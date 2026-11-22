#include "DiscordRpc.h"

#include <QDir>
#include <QJsonDocument>
#include <QLocalSocket>
#include <QUuid>
#include <QtEndian>
#include <utility>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

using namespace Qt::StringLiterals;

namespace {

constexpr quint32 maxPayload = 1024 * 1024;
constexpr qsizetype headerSize = 8;
enum Opcode : quint32 { Handshake, Frame, Close, Ping, Pong };

QStringList discordEndpoints()
{
    QStringList paths;
#ifdef Q_OS_WIN
    for (int index = 0; index < 10; ++index)
        paths.append(u"discord-ipc-%1"_s.arg(index));
#else
    QStringList directories;
    for (const auto *name : {"XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"}) {
        const auto directory = qEnvironmentVariable(name);
        if (!directory.isEmpty())
            directories.append(directory);
    }
    directories.append(u"/tmp"_s);
    directories.removeDuplicates();
    for (const auto &directory : directories) {
        for (int index = 0; index < 10; ++index)
            paths.append(QDir(directory).filePath(u"discord-ipc-%1"_s.arg(index)));
    }
#endif
    return paths;
}

}

DiscordRpc::DiscordRpc(QStringList endpoints, QObject *parent)
    : QObject(parent), m_endpoints(endpoints.isEmpty() ? discordEndpoints() : std::move(endpoints))
{
    m_probe.setSingleShot(true);
    m_handshake.setSingleShot(true);
    m_timeouts.setInterval(250);
    connect(&m_probe, &QTimer::timeout, this, &DiscordRpc::probe);
    connect(&m_handshake, &QTimer::timeout, this, &DiscordRpc::retry);
    connect(&m_timeouts, &QTimer::timeout, this, &DiscordRpc::expireRequests);
}

void DiscordRpc::start(const QString &clientId)
{
    stop();
    m_clientId = clientId;
    if (!m_clientId.isEmpty())
        m_probe.start(0);
}

void DiscordRpc::stop()
{
    m_clientId.clear();
    m_nextEndpoint = 0;
    m_probe.stop();
    closeSocket();
}

void DiscordRpc::closeSocket()
{
    m_ready = false;
    m_userId.clear();
    m_handshake.stop();
    m_timeouts.stop();
    m_pending.clear();
    m_buffer.clear();
    if (auto *socket = std::exchange(m_socket, nullptr)) {
        socket->disconnect(this);
        socket->abort();
        socket->deleteLater();
    }
}

void DiscordRpc::probe()
{
    if (m_clientId.isEmpty() || m_nextEndpoint >= m_endpoints.size())
        return;

    m_socket = new QLocalSocket(this);
    m_socket->setReadBufferSize(maxPayload + headerSize);
    connect(m_socket, &QLocalSocket::readyRead, this, &DiscordRpc::readFrames);
    connect(m_socket, &QLocalSocket::disconnected, this, &DiscordRpc::retry);
    connect(m_socket, &QLocalSocket::errorOccurred, this, [this](auto) { retry(); });

    const auto endpoint = m_endpoints.at(m_nextEndpoint++);
    m_handshake.start(2500);
#ifdef Q_OS_WIN
    // QLocalSocket's Windows connect can wait on a busy pipe. Open once and
    // let the retry timer handle contention without holding the UI thread.
    const auto path = u"\\\\.\\pipe\\"_s + endpoint;
    const auto handle = CreateFileW(reinterpret_cast<const wchar_t *>(path.utf16()), GENERIC_READ | GENERIC_WRITE,
        0, nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
        retry();
        return;
    }
    if (!m_socket->setSocketDescriptor(reinterpret_cast<qintptr>(handle))) {
        CloseHandle(handle);
        retry();
        return;
    }
    sendHandshake();
#else
    connect(m_socket, &QLocalSocket::connected, this, &DiscordRpc::sendHandshake);
    m_socket->connectToServer(endpoint);
#endif
}

void DiscordRpc::sendHandshake()
{
    const QJsonObject hello{{u"v"_s, 1}, {u"client_id"_s, m_clientId}};
    writeFrame(Handshake, QJsonDocument(hello).toJson(QJsonDocument::Compact));
}

void DiscordRpc::retry()
{
    const bool lostSession = m_ready;
    closeSocket();
    if (m_clientId.isEmpty())
        return;

    if (lostSession || m_nextEndpoint >= m_endpoints.size()) {
        m_nextEndpoint = 0;
        m_probe.start(2500);
        emit waitingForClient();
    } else {
        m_probe.start(0);
    }
}

void DiscordRpc::request(const QString &command, const QJsonObject &arguments, Reply reply,
                         const QString &event)
{
    if (!m_ready || m_pending.size() >= 48) {
        reply(QJsonValue(), TransportError);
        return;
    }

    const auto nonce = QUuid::createUuid().toString(QUuid::WithoutBraces);
    QJsonObject payload{{u"cmd"_s, command}, {u"nonce"_s, nonce}, {u"args"_s, arguments}};
    if (!event.isEmpty())
        payload.insert(u"evt"_s, event);
    m_pending.insert(nonce, {command, QDeadlineTimer(4500), std::move(reply)});
    if (!m_timeouts.isActive())
        m_timeouts.start();
    writeFrame(Frame, QJsonDocument(payload).toJson(QJsonDocument::Compact));
}

void DiscordRpc::writeFrame(quint32 opcode, const QByteArray &payload)
{
    if (!m_socket)
        return;
    QByteArray frame(headerSize, Qt::Uninitialized);
    qToLittleEndian(opcode, frame.data());
    qToLittleEndian(quint32(payload.size()), frame.data() + 4);
    frame.append(payload);
    auto *socket = m_socket;
    if (socket->write(frame) < 0 && socket == m_socket)
        retry();
}

void DiscordRpc::readFrames()
{
    auto *socket = m_socket;
    if (!socket)
        return;
    m_buffer.append(socket->readAll());
    while (m_socket == socket && m_buffer.size() >= headerSize) {
        const auto opcode = qFromLittleEndian<quint32>(m_buffer.constData());
        const auto size = qFromLittleEndian<quint32>(m_buffer.constData() + 4);
        if (size > maxPayload || opcode > Pong || opcode == Handshake || opcode == Close) {
            retry();
            return;
        }
        if (m_buffer.size() < headerSize + size)
            return;

        const auto payload = m_buffer.mid(headerSize, size);
        m_buffer.remove(0, headerSize + size);
        if (opcode == Ping) {
            writeFrame(Pong, payload);
        } else if (opcode == Frame) {
            const auto json = QJsonDocument::fromJson(payload);
            if (!json.isObject()) {
                retry();
                return;
            }
            handleFrame(json.object());
        }
    }
}

void DiscordRpc::handleFrame(const QJsonObject &frame)
{
    const auto command = frame.value(u"cmd"_s).toString();
    const auto event = frame.value(u"evt"_s).toString();
    const auto data = frame.value(u"data"_s);
    if (command == u"DISPATCH"_s && event == u"READY"_s && !m_ready) {
        const auto ready = data.toObject();
        if (ready.value(u"v"_s).toInt() != 1) {
            retry();
            return;
        }
        m_userId = ready.value(u"user"_s).toObject().value(u"id"_s).toString();
        m_ready = true;
        m_handshake.stop();
        emit handshakeReady();
        return;
    }
    if (!m_ready)
        return;

    const auto nonce = frame.value(u"nonce"_s).toString();
    if (!nonce.isEmpty()) {
        auto pending = m_pending.find(nonce);
        if (pending == m_pending.end() || (pending->command != command && event != u"ERROR"_s))
            return;
        auto reply = std::move(pending->reply);
        m_pending.erase(pending);
        if (m_pending.isEmpty())
            m_timeouts.stop();
        reply(data, event == u"ERROR"_s ? data.toObject().value(u"code"_s).toInt(4000) : 0);
    } else if (command == u"DISPATCH"_s && !event.isEmpty()) {
        emit eventReceived(event, data.toObject());
    }
}

void DiscordRpc::expireRequests()
{
    const auto nonces = m_pending.keys();
    for (const auto &nonce : nonces) {
        auto pending = m_pending.find(nonce);
        if (pending == m_pending.end() || !pending->deadline.hasExpired())
            continue;
        auto reply = std::move(pending->reply);
        m_pending.erase(pending);
        reply(QJsonValue(), RequestTimeout);
    }
    if (m_pending.isEmpty())
        m_timeouts.stop();
}
