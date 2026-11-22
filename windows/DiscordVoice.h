#pragma once

#include "DiscordOAuth.h"
#include "DiscordRpc.h"

#include <QElapsedTimer>
#include <QJsonArray>
#include <QSet>
#include <QVariantList>

class QSettings;

class DiscordVoice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(QString redirectUri READ redirectUri CONSTANT)
    Q_PROPERTY(QString clientId READ clientId NOTIFY clientIdChanged)
    Q_PROPERTY(bool linked READ linked NOTIFY changed)
    Q_PROPERTY(bool signingIn READ signingIn NOTIFY changed)
    Q_PROPERTY(bool authorized READ authorized NOTIFY changed)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed)
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(QString room READ room NOTIFY changed)
    Q_PROPERTY(QString context READ context NOTIFY changed)
    Q_PROPERTY(QVariantList participants READ participants NOTIFY changed)
    Q_PROPERTY(bool muted READ muted NOTIFY changed)
    Q_PROPERTY(bool deafened READ deafened NOTIFY changed)
    Q_PROPERTY(bool canChangeVoice READ canChangeVoice NOTIFY changed)
    Q_PROPERTY(bool canHangUp READ canHangUp NOTIFY changed)
    Q_PROPERTY(QString durationText READ durationText NOTIFY durationChanged)

public:
    DiscordVoice(QSettings &settings, bool available, QStringList endpoints = {}, QObject *parent = nullptr);

    bool available() const { return m_available; }
    QString redirectUri() const { return DiscordOAuth::redirectUri(); }
    QString clientId() const { return m_clientId; }
    bool linked() const { return m_linked; }
    bool signingIn() const { return m_authenticating || m_oauth.busy(); }
    bool authorized() const { return m_authorized; }
    QString statusText() const { return m_status; }
    bool connected() const { return !m_channelId.isEmpty(); }
    QString room() const { return m_room; }
    QString context() const { return m_context; }
    QVariantList participants() const { return m_participants; }
    bool muted() const { return m_muted; }
    bool deafened() const { return m_deafened; }
    bool canChangeVoice() const { return canHangUp() && m_settingsKnown; }
    bool canHangUp() const;
    QString durationText() const;

    Q_INVOKABLE void connectDiscord(const QString &clientId);
    Q_INVOKABLE void disconnectDiscord();
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void toggleDeafen();
    Q_INVOKABLE void hangUp();

signals:
    void clientIdChanged();
    void changed();
    void durationChanged();

private:
    friend struct DiscordVoiceTest;

    void openClient();
    void clientLost();
    void authenticate();
    void refreshVoice();
    void refreshSettings();
    void voiceSettings(const QJsonObject &settings);
    void applyChannel(const QJsonValue &data);
    void subscribeChannel(const QString &oldChannel);
    void dispatch(const QString &event, const QJsonObject &data);
    void publishParticipants();
    void mutate(const QString &command, const QJsonObject &args);
    void clearSession();
    void setStatus(const QString &status);

    QSettings &m_settings;
    const bool m_available;
    DiscordRpc m_rpc;
    DiscordOAuth m_oauth;
    QTimer m_poll;
    QTimer m_clock;
    QElapsedTimer m_callStarted;
    QElapsedTimer m_ipcLostAt;
    QString m_clientId;
    QString m_status;
    QString m_selfId;
    QString m_channelId;
    QString m_lastChannel;
    QString m_room;
    QString m_context;
    QString m_channelName;
    QJsonArray m_members;
    QSet<QString> m_speaking;
    QSet<QString> m_subscribed;
    QVariantList m_participants;
    int m_channelType = 0;
    int m_seconds = 0;
    quint64 m_voiceRevision = 0;
    quint64 m_settingsRevision = 0;
    bool m_linked = false;
    bool m_consentRequested = false;
    bool m_authenticating = false;
    bool m_authorized = false;
    bool m_writable = false;
    bool m_settingsKnown = false;
    bool m_muted = false;
    bool m_deafened = false;
    bool m_mutating = false;
    bool m_switching = false;
    bool m_queryingVoice = false;
    bool m_queryingSettings = false;
};
