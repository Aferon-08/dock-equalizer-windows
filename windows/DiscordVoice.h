#pragma once

#include "DiscordOAuth.h"
#include "DiscordRpc.h"

#include <QAbstractListModel>
#include <QElapsedTimer>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QSet>
#include <QUrl>
#include <QVariantList>

class QSettings;

class DiscordParticipants : public QAbstractListModel
{
public:
    explicit DiscordParticipants(QObject *parent);
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    const QVariantList &rows() const { return m_rows; }
    bool setRows(QVariantList rows);

private:
    QVariantList m_rows;
};

class DiscordVoice : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(QString proxyMode READ proxyMode WRITE setProxyMode NOTIFY proxyModeChanged)
    Q_PROPERTY(bool linked READ linked NOTIFY changed)
    Q_PROPERTY(bool signingIn READ signingIn NOTIFY changed)
    Q_PROPERTY(bool authorized READ authorized NOTIFY changed)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed)
    Q_PROPERTY(bool connected READ connected NOTIFY changed)
    Q_PROPERTY(QString channelId READ channelId NOTIFY changed)
    Q_PROPERTY(QString room READ room NOTIFY changed)
    Q_PROPERTY(QString context READ context NOTIFY changed)
    Q_PROPERTY(QVariantList participants READ participants NOTIFY participantsChanged)
    Q_PROPERTY(QAbstractItemModel *participantModel READ participantModel CONSTANT)
    Q_PROPERTY(int participantCount READ participantCount NOTIFY participantCountChanged)
    Q_PROPERTY(QString voiceStatus READ voiceStatus NOTIFY voiceStatusChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY changed)
    Q_PROPERTY(bool deafened READ deafened NOTIFY changed)
    Q_PROPERTY(bool canChangeVoice READ canChangeVoice NOTIFY changed)
    Q_PROPERTY(bool canHangUp READ canHangUp NOTIFY changed)
    Q_PROPERTY(QString durationText READ durationText NOTIFY durationChanged)

public:
    DiscordVoice(QSettings &settings, bool available, QString applicationId, QStringList endpoints = {},
                 QObject *parent = nullptr);
    ~DiscordVoice() override;

    bool available() const { return m_available; }
    QString proxyMode() const { return m_proxyMode; }
    void setProxyMode(const QString &mode);
    bool linked() const { return m_linked; }
    bool signingIn() const { return m_authenticating || m_oauth.busy(); }
    bool authorized() const { return m_authorized; }
    QString statusText() const { return m_status; }
    bool connected() const { return !m_channelId.isEmpty(); }
    QString channelId() const { return m_channelId; }
    QString room() const { return m_room; }
    QString context() const { return m_context; }
    QVariantList participants() const { return m_participants.rows(); }
    QAbstractItemModel *participantModel() { return &m_participants; }
    int participantCount() const { return m_participants.rowCount(); }
    QString voiceStatus() const { return m_voiceStatus; }
    bool muted() const { return m_muted; }
    bool deafened() const { return m_deafened; }
    bool canChangeVoice() const { return canHangUp() && m_settingsKnown; }
    bool canHangUp() const;
    QString durationText() const;

    Q_INVOKABLE void connectDiscord();
    Q_INVOKABLE void disconnectDiscord();
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void toggleDeafen();
    Q_INVOKABLE void hangUp();

signals:
    void changed();
    void durationChanged();
    void proxyModeChanged();
    void participantsChanged();
    void participantCountChanged();
    void voiceStatusChanged();

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
    void connectionStatus(const QJsonObject &data);
    void setVoiceStatus(const QString &status);
    void publishParticipants();
    void setParticipantRows(QVariantList rows);
    void syncAvatars(const QSet<QUrl> &urls);
    void fetchAvatar(const QUrl &url);
    void mutate(const QString &command, const QJsonObject &args);
    void clearSession();
    void setStatus(const QString &status);

    QSettings &m_settings;
    const bool m_available;
    const QString m_clientId;
    QString m_proxyMode;
    DiscordRpc m_rpc;
    DiscordOAuth m_oauth;
    DiscordParticipants m_participants;
    QNetworkAccessManager m_avatarNetwork;
    QHash<QUrl, QNetworkReply *> m_avatarRequests;
    QHash<QUrl, QUrl> m_avatars;
    QTimer m_poll;
    QTimer m_clock;
    QElapsedTimer m_callStarted;
    QElapsedTimer m_ipcLostAt;
    QString m_status;
    QString m_selfId;
    QJsonObject m_selfUser;
    QString m_channelId;
    QString m_lastChannel;
    QString m_pendingChannel;
    QString m_pendingVoiceStatus;
    QString m_voiceStatus = QStringLiteral("unknown");
    QString m_room;
    QString m_context;
    QString m_channelName;
    QJsonArray m_members;
    QSet<QString> m_speaking;
    QSet<QString> m_subscribed;
    int m_channelType = 0;
    int m_seconds = 0;
    quint64 m_voiceRevision = 0;
    quint64 m_settingsRevision = 0;
    bool m_linked = false;
    bool m_consentRequested = false;
    bool m_authenticating = false;
    bool m_authorized = false;
    bool m_voiceStatusSubscribed = false;
    bool m_writable = false;
    bool m_settingsKnown = false;
    bool m_muted = false;
    bool m_deafened = false;
    bool m_mutating = false;
    bool m_switching = false;
    bool m_queryingVoice = false;
    bool m_queryingSettings = false;
};
