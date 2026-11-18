#include "MediaSessions.h"

#ifdef Q_OS_WIN
#include "WinMediaWorker.h"
#endif

#include <QVariantMap>

#include <utility>

MediaSessions::MediaSessions(bool enabled)
{
#ifdef Q_OS_WIN
    if (enabled) {
        m_connecting = true;
        m_worker = std::make_unique<WinMediaWorker>(this);
    }
#else
    Q_UNUSED(enabled);
#endif
}

MediaSessions::~MediaSessions() = default;

QString MediaSessions::title() const
{
    return !m_state.sessionId.isEmpty() && m_state.title.isEmpty()
        ? tr("Без названия") : m_state.title;
}

QString MediaSessions::artist() const
{
    return m_state.artist.isEmpty() ? m_state.sourceName : m_state.artist;
}

QString MediaSessions::statusText() const
{
    if (m_connecting)
        return tr("Подключение к плеерам…");
    return m_available ? tr("Откройте музыкальный плеер") : tr("Медиасессии недоступны");
}

void MediaSessions::applyUpdate(MediaUpdate update)
{
    if (update.revision != m_revision)
        return;

    const bool resetClock = m_state.trackKey != update.state.trackKey
        || m_state.sessionId != update.state.sessionId;
    m_clock.observe(update.state.timeline, resetClock);
    m_state = std::move(update.state);
    m_available = update.available;
    m_connecting = false;
    m_commandError = std::move(update.commandError);
    const bool listChanged = m_sessions != update.sessions || m_preference != update.preference;
    m_sessions = std::move(update.sessions);
    m_preference = std::move(update.preference);
    emit changed();
    if (listChanged)
        emit sessionsChanged();
}

void MediaSessions::selectSession(const QString &id)
{
#ifdef Q_OS_WIN
    if (!m_worker || id == m_preference)
        return;
    if (!id.isEmpty() && std::none_of(m_sessions.begin(), m_sessions.end(), [&id](const QVariant &source) {
            return source.toMap().value(QStringLiteral("id")).toString() == id;
        }))
        return;

    m_preference = id;
    m_connecting = true;
    m_state = {};
    m_clock = {};
    m_commandError.clear();
    m_worker->select(id, ++m_revision);
    emit changed();
    emit sessionsChanged();
#else
    Q_UNUSED(id);
#endif
}

void MediaSessions::send(MediaAction action, qreal value)
{
#ifdef Q_OS_WIN
    if (m_worker && !m_state.sessionId.isEmpty())
        m_worker->enqueue({action, m_state.sessionId, m_state.trackKey, value});
#else
    Q_UNUSED(action);
    Q_UNUSED(value);
#endif
}

void MediaSessions::togglePlaying()
{
    if (canTogglePlaying())
        send(MediaAction::TogglePlaying);
}

void MediaSessions::next()
{
    if (canGoNext())
        send(MediaAction::Next);
}

void MediaSessions::previous()
{
    if (canGoPrevious())
        send(MediaAction::Previous);
}

void MediaSessions::seek(qreal seconds)
{
    if (canSeek() && std::isfinite(seconds))
        send(MediaAction::Seek, std::clamp(seconds, 0.0, length()));
}

void MediaSessions::setVolume(qreal value)
{
    if (volumeSupported() && std::isfinite(value))
        send(MediaAction::Volume, std::clamp(value, 0.0, 1.0));
}

void MediaSessions::changeVolume(int direction)
{
    setVolume(volume() + (direction > 0 ? 0.05 : -0.05));
}

void MediaSessions::toggleMute()
{
    if (volumeSupported())
        send(MediaAction::ToggleMute);
}
