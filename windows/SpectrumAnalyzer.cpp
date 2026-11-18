#include "SpectrumAnalyzer.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>

namespace {

constexpr double twoPi = 6.283185307179586;

std::size_t sampleBytes(PcmEncoding encoding)
{
    switch (encoding) {
    case PcmEncoding::Unsigned8: return 1;
    case PcmEncoding::Signed16: return 2;
    case PcmEncoding::Signed24: return 3;
    case PcmEncoding::Signed32:
    case PcmEncoding::Float32: return 4;
    case PcmEncoding::Float64: return 8;
    }
    return 0;
}

template<typename T>
T loadSample(const std::uint8_t *bytes)
{
    T value;
    std::memcpy(&value, bytes, sizeof(value));
    return value;
}

float sampleAt(const std::uint8_t *bytes, PcmEncoding encoding)
{
    switch (encoding) {
    case PcmEncoding::Unsigned8:
        return (int(bytes[0]) - 128) / 128.0f;
    case PcmEncoding::Signed16:
        return loadSample<std::int16_t>(bytes) / 32768.0f;
    case PcmEncoding::Signed24: {
        const auto value = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16);
        return (value - ((value & 0x800000) ? 0x1000000 : 0)) / 8388608.0f;
    }
    case PcmEncoding::Signed32:
        return loadSample<std::int32_t>(bytes) / 2147483648.0f;
    case PcmEncoding::Float32: {
        const float value = loadSample<float>(bytes);
        return std::isfinite(value) ? std::clamp(value, -1.0f, 1.0f) : 0;
    }
    case PcmEncoding::Float64: {
        const double value = loadSample<double>(bytes);
        return std::isfinite(value) ? float(std::clamp(value, -1.0, 1.0)) : 0;
    }
    }
    return 0;
}

} // namespace

SpectrumAnalyzer::SpectrumAnalyzer(SpectrumInput input)
    : m_input(std::move(input)), m_sampleBytes(sampleBytes(m_input.encoding))
{
    // Keep a similar window duration at common output sample rates.
    while (m_fftSize < 16384 && m_fftSize * 12 < std::size_t(m_input.sampleRate))
        m_fftSize *= 2;
    for (auto &channel : m_history)
        channel.resize(m_fftSize);
    m_bitOrder.resize(m_fftSize);
    m_window.resize(m_fftSize);
    m_twiddles.resize(m_fftSize / 2);
    m_fft.resize(m_fftSize);
    for (std::size_t i = 0; i < m_fftSize; ++i) {
        m_bitOrder[i] = (m_bitOrder[i / 2] >> 1) | ((i & 1) ? m_fftSize / 2 : 0);
        m_window[i] = float(0.5 - 0.5 * std::cos(twoPi * i / m_fftSize));
    }
    for (std::size_t i = 0; i < m_twiddles.size(); ++i)
        m_twiddles[i] = std::polar(1.0f, float(-twoPi * i / m_fftSize));

    constexpr double low = 40;
    const double high = std::min(20000.0, m_input.sampleRate / 2.0);
    const double binWidth = double(m_input.sampleRate) / m_fftSize;
    const double ratio = std::pow(high / low, 1.0 / bandsPerChannel);
    for (std::size_t band = 0; band < bandsPerChannel; ++band) {
        const auto start = std::size_t(std::ceil(low * std::pow(ratio, band) / binWidth));
        const auto end = std::size_t(std::ceil(low * std::pow(ratio, band + 1) / binWidth));
        const auto first = std::clamp(start, std::size_t(1), m_fftSize / 2 - 1);
        m_binRanges[band] = {first, std::clamp(end, first + 1, m_fftSize / 2)};
    }
}

void SpectrumAnalyzer::append(const void *packet, std::size_t frames)
{
    if (!frames)
        return;
    const auto *bytes = static_cast<const std::uint8_t *>(packet);
    if (frames > m_fftSize) {
        if (bytes)
            bytes += (frames - m_fftSize) * m_input.frameBytes;
        frames = m_fftSize;
    }

    const auto &weights = m_input.channelWeights;
    for (std::size_t i = 0; i < frames; ++i) {
        float left = 0;
        float right = 0;
        if (bytes) {
            for (std::size_t ch = 0; ch < weights.size(); ++ch) {
                const float value = sampleAt(bytes + ch * m_sampleBytes, m_input.encoding);
                left += value * weights[ch][0];
                right += value * weights[ch][1];
            }
            bytes += m_input.frameBytes;
        }
        m_history[0][m_writeIndex] = left;
        m_history[1][m_writeIndex] = right;
        m_writeIndex = (m_writeIndex + 1) & (m_fftSize - 1);
    }
    m_dirty = true;
}

void SpectrumAnalyzer::clearHistory()
{
    for (auto &channel : m_history)
        std::fill(channel.begin(), channel.end(), 0);
    m_writeIndex = 0;
    m_measured.fill(0);
    m_dirty = false;
}

void SpectrumAnalyzer::measure(std::size_t side)
{
    const auto offset = side * bandsPerChannel;
    bool hasSignal = false;
    for (std::size_t i = 0; i < m_fftSize; ++i) {
        const float value = m_history[side][(m_writeIndex + i) & (m_fftSize - 1)];
        m_fft[m_bitOrder[i]] = value * m_window[i];
        hasSignal |= std::abs(value) > 0.0002f;
    }
    if (!hasSignal) {
        std::fill_n(m_measured.begin() + offset, bandsPerChannel, 0);
        return;
    }

    for (std::size_t width = 2; width <= m_fftSize; width *= 2) {
        const auto half = width / 2;
        const auto step = m_fftSize / width;
        for (std::size_t i = 0; i < m_fftSize; i += width) {
            for (std::size_t j = 0; j < half; ++j) {
                const auto left = m_fft[i + j];
                const auto right = m_fft[i + j + half] * m_twiddles[j * step];
                m_fft[i + j] = left + right;
                m_fft[i + j + half] = left - right;
            }
        }
    }
    // Normalize for the Hann window and lift quiet passages with a soft curve.
    for (std::size_t band = 0; band < bandsPerChannel; ++band) {
        const auto [start, end] = m_binRanges[band];
        float peakSquared = 0;
        for (auto bin = start; bin < end; ++bin)
            peakSquared = std::max(peakSquared, std::norm(m_fft[bin]));
        const auto amplitude = std::max(0.0f, std::sqrt(peakSquared) * (4.0f / m_fftSize) - 0.0002f);
        m_measured[offset + band] = 1000.0f * std::min(1.0f,
            std::log1p(24.0f * amplitude) / std::log1p(12.0f));
    }
}

SpectrumBands SpectrumAnalyzer::update()
{
    if (m_dirty) {
        measure(0);
        measure(1);
        m_dirty = false;
    }

    SpectrumBands bands{};
    for (std::size_t i = 0; i < bands.size(); ++i) {
        auto &level = m_smoothed[i];
        const auto target = m_measured[i];
        level += (target - level) * (target > level ? 0.72f : 0.31f);
        if (level < 0.5f)
            level = 0;
        bands[i] = int(std::lround(level));
    }
    return bands;
}
