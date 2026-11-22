#pragma once

#include <QNetworkAccessManager>
#include <QObject>
#include <QTcpServer>
#include <QTimer>

class QNetworkReply;
class QNetworkProxy;
class QSettings;
class QTcpSocket;
class QUrlQuery;

class DiscordOAuth : public QObject
{
    Q_OBJECT

public:
    explicit DiscordOAuth(QSettings &settings, QObject *parent = nullptr);
    ~DiscordOAuth() override;

    static QString redirectUri();
    static QStringList scopes();
    void setProxy(const QNetworkProxy &proxy);
    void setClientId(const QString &clientId);
    void authorize();
    void refresh();
    void cancel();
    void forget();

    bool busy() const { return m_callback.isListening() || m_reply; }
    bool usable() const;
    bool renewable() const { return !m_refreshToken.isEmpty(); }
    QString accessToken() const { return m_accessToken; }

signals:
    void authorizing();
    void exchanging();
    void granted();
    void failed(const QString &message);

private:
    friend struct DiscordVoiceTest;

    void acceptCallbacks();
    void handleCallback(QTcpSocket &socket, const QByteArray &request);
    void exchange(QUrlQuery parameters, bool refreshing);
    void restoreGrant();
    void saveGrant();

    QSettings &m_settings;
    QNetworkAccessManager m_network;
    QTcpServer m_callback;
    QTimer m_consentTimeout;
    QNetworkReply *m_reply = nullptr;
    QUrl m_tokenEndpoint{QStringLiteral("https://discord.com/api/v10/oauth2/token")};
    QString m_clientId;
    QString m_state;
    QString m_verifier;
    QString m_accessToken;
    QString m_refreshToken;
    qint64 m_expiresAt = 0;
};
