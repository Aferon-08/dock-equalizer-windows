#include "SystemAudio.h"
#include "SpectrumAnalyzer.h"

#ifdef Q_OS_WIN
#include <QtCore/qt_windows.h>
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

namespace {

using Microsoft::WRL::ComPtr;
using namespace std::chrono_literals;

struct ComApartment
{
    const HRESULT status = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    ~ComApartment() { if (SUCCEEDED(status)) CoUninitialize(); }
};

struct FreeTaskMemory
{
    void operator()(void *ptr) const { CoTaskMemFree(ptr); }
};

using StereoWeights = std::vector<std::array<float, 2>>;

StereoWeights channelWeights(unsigned channels, DWORD mask)
{
    if (channels == 1)
        return {{1.0f, 1.0f}};

    constexpr DWORD left = SPEAKER_FRONT_LEFT_OF_CENTER | SPEAKER_BACK_LEFT
        | SPEAKER_SIDE_LEFT | SPEAKER_TOP_FRONT_LEFT | SPEAKER_TOP_BACK_LEFT;
    constexpr DWORD right = SPEAKER_FRONT_RIGHT_OF_CENTER | SPEAKER_BACK_RIGHT
        | SPEAKER_SIDE_RIGHT | SPEAKER_TOP_FRONT_RIGHT | SPEAKER_TOP_BACK_RIGHT;
    StereoWeights weights;
    // Extensible PCM channels are ordered by increasing speaker bit.
    for (DWORD bit = 1; mask && bit; bit <<= 1) {
        if (!(bit & mask))
            continue;
        if (bit == SPEAKER_FRONT_LEFT)
            weights.push_back({1.0f, 0.0f});
        else if (bit == SPEAKER_FRONT_RIGHT)
            weights.push_back({0.0f, 1.0f});
        else if (bit & left)
            weights.push_back({0.707f, 0.0f});
        else if (bit & right)
            weights.push_back({0.0f, 0.707f});
        else
            weights.push_back({0.5f, 0.5f});
    }
    if (weights.size() == channels)
        return weights;

    weights.assign(channels, {0.5f, 0.5f});
    weights[0] = {1.0f, 0.0f};
    weights[1] = {0.0f, 1.0f};
    return weights;
}

std::optional<PcmEncoding> pcmEncoding(WORD tag, WORD bits)
{
    if (tag == WAVE_FORMAT_PCM) {
        switch (bits) {
        case 8: return PcmEncoding::Unsigned8;
        case 16: return PcmEncoding::Signed16;
        case 24: return PcmEncoding::Signed24;
        case 32: return PcmEncoding::Signed32;
        }
    }
    if (tag == WAVE_FORMAT_IEEE_FLOAT) {
        if (bits == 32)
            return PcmEncoding::Float32;
        if (bits == 64)
            return PcmEncoding::Float64;
    }
    return std::nullopt;
}

std::optional<SpectrumInput> spectrumInput(const WAVEFORMATEX &wave)
{
    WORD tag = wave.wFormatTag;
    DWORD mask = 0;
    if (tag == WAVE_FORMAT_EXTENSIBLE) {
        if (wave.cbSize < sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX))
            return std::nullopt;
        const auto &ext = reinterpret_cast<const WAVEFORMATEXTENSIBLE &>(wave);
        constexpr GUID pcm{DEFINE_WAVEFORMATEX_GUID(WAVE_FORMAT_PCM)};
        constexpr GUID ieeeFloat{DEFINE_WAVEFORMATEX_GUID(WAVE_FORMAT_IEEE_FLOAT)};
        if (IsEqualGUID(ext.SubFormat, pcm))
            tag = WAVE_FORMAT_PCM;
        else if (IsEqualGUID(ext.SubFormat, ieeeFloat))
            tag = WAVE_FORMAT_IEEE_FLOAT;
        mask = ext.dwChannelMask;
    }

    const auto encoding = pcmEncoding(tag, wave.wBitsPerSample);
    if (!encoding || wave.nSamplesPerSec < 8000 || wave.nSamplesPerSec > 768000
            || wave.nChannels == 0 || wave.nChannels > 32
            || wave.nBlockAlign < wave.nChannels * (wave.wBitsPerSample / 8))
        return std::nullopt;

    return SpectrumInput{int(wave.nSamplesPerSec), wave.nBlockAlign, *encoding,
                         channelWeights(wave.nChannels, mask)};
}

std::wstring endpointId(IMMDevice *device)
{
    LPWSTR id = nullptr;
    const HRESULT result = device ? device->GetId(&id) : E_POINTER;
    const std::unique_ptr<wchar_t, FreeTaskMemory> memory(id);
    return SUCCEEDED(result) && id ? std::wstring(id) : std::wstring();
}

class LoopbackStream
{
public:
    ~LoopbackStream()
    {
        if (m_started)
            m_client->Stop();
    }

    bool start(IMMDevice *endpoint)
    {
        if (FAILED(endpoint->Activate(__uuidof(IAudioClient), CLSCTX_INPROC_SERVER, nullptr,
                reinterpret_cast<void **>(m_client.GetAddressOf()))))
            return false;

        WAVEFORMATEX *mix = nullptr;
        const HRESULT formatResult = m_client->GetMixFormat(&mix);
        const std::unique_ptr<WAVEFORMATEX, FreeTaskMemory> format(mix);
        if (FAILED(formatResult) || !format)
            return false;
        auto input = spectrumInput(*format);
        if (!input)
            return false;

        // Poll at the display cadence with a 100 ms shared-mode buffer.
        constexpr REFERENCE_TIME bufferDuration = 1'000'000;
        if (FAILED(m_client->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
                    bufferDuration, 0, format.get(), nullptr))
                || FAILED(m_client->GetService(IID_PPV_ARGS(m_packets.GetAddressOf()))))
            return false;

        m_analyzer.emplace(std::move(*input));
        m_started = SUCCEEDED(m_client->Start());
        return m_started;
    }

    bool update(ULONGLONG now, SpectrumBands &bands)
    {
        for (int i = 0; i < 64; ++i) {
            UINT32 next = 0;
            if (FAILED(m_packets->GetNextPacketSize(&next)))
                return false;
            if (!next)
                break;

            BYTE *data = nullptr;
            UINT32 frames = 0;
            DWORD flags = 0;
            const HRESULT result = m_packets->GetBuffer(&data, &frames, &flags, nullptr, nullptr);
            if (FAILED(result))
                return false;
            if (result == AUDCLNT_S_BUFFER_EMPTY)
                break;

            if (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY)
                m_analyzer->clearHistory();
            m_analyzer->append((flags & AUDCLNT_BUFFERFLAGS_SILENT) ? nullptr : data, frames);
            if (FAILED(m_packets->ReleaseBuffer(frames)))
                return false;
            m_lastPacket = now;
        }

        // A render endpoint can stop producing packets when its mix is idle.
        if (m_lastPacket && now - m_lastPacket > 120) {
            m_analyzer->clearHistory();
            m_lastPacket = 0;
        }
        bands = m_analyzer->update();
        return true;
    }

private:
    ComPtr<IAudioClient> m_client;
    ComPtr<IAudioCaptureClient> m_packets;
    std::optional<SpectrumAnalyzer> m_analyzer;
    bool m_started = false;
    ULONGLONG m_lastPacket = 0;
};

} // namespace

class SystemAudio::Capture
{
public:
    explicit Capture(SystemAudio *owner)
        : m_owner(owner), m_thread([this] { run(); })
    {
    }

    ~Capture()
    {
        {
            const std::lock_guard lock(m_mutex);
            m_stopping = true;
        }
        m_wake.notify_one();
        m_thread.join();
    }

private:
    void publish(const SpectrumBands &bands)
    {
        {
            const std::lock_guard lock(m_mutex);
            if (m_stopping || m_latest == bands)
                return;
            m_latest = bands;
            if (m_applyQueued)
                return;
            m_applyQueued = true;
        }
        QMetaObject::invokeMethod(m_owner, [this] {
            SpectrumBands latest;
            {
                const std::lock_guard lock(m_mutex);
                latest = m_latest;
                m_applyQueued = false;
            }
            QVariantList values;
            values.reserve(latest.size());
            for (int level : latest)
                values.append(level);
            m_owner->m_bands = std::move(values);
            m_owner->m_audible = std::any_of(latest.begin(), latest.end(), [](int level) {
                return level > 5;
            });
            emit m_owner->changed();
        }, Qt::QueuedConnection);
    }

    void run()
    {
        const ComApartment apartment;
        if (FAILED(apartment.status))
            return;

        ComPtr<IMMDeviceEnumerator> devices;
        std::optional<LoopbackStream> stream;
        std::wstring activeId;
        ULONGLONG nextProbe = 0;
        ULONGLONG previousTick = GetTickCount64();
        for (;;) {
            const ULONGLONG now = GetTickCount64();
            if (now - previousTick > 2000) {
                // A long suspension can leave the previous client stale.
                stream.reset();
                publish({});
                nextProbe = now;
            }
            previousTick = now;
            if (now >= nextProbe) {
                nextProbe = now + 500;
                if (!devices)
                    CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER,
                                     IID_PPV_ARGS(devices.GetAddressOf()));
                ComPtr<IMMDevice> device;
                if (devices)
                    devices->GetDefaultAudioEndpoint(eRender, eMultimedia, device.GetAddressOf());
                const auto id = endpointId(device.Get());
                if (stream && id != activeId) {
                    stream.reset();
                    publish({});
                }
                if (!stream && !id.empty()) {
                    if (stream.emplace().start(device.Get()))
                        activeId = id;
                    else
                        stream.reset();
                }
            }
            if (stream) {
                SpectrumBands bands;
                if (stream->update(now, bands)) {
                    publish(bands);
                } else {
                    stream.reset();
                    publish({});
                }
            }
            std::unique_lock lock(m_mutex);
            if (m_wake.wait_for(lock, stream ? 33ms : 500ms, [this] { return m_stopping; }))
                return;
        }
    }

    SystemAudio *const m_owner;
    std::mutex m_mutex;
    std::condition_variable m_wake;
    SpectrumBands m_latest{};
    bool m_applyQueued = false;
    bool m_stopping = false;
    std::thread m_thread;
};
#endif

SystemAudio::SystemAudio(bool enabled)
    : m_bands(SpectrumBands{}.size(), QVariant(0))
{
#ifdef Q_OS_WIN
    if (enabled)
        m_capture = std::make_unique<Capture>(this);
#else
    Q_UNUSED(enabled);
#endif
}

SystemAudio::~SystemAudio() = default;
