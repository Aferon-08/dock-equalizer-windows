#include "WinMediaWorker.h"
#include "WinMediaAbi.h"

#include <QBuffer>
#include <QImageReader>
#include <QMetaObject>
#include <QVariantMap>

#include <appmodel.h>
#include <asyncinfo.h>
#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <roapi.h>
#include <shcore.h>
#include <winstring.h>
#include <wrl/client.h>

#include <iterator>
#include <utility>

namespace {

using Microsoft::WRL::ComPtr;
using namespace winmedia;
using namespace std::chrono_literals;
constexpr double ticksPerSecond = 10'000'000.0;

struct Apartment
{
    const HRESULT status = RoInitialize(RO_INIT_MULTITHREADED);
    ~Apartment() { if (SUCCEEDED(status)) RoUninitialize(); }
};

template<class Interface, class Getter>
QString stringProperty(Interface *object, Getter getter)
{
    HSTRING value = nullptr;
    QString result;
    if (SUCCEEDED((object->*getter)(&value)) && value) {
        UINT32 size = 0;
        const wchar_t *text = WindowsGetStringRawBuffer(value, &size);
        result = QString::fromWCharArray(text, size).trimmed();
    }
    WindowsDeleteString(value);
    return result;
}

template<class T>
bool await(AsyncOperation<T> *operation, T *result, const std::atomic_bool &stopping,
           std::chrono::milliseconds timeout = 800ms)
{
    if (!operation)
        return false;
    ComPtr<IAsyncInfo> info;
    if (FAILED(operation->QueryInterface(__uuidof(IAsyncInfo),
            reinterpret_cast<void **>(info.GetAddressOf()))))
        return false;

    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (!stopping && std::chrono::steady_clock::now() < deadline) {
        AsyncStatus status{};
        if (FAILED(info->get_Status(&status)))
            return false;
        if (status == AsyncStatus::Completed)
            return SUCCEEDED(operation->GetResults(result));
        if (status != AsyncStatus::Started)
            return false;
        std::this_thread::sleep_for(10ms);
    }
    info->Cancel();
    return false;
}

ComPtr<IUnknown> identity(Session *session)
{
    ComPtr<IUnknown> key;
    if (session)
        session->QueryInterface(__uuidof(IUnknown), reinterpret_cast<void **>(key.GetAddressOf()));
    return key;
}

bool isGameBarSource(const QString &appId)
{
    const QString package = appId.section(u'!', 0, 0);
    return package.compare(QLatin1StringView("Microsoft.XboxGamingOverlay_8wekyb3d8bbwe"),
                           Qt::CaseInsensitive) == 0
        || package.compare(QLatin1StringView("Microsoft.XboxGamingOverlay"),
                           Qt::CaseInsensitive) == 0;
}

QString sourceLabel(const QString &appId)
{
    for (const auto &pair : {std::pair{"spotify", "Spotify"}, {"firefox", "Firefox"},
                           {"chrome", "Chrome"}, {"msedge", "Microsoft Edge"}, {"vlc", "VLC"}}) {
        if (appId.contains(QLatin1StringView(pair.first), Qt::CaseInsensitive))
            return QString::fromLatin1(pair.second);
    }
    return appId.isEmpty() ? QStringLiteral("Медиаплеер") : appId.section(u'!', 0, 0);
}

class PropertiesChanged final : public PropertiesChangedHandler
{
public:
    const std::shared_ptr<std::atomic_uint64_t> revision = std::make_shared<std::atomic_uint64_t>(0);

    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **out) override
    {
        if (!out)
            return E_POINTER;
        *out = nullptr;
        if (iid != __uuidof(IUnknown) && iid != __uuidof(IAgileObject)
                && iid != propertiesChangedHandlerId)
            return E_NOINTERFACE;
        *out = static_cast<PropertiesChangedHandler *>(this);
        AddRef();
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++m_refs; }
    ULONG STDMETHODCALLTYPE Release() override
    {
        const ULONG refs = --m_refs;
        if (!refs)
            delete this;
        return refs;
    }
    HRESULT STDMETHODCALLTYPE Invoke(Session *, IInspectable *) override
    {
        ++*revision;
        return S_OK;
    }

private:
    std::atomic_ulong m_refs = 1;
};

QUrl thumbnail(Properties *properties, const std::atomic_bool &stopping)
{
    ComPtr<StreamReference> reference;
    ComPtr<AsyncOperation<IInspectable *>> operation;
    ComPtr<IInspectable> stream;
    ComPtr<IStream> input;
    if (FAILED(properties->get_Thumbnail(reference.GetAddressOf())) || !reference
            || FAILED(reference->OpenReadAsync(operation.GetAddressOf()))
            || !await(operation.Get(), stream.GetAddressOf(), stopping, 450ms) || !stream
            || FAILED(CreateStreamOverRandomAccessStream(stream.Get(), __uuidof(IStream),
                reinterpret_cast<void **>(input.GetAddressOf()))))
        return {};

    constexpr quint64 maxFileBytes = 6 * 1024 * 1024;
    STATSTG info{};
    if (FAILED(input->Stat(&info, STATFLAG_NONAME)) || info.cbSize.QuadPart == 0
            || info.cbSize.QuadPart > maxFileBytes)
        return {};
    QByteArray bytes(info.cbSize.QuadPart, Qt::Uninitialized);
    ULONG size = 0;
    if (FAILED(input->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &size)) || !size)
        return {};
    bytes.resize(size);

    QBuffer buffer(&bytes);
    buffer.open(QIODevice::ReadOnly);
    QImageReader reader(&buffer);
    const QSize dimensions = reader.size();
    if (dimensions.isEmpty() || qint64(dimensions.width()) * dimensions.height() > 25'000'000)
        return {};
    reader.setAutoTransform(true);
    reader.setScaledSize(dimensions.scaled(256, 256, Qt::KeepAspectRatio));
    const QImage image = reader.read();
    QByteArray encoded;
    QBuffer destination(&encoded);
    destination.open(QIODevice::WriteOnly);
    if (image.isNull() || !image.save(&destination, "PNG"))
        return {};
    return QUrl::fromEncoded(QByteArrayLiteral("data:image/png;base64,") + encoded.toBase64());
}

bool capability(PlaybackControls *controls, HRESULT (STDMETHODCALLTYPE PlaybackControls::*getter)(boolean *))
{
    boolean enabled = false;
    return controls && SUCCEEDED((controls->*getter)(&enabled)) && enabled;
}

bool processMatches(DWORD pid, const QString &appId)
{
    const HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!process)
        return false;
    wchar_t name[256]{};
    UINT32 size = std::size(name);
    const LONG status = GetApplicationUserModelId(process, &size, name);
    CloseHandle(process);
    return status == ERROR_SUCCESS && QString::fromWCharArray(name).compare(appId, Qt::CaseInsensitive) == 0;
}

ComPtr<ISimpleAudioVolume> uniqueVolume(const QString &appId)
{
    // Only use an exact package application identity from both APIs. A
    // friendly name or executable basename is insufficient to set volume.
    if (!appId.contains(u'!'))
        return {};
    ComPtr<IMMDeviceEnumerator> devices;
    ComPtr<IMMDevice> endpoint;
    ComPtr<IAudioSessionManager2> manager;
    ComPtr<IAudioSessionEnumerator> sessions;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(devices.GetAddressOf())))
            || FAILED(devices->GetDefaultAudioEndpoint(eRender, eMultimedia, endpoint.GetAddressOf()))
            || FAILED(endpoint->Activate(__uuidof(IAudioSessionManager2), CLSCTX_INPROC_SERVER,
                nullptr, reinterpret_cast<void **>(manager.GetAddressOf())))
            || FAILED(manager->GetSessionEnumerator(sessions.GetAddressOf())))
        return {};

    int count = 0;
    if (FAILED(sessions->GetCount(&count)))
        return {};
    ComPtr<ISimpleAudioVolume> match;
    for (int i = 0; i < count; ++i) {
        ComPtr<IAudioSessionControl> control;
        ComPtr<IAudioSessionControl2> details;
        AudioSessionState state{};
        DWORD pid = 0;
        if (FAILED(sessions->GetSession(i, control.GetAddressOf()))
                || FAILED(control->GetState(&state)) || state == AudioSessionStateExpired
                || FAILED(control.As(&details)) || details->GetProcessId(&pid) != S_OK
                || !pid || !processMatches(pid, appId))
            continue;
        if (match || FAILED(control.As(&match)))
            return {};
    }
    return match;
}

struct SessionEntry
{
    QString id;
    QString appId;
    ComPtr<IUnknown> key;
    ComPtr<Session> session;
};

bool isPlaying(const SessionEntry &entry)
{
    ComPtr<PlaybackInfo> info;
    PlaybackStatus status{};
    return SUCCEEDED(entry.session->GetPlaybackInfo(info.GetAddressOf())) && info
        && SUCCEEDED(info->get_PlaybackStatus(&status)) && status == PlaybackStatus::Playing;
}

class SessionBroker
{
public:
    explicit SessionBroker(const std::atomic_bool &stopping) : m_stopping(stopping) {}
    ~SessionBroker() { clearSelection(); }

    void read(MediaUpdate &update)
    {
        if (!m_manager && !connectManager())
            return;

        ComPtr<VectorView<Session *>> sessions;
        UINT32 count = 0;
        if (FAILED(m_manager->GetSessions(sessions.GetAddressOf())) || !sessions
                || FAILED(sessions->get_Size(&count))) {
            clearSelection();
            m_entries.clear();
            m_manager.Reset();
            return;
        }

        std::vector<SessionEntry> entries;
        for (UINT32 i = 0; i < count; ++i) {
            ComPtr<Session> session;
            if (SUCCEEDED(sessions->GetAt(i, session.GetAddressOf())) && session)
                append(entries, std::move(session));
        }
        ComPtr<Session> current;
        m_manager->GetCurrentSession(current.GetAddressOf());
        const QString currentId = resolveCurrent(entries, std::move(current));

        update.available = true;
        for (const auto &entry : entries) {
            QString label = sourceLabel(entry.appId);
            if (std::count_if(entries.begin(), entries.end(), [&entry](const SessionEntry &other) {
                    return other.appId == entry.appId;
                }) > 1)
                label += QStringLiteral(" · ") + entry.id;
            update.sessions.append(QVariantMap{{QStringLiteral("id"), entry.id},
                                               {QStringLiteral("label"), label}});
        }

        const SessionEntry *selected = nullptr;
        for (const auto &entry : entries) {
            if (entry.id == update.preference)
                selected = &entry;
        }
        if (!selected) {
            update.preference.clear();
            for (const auto &entry : entries) {
                if (entry.id == currentId)
                    selected = &entry;
            }
            if (!selected && !entries.empty()) {
                selected = &entries.front();
                for (const auto &entry : entries) {
                    if (isPlaying(entry)) {
                        selected = &entry;
                        break;
                    }
                    if (entry.id == m_state.sessionId)
                        selected = &entry;
                }
            }
        }

        if (selected && m_state.sessionId != selected->id)
            select(*selected);
        else if (!selected)
            clearSelection();
        m_entries = std::move(entries);

        if (m_selected) {
            readProperties();
            readTimeline();
            readVolume();
        }
        update.state = m_state;
    }

    bool selectionStillCurrent(const QString &preference) const
    {
        if (!preference.isEmpty() || !m_manager || !m_selected)
            return true;
        ComPtr<Session> current;
        if (FAILED(m_manager->GetCurrentSession(current.GetAddressOf())))
            return false;
        if (!current || identity(current.Get()).Get() == identity(m_selected.Get()).Get())
            return true;
        const QString appId = stringProperty(current.Get(), &Session::get_SourceAppUserModelId);
        // The broker may keep Game Bar current even when another session plays.
        if (isGameBarSource(appId))
            return true;
        const auto *matchingApp = uniqueApp(m_entries, appId);
        return matchingApp && matchingApp->id == m_state.sessionId;
    }

    bool execute(const MediaCommand &command)
    {
        if (!m_selected || command.sessionId != m_state.sessionId
                || command.trackKey != m_state.trackKey)
            return false;

        if (command.action == MediaAction::Volume || command.action == MediaAction::ToggleMute) {
            const auto target = uniqueVolume(m_appId);
            if (!target)
                return false;
            if (command.action == MediaAction::ToggleMute) {
                BOOL muted = FALSE;
                return SUCCEEDED(target->GetMute(&muted)) && SUCCEEDED(target->SetMute(!muted, nullptr));
            }
            if (FAILED(target->SetMasterVolume(static_cast<float>(command.value), nullptr)))
                return false;
            return command.value <= 0 || SUCCEEDED(target->SetMute(FALSE, nullptr));
        }

        ComPtr<AsyncOperation<boolean>> operation;
        HRESULT result = E_NOTIMPL;
        switch (command.action) {
        case MediaAction::TogglePlaying:
            if (m_canToggle)
                result = m_selected->TryTogglePlayPauseAsync(operation.GetAddressOf());
            else if (m_state.timeline.playing && m_canPause)
                result = m_selected->TryPauseAsync(operation.GetAddressOf());
            else if (!m_state.timeline.playing && m_canPlay)
                result = m_selected->TryPlayAsync(operation.GetAddressOf());
            break;
        case MediaAction::Next:
            if (m_state.canGoNext)
                result = m_selected->TrySkipNextAsync(operation.GetAddressOf());
            break;
        case MediaAction::Previous:
            if (m_state.canGoPrevious)
                result = m_selected->TrySkipPreviousAsync(operation.GetAddressOf());
            break;
        case MediaAction::Seek:
            if (m_state.canSeek) {
                const auto target = static_cast<INT64>(std::clamp(
                    m_start + command.value * ticksPerSecond, m_minSeek, m_maxSeek));
                result = m_selected->TryChangePlaybackPositionAsync(target, operation.GetAddressOf());
            }
            break;
        case MediaAction::Volume:
        case MediaAction::ToggleMute:
            break;
        }
        boolean accepted = false;
        return SUCCEEDED(result) && await(operation.Get(), &accepted, m_stopping) && accepted;
    }

private:
    bool connectManager()
    {
        HSTRING_HEADER storage{};
        HSTRING className = nullptr;
        if (FAILED(WindowsCreateStringReference(sessionManagerClass,
                std::size(sessionManagerClass) - 1, &storage, &className)))
            return false;
        ComPtr<SessionManagerFactory> factory;
        ComPtr<AsyncOperation<SessionManager *>> operation;
        return SUCCEEDED(RoGetActivationFactory(className, sessionManagerFactoryId,
                    reinterpret_cast<void **>(factory.GetAddressOf())))
            && SUCCEEDED(factory->RequestAsync(operation.GetAddressOf()))
            && await(operation.Get(), m_manager.GetAddressOf(), m_stopping, 2000ms)
            && m_manager;
    }

    void append(std::vector<SessionEntry> &entries, ComPtr<Session> session)
    {
        auto key = identity(session.Get());
        if (!key)
            return;
        const auto old = std::find_if(m_entries.begin(), m_entries.end(), [&key](const SessionEntry &entry) {
            return entry.key.Get() == key.Get();
        });
        const QString appId = old != m_entries.end() && !old->appId.isEmpty()
            ? old->appId : stringProperty(session.Get(), &Session::get_SourceAppUserModelId);
        if (isGameBarSource(appId))
            return;

        const QString id = old == m_entries.end() ? QString::number(++m_nextId) : old->id;
        entries.push_back({id, appId, std::move(key), std::move(session)});
    }

    static const SessionEntry *uniqueApp(const std::vector<SessionEntry> &entries, const QString &appId)
    {
        const SessionEntry *match = nullptr;
        if (appId.isEmpty())
            return match;
        for (const auto &entry : entries) {
            if (entry.appId != appId)
                continue;
            if (match)
                return nullptr;
            match = &entry;
        }
        return match;
    }

    QString resolveCurrent(std::vector<SessionEntry> &entries, ComPtr<Session> session)
    {
        const auto key = identity(session.Get());
        if (!key)
            return {};
        const auto exact = std::find_if(entries.begin(), entries.end(), [&key](const SessionEntry &entry) {
            return entry.key.Get() == key.Get();
        });
        if (exact != entries.end())
            return exact->id;
        if (const auto *match = uniqueApp(entries,
                stringProperty(session.Get(), &Session::get_SourceAppUserModelId)))
            return match->id;
        const auto previousSize = entries.size();
        append(entries, std::move(session));
        return entries.size() > previousSize ? entries.back().id : QString{};
    }

    void clearSelection()
    {
        if (m_selected && m_listening)
            m_selected->remove_MediaPropertiesChanged(m_token);
        m_selected.Reset();
        m_revision.reset();
        m_listening = false;
        m_state = {};
        m_appId.clear();
        m_probeAfter = 0;
        m_lastRevision = 0;
    }

    void select(const SessionEntry &entry)
    {
        clearSelection();
        m_selected = entry.session;
        m_appId = entry.appId;
        m_state.sessionId = entry.id;
        m_state.sourceName = sourceLabel(m_appId);
        m_state.trackKey = entry.id;
        ComPtr<PropertiesChanged> callback;
        callback.Attach(new PropertiesChanged);
        m_revision = callback.Get()->revision;
        m_listening = SUCCEEDED(m_selected->add_MediaPropertiesChanged(callback.Get(), &m_token));
    }

    void readProperties()
    {
        const auto revision = m_revision->load();
        const auto now = playbackTimeMs();
        if (revision == m_lastRevision && now < m_probeAfter)
            return;

        ComPtr<AsyncOperation<Properties *>> operation;
        ComPtr<Properties> properties;
        if (FAILED(m_selected->TryGetMediaPropertiesAsync(operation.GetAddressOf()))
                || !await(operation.Get(), properties.GetAddressOf(), m_stopping) || !properties) {
            m_probeAfter = now + 1000;
            m_lastRevision = revision;
            return;
        }
        const QString title = stringProperty(properties.Get(), &Properties::get_Title);
        const QString artist = stringProperty(properties.Get(), &Properties::get_Artist);
        const QString album = stringProperty(properties.Get(), &Properties::get_AlbumTitle);
        INT32 track = 0;
        properties->get_TrackNumber(&track);
        const QString key = m_state.sessionId + u'\x1f' + title + u'\x1f' + artist
            + u'\x1f' + album + u'\x1f' + QString::number(track);

        QUrl art = m_state.artUrl;
        if (key != m_state.trackKey || revision != m_lastRevision || art.isEmpty())
            art = thumbnail(properties.Get(), m_stopping);
        if (revision != m_revision->load())
            return;

        m_state.trackKey = key;
        m_state.title = title;
        m_state.artist = artist;
        m_state.album = album;
        m_state.artUrl = std::move(art);
        m_lastRevision = revision;
        m_probeAfter = playbackTimeMs() + (m_listening ? 4000 : 1200);
    }

    void readTimeline()
    {
        ComPtr<PlaybackInfo> info;
        ComPtr<PlaybackControls> controls;
        PlaybackStatus status = PlaybackStatus::Closed;
        double rate = 1;
        if (SUCCEEDED(m_selected->GetPlaybackInfo(info.GetAddressOf())) && info) {
            info->get_PlaybackStatus(&status);
            info->get_Controls(controls.GetAddressOf());
            ComPtr<BoxedDouble> boxed;
            if (SUCCEEDED(info->get_PlaybackRate(boxed.GetAddressOf())) && boxed)
                boxed->get_Value(&rate);
        }
        TimelineSample sample;
        sample.playing = status == PlaybackStatus::Playing;
        sample.rate = rate;
        sample.observedMs = playbackTimeMs();
        m_canPlay = capability(controls.Get(), &PlaybackControls::get_IsPlayEnabled);
        m_canPause = capability(controls.Get(), &PlaybackControls::get_IsPauseEnabled);
        m_canToggle = capability(controls.Get(), &PlaybackControls::get_IsPlayPauseToggleEnabled);
        m_state.canTogglePlaying = m_canToggle || (sample.playing ? m_canPause : m_canPlay);
        m_state.canGoNext = capability(controls.Get(), &PlaybackControls::get_IsNextEnabled);
        m_state.canGoPrevious = capability(controls.Get(), &PlaybackControls::get_IsPreviousEnabled);
        m_state.canSeek = false;

        ComPtr<Timeline> timeline;
        WinTime start{}, end{}, position{}, updated{}, min{}, max{};
        if (SUCCEEDED(m_selected->GetTimelineProperties(timeline.GetAddressOf())) && timeline
                && SUCCEEDED(timeline->get_StartTime(&start)) && SUCCEEDED(timeline->get_Position(&position))) {
            timeline->get_EndTime(&end);
            timeline->get_LastUpdatedTime(&updated);
            m_start = static_cast<double>(start.ticks);
            sample.position = std::max(0.0, (position.ticks - m_start) / ticksPerSecond);
            if (end.ticks > start.ticks && end.ticks < INT64_MAX / 2)
                sample.duration = (end.ticks - m_start) / ticksPerSecond;
            sample.sourceTimestamp = updated.ticks;
            sample.valid = position.ticks >= 0 && (updated.ticks > 0 || position.ticks > 0 || sample.duration > 0);
            FILETIME wallClock{};
            GetSystemTimeAsFileTime(&wallClock);
            const quint64 wallTicks = (quint64(wallClock.dwHighDateTime) << 32) | wallClock.dwLowDateTime;
            if (updated.ticks > 0 && quint64(updated.ticks) <= wallTicks) {
                const double age = (wallTicks - quint64(updated.ticks)) / ticksPerSecond;
                if (age <= 3600)
                    sample.ageSeconds = age;
            }
            timeline->get_MinSeekTime(&min);
            timeline->get_MaxSeekTime(&max);
            m_minSeek = min.ticks < max.ticks ? std::max(m_start, double(min.ticks)) : m_start;
            m_maxSeek = min.ticks < max.ticks
                ? std::min(double(end.ticks), double(max.ticks)) : double(end.ticks);
            m_state.canSeek = sample.valid && sample.duration > 0 && m_maxSeek > m_minSeek
                && capability(controls.Get(), &PlaybackControls::get_IsPlaybackPositionEnabled);
        }
        m_state.timeline = sample;
    }

    void readVolume()
    {
        const auto volume = uniqueVolume(m_appId);
        float value = 0;
        BOOL muted = FALSE;
        m_state.volumeSupported = volume && SUCCEEDED(volume->GetMasterVolume(&value))
            && SUCCEEDED(volume->GetMute(&muted));
        m_state.volume = m_state.volumeSupported && !muted ? value : 0;
    }

    const std::atomic_bool &m_stopping;
    ComPtr<SessionManager> m_manager;
    std::vector<SessionEntry> m_entries;
    quint64 m_nextId = 0;
    ComPtr<Session> m_selected;
    QString m_appId;
    MediaState m_state;
    EventToken m_token{};
    bool m_listening = false;
    std::shared_ptr<std::atomic_uint64_t> m_revision;
    quint64 m_lastRevision = 0;
    qint64 m_probeAfter = 0;
    bool m_canPlay = false;
    bool m_canPause = false;
    bool m_canToggle = false;
    double m_start = 0;
    double m_minSeek = 0;
    double m_maxSeek = 0;
};

} // namespace

WinMediaWorker::WinMediaWorker(MediaSessions *owner)
    : m_owner(owner), m_thread([this] { run(); })
{
}

WinMediaWorker::~WinMediaWorker()
{
    {
        const std::lock_guard lock(m_mutex);
        m_stopping = true;
    }
    m_wake.notify_one();
    m_thread.join();
}

void WinMediaWorker::select(const QString &id, quint64 revision)
{
    {
        const std::lock_guard lock(m_mutex);
        m_preference = id;
        m_revision = revision;
        m_commands.clear();
        m_changed = true;
    }
    m_wake.notify_one();
}

void WinMediaWorker::enqueue(MediaCommand command)
{
    {
        const std::lock_guard lock(m_mutex);
        if (!m_commands.empty() && m_commands.back().action == command.action
                && (command.action == MediaAction::Seek || command.action == MediaAction::Volume))
            m_commands.back() = std::move(command);
        else if (m_commands.size() < 8)
            m_commands.push_back(std::move(command));
        m_changed = true;
    }
    m_wake.notify_one();
}

void WinMediaWorker::publish(MediaUpdate update)
{
    QMetaObject::invokeMethod(m_owner, [owner = m_owner, update = std::move(update)]() mutable {
        owner->applyUpdate(std::move(update));
    }, Qt::QueuedConnection);
}

void WinMediaWorker::run()
{
    const Apartment apartment;
    if (FAILED(apartment.status)) {
        publish({});
        return;
    }

    SessionBroker broker(m_stopping);
    auto delay = 0ms;
    qint64 errorUntil = 0;
    while (!m_stopping) {
        MediaUpdate update;
        std::vector<MediaCommand> commands;
        {
            std::unique_lock lock(m_mutex);
            m_wake.wait_for(lock, delay, [this] { return m_stopping || m_changed; });
            if (m_stopping)
                return;
            m_changed = false;
            update.revision = m_revision;
            update.preference = m_preference;
            commands.swap(m_commands);
        }
        broker.read(update);
        {
            const std::lock_guard lock(m_mutex);
            if (update.revision != m_revision)
                continue;
            m_preference = update.preference;
        }
        if (!broker.selectionStillCurrent(update.preference)) {
            if (!commands.empty())
                errorUntil = playbackTimeMs() + 3500;
            delay = 50ms;
            continue;
        }
        for (const auto &command : commands) {
            if (m_stopping)
                return;
            errorUntil = broker.execute(command) ? 0 : playbackTimeMs() + 3500;
        }
        if (errorUntil > playbackTimeMs())
            update.commandError = QStringLiteral("Плеер не выполнил команду");
        delay = !update.available ? 2500ms : commands.empty() ? 450ms : 120ms;
        publish(std::move(update));
    }
}
