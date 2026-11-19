#pragma once

#include "PlaybackClock.h"

#include <QObject>
#include <QString>
#include <QUrl>
#include <QVariantList>

#include <memory>

struct MediaState
{
    QString sessionId;
    QString trackKey;
    QString title;
    QString artist;
    QString album;
    QString sourceName;
    QUrl artUrl;
    TimelineSample timeline;
    bool canTogglePlaying = false;
    bool canGoNext = false;
    bool canGoPrevious = false;
    bool canSeek = false;
    bool volumeSupported = false;
    qreal volume = 0;
};

struct MediaUpdate
{
    quint64 revision = 0;
    bool available = false;
    QVariantList sessions;
    QString preference;
    QString commandError;
    MediaState state;
};

enum class MediaAction { TogglePlaying, Next, Previous, Seek, Volume, ToggleMute };

struct MediaCommand
{
    MediaAction action;
    QString sessionId;
    QString trackKey;
    qreal value;
};

class WinMediaWorker;

class MediaSessions final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QObject *player READ player NOTIFY changed FINAL)
    Q_PROPERTY(QString title READ title NOTIFY changed FINAL)
    Q_PROPERTY(QString artist READ artist NOTIFY changed FINAL)
    Q_PROPERTY(QUrl artUrl READ artUrl NOTIFY changed FINAL)
    Q_PROPERTY(QString trackKey READ trackKey NOTIFY changed FINAL)
    Q_PROPERTY(bool playing READ playing NOTIFY changed FINAL)
    Q_PROPERTY(bool canTogglePlaying READ canTogglePlaying NOTIFY changed FINAL)
    Q_PROPERTY(bool canGoNext READ canGoNext NOTIFY changed FINAL)
    Q_PROPERTY(bool canGoPrevious READ canGoPrevious NOTIFY changed FINAL)
    Q_PROPERTY(bool canSeek READ canSeek NOTIFY changed FINAL)
    Q_PROPERTY(bool canControl READ volumeSupported NOTIFY changed FINAL)
    Q_PROPERTY(bool volumeSupported READ volumeSupported NOTIFY changed FINAL)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY changed FINAL)
    Q_PROPERTY(qreal length READ length NOTIFY changed FINAL)
    Q_PROPERTY(bool lengthSupported READ lengthSupported NOTIFY changed FINAL)
    Q_PROPERTY(bool positionSupported READ positionSupported NOTIFY changed FINAL)
    Q_PROPERTY(QVariantList sessions READ sessions NOTIFY sessionsChanged FINAL)
    Q_PROPERTY(QString preference READ preference NOTIFY sessionsChanged FINAL)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed FINAL)
    Q_PROPERTY(QString commandError READ commandError NOTIFY changed FINAL)

public:
    explicit MediaSessions(bool enabled = true);
    ~MediaSessions() override;

    QObject *player() { return m_state.sessionId.isEmpty() ? nullptr : this; }
    QString title() const;
    QString artist() const;
    QString trackTitle() const { return m_state.title; }
    QString trackArtist() const { return m_state.artist; }
    QString trackAlbum() const { return m_state.album; }
    QUrl artUrl() const { return m_state.artUrl; }
    QString trackKey() const { return m_state.trackKey; }
    bool playing() const { return m_state.timeline.playing; }
    bool canTogglePlaying() const { return m_state.canTogglePlaying; }
    bool canGoNext() const { return m_state.canGoNext; }
    bool canGoPrevious() const { return m_state.canGoPrevious; }
    bool canSeek() const { return m_state.canSeek; }
    bool volumeSupported() const { return m_state.volumeSupported; }
    qreal volume() const { return m_state.volume; }
    qreal length() const { return m_state.timeline.duration; }
    bool lengthSupported() const { return length() > 0; }
    bool positionSupported() const { return m_state.timeline.valid; }
    QVariantList sessions() const { return m_sessions; }
    QString preference() const { return m_preference; }
    QString statusText() const;
    QString commandError() const { return m_commandError; }

    Q_INVOKABLE qreal positionNow() const { return m_clock.positionAt(playbackTimeMs()); }
    Q_INVOKABLE void selectSession(const QString &id);
    Q_INVOKABLE void togglePlaying();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void seek(qreal seconds);
    Q_INVOKABLE void changeVolume(int direction);
    Q_INVOKABLE void toggleMute();
    void setVolume(qreal value);

signals:
    void changed();
    void sessionsChanged();

private:
    friend class WinMediaWorker;
    void applyUpdate(MediaUpdate update);
    void send(MediaAction action, qreal value = 0);

    MediaState m_state;
    PlaybackClock m_clock;
    QVariantList m_sessions;
    QString m_preference;
    QString m_commandError;
    quint64 m_revision = 0;
    bool m_available = false;
    bool m_connecting = false;
#ifdef Q_OS_WIN
    std::unique_ptr<WinMediaWorker> m_worker;
#endif
};
