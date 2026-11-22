#pragma once

#include <QDeadlineTimer>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QStringList>
#include <QTimer>

#include <functional>

class QLocalSocket;

class DiscordRpc : public QObject
{
    Q_OBJECT

public:
    using Reply = std::function<void(const QJsonValue &, int)>;
    static constexpr int TransportError = -1;
    static constexpr int RequestTimeout = -2;

    explicit DiscordRpc(QStringList endpoints = {}, QObject *parent = nullptr);

    void start(const QString &clientId);
    void stop();
    bool ready() const { return m_ready; }
    QString userId() const { return m_userId; }
    void request(const QString &command, const QJsonObject &arguments, Reply reply,
                 const QString &event = {});

signals:
    void handshakeReady();
    void waitingForClient();
    void eventReceived(const QString &event, const QJsonObject &data);

private:
    struct Pending {
        QString command;
        QDeadlineTimer deadline;
        Reply reply;
    };

    void probe();
    void retry();
    void closeSocket();
    void sendHandshake();
    void readFrames();
    void handleFrame(const QJsonObject &frame);
    void expireRequests();
    void writeFrame(quint32 opcode, const QByteArray &payload);

    QStringList m_endpoints;
    QString m_clientId;
    QString m_userId;
    QLocalSocket *m_socket = nullptr;
    QByteArray m_buffer;
    QHash<QString, Pending> m_pending;
    QTimer m_probe;
    QTimer m_handshake;
    QTimer m_timeouts;
    qsizetype m_nextEndpoint = 0;
    bool m_ready = false;
};
