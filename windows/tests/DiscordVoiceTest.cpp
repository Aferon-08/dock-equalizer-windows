#include "DiscordVoice.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QEventLoop>
#include <QJsonDocument>
#include <QLocalServer>
#include <QLocalSocket>
#include <QPointer>
#include <QSettings>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QThread>
#include <QUrlQuery>
#include <QUuid>
#include <QtEndian>
#include <cstdio>

using namespace Qt::StringLiterals;

namespace {

const auto applicationId = u"123456789012345678"_s;
const auto ownId = u"100000000000000001"_s;
const auto peerId = u"100000000000000002"_s;
const auto voiceId = u"100000000000000003"_s;
const auto directId = u"100000000000000004"_s;
const auto mockAccess = u"mock-oauth-access-token"_s;

bool check(bool condition, const char *message)
{
    if (!condition)
        std::fprintf(stderr, "%s\n", message);
    return condition;
}

template<class Condition>
bool waitFor(Condition condition, int timeout = 1600)
{
    QElapsedTimer clock;
    clock.start();
    do {
        QCoreApplication::processEvents(QEventLoop::AllEvents);
        if (condition())
            return true;
        QThread::msleep(4);
    } while (clock.elapsed() < timeout);
    return false;
}

QByteArray frame(const QByteArray &data, quint32 opcode = 1)
{
    QByteArray encoded(8, Qt::Uninitialized);
    qToLittleEndian(opcode, encoded.data());
    qToLittleEndian(quint32(data.size()), encoded.data() + 4);
    return encoded + data;
}

QByteArray frame(const QJsonObject &data)
{
    return frame(QJsonDocument(data).toJson(QJsonDocument::Compact));
}

QJsonObject member(const QString &id, const QString &name, const QString &nick = {})
{
    return {{u"user"_s, QJsonObject{{u"id"_s, id}, {u"username"_s, name}}},
        {u"nick"_s, nick}, {u"voice_state"_s, QJsonObject{{u"self_mute"_s, false}, {u"self_deaf"_s, false}}}};
}

class MockDiscord
{
public:
    MockDiscord()
    {
        QObject::connect(&server, &QLocalServer::newConnection, &server, [this] {
            socket = server.nextPendingConnection();
            buffer.clear();
            QObject::connect(socket, &QLocalSocket::readyRead, &server, [this] { read(); });
            QObject::connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
        });
        channel = {{u"id"_s, voiceId}, {u"name"_s, u"Ночной эфир"_s}, {u"type"_s, 2},
            {u"voice_states"_s, QJsonArray{member(ownId, u"self"_s), member(peerId, u"mira"_s, u"Мира"_s)}}};
    }

    void sendEvent(const QString &event, const QJsonObject &data)
    {
        socket->write(frame(QJsonObject{{u"cmd"_s, u"DISPATCH"_s}, {u"evt"_s, event}, {u"data"_s, data}}));
    }

    void reply(const QJsonObject &request, const QJsonValue &data, int error = 0)
    {
        QJsonObject response{{u"cmd"_s, request.value(u"cmd"_s)}, {u"nonce"_s, request.value(u"nonce"_s)},
            {u"data"_s, data}};
        if (error) {
            response.insert(u"evt"_s, u"ERROR"_s);
            response.insert(u"data"_s, QJsonObject{{u"code"_s, error}});
        }
        socket->write(frame(response));
    }

    QLocalServer server;
    QPointer<QLocalSocket> socket;
    QJsonObject channel;
    QJsonObject heldQuery;
    QJsonObject lastMutation;
    QSet<QString> subscriptions;
    int authCount = 0;
    int mutationCount = 0;
    bool wrongHandshake = false;
    bool wrongToken = false;
    bool pongReceived = false;
    bool holdQuery = false;
    bool rejectMutation = false;
    bool writeScope = true;
    bool muted = false;
    bool deafened = false;

private:
    void read()
    {
        buffer.append(socket->readAll());
        while (buffer.size() >= 8) {
            const auto opcode = qFromLittleEndian<quint32>(buffer.constData());
            const auto length = qFromLittleEndian<quint32>(buffer.constData() + 4);
            if (buffer.size() < 8 + length)
                return;
            const auto payload = buffer.mid(8, length);
            buffer.remove(0, 8 + length);
            if (opcode == 4) {
                pongReceived = payload == "opaque ping";
                continue;
            }
            const auto json = QJsonDocument::fromJson(payload).object();
            if (opcode == 0) {
                wrongHandshake |= json.value(u"client_id"_s) != applicationId || json.value(u"v"_s).toInt() != 1;
                const auto ready = frame(QJsonObject{{u"cmd"_s, u"DISPATCH"_s}, {u"evt"_s, u"READY"_s},
                    {u"data"_s, QJsonObject{{u"v"_s, 1}, {u"user"_s, QJsonObject{{u"id"_s, ownId}}}}}});
                socket->write(ready.left(3));
                QTimer::singleShot(12, socket, [client = socket, packet = ready.mid(3)] {
                    client->write(packet + frame(QByteArray("opaque ping"), 3));
                });
            } else {
                handle(json);
            }
        }
    }

    void handle(const QJsonObject &request)
    {
        const auto command = request.value(u"cmd"_s).toString();
        const auto args = request.value(u"args"_s).toObject();
        const auto event = request.value(u"evt"_s).toString();
        const auto subscription = event + u':' + args.value(u"channel_id"_s).toString();
        if (command == u"AUTHENTICATE"_s) {
            ++authCount;
            wrongToken |= args.value(u"access_token"_s) != mockAccess;
            QJsonArray scopes{u"identify"_s, u"rpc"_s, u"rpc.voice.read"_s};
            if (writeScope)
                scopes.append(u"rpc.voice.write"_s);
            reply(request, QJsonObject{{u"user"_s, QJsonObject{{u"id"_s, ownId}}}, {u"scopes"_s, scopes},
                {u"application"_s, QJsonObject{{u"id"_s, applicationId}}}});
        } else if (command == u"SUBSCRIBE"_s || command == u"UNSUBSCRIBE"_s) {
            if (command == u"SUBSCRIBE"_s)
                subscriptions.insert(subscription);
            else
                subscriptions.remove(subscription);
            reply(request, QJsonObject{{u"evt"_s, event}});
        } else if (command == u"GET_SELECTED_VOICE_CHANNEL"_s) {
            if (holdQuery)
                heldQuery = request;
            else
                reply(request, channel.isEmpty() ? QJsonValue(QJsonValue::Null) : QJsonValue(channel));
        } else if (command == u"GET_VOICE_SETTINGS"_s) {
            reply(request, QJsonObject{{u"mute"_s, muted}, {u"deaf"_s, deafened}});
        } else if (command == u"SET_VOICE_SETTINGS"_s || command == u"SELECT_VOICE_CHANNEL"_s) {
            ++mutationCount;
            lastMutation = args;
            if (rejectMutation) {
                rejectMutation = false;
                reply(request, {}, 5000);
            } else if (command == u"SELECT_VOICE_CHANNEL"_s) {
                if (!args.value(u"channel_id"_s).isNull()) {
                    reply(request, {}, 4000);
                    return;
                }
                channel = {};
                reply(request, QJsonValue(QJsonValue::Null));
            } else {
                muted = args.value(u"mute"_s).toBool(muted);
                deafened = args.value(u"deaf"_s).toBool(deafened);
                reply(request, QJsonObject{{u"mute"_s, muted}, {u"deaf"_s, deafened}});
            }
        }
    }

    QByteArray buffer;
};

class BrowserCapture : public QObject
{
    Q_OBJECT

public:
    QUrl url;

public slots:
    void open(const QUrl &value) { url = value; }
};

QByteArray callback(const QUrl &redirect, const QByteArray &query)
{
    QTcpSocket socket;
    socket.connectToHost(QHostAddress::LocalHost, quint16(redirect.port()));
    if (!waitFor([&] { return socket.state() == QAbstractSocket::ConnectedState; }))
        return {};
    socket.write("GET " + redirect.path().toUtf8() + '?' + query + " HTTP/1.1\r\n"
        "Host: 127.0.0.1\r\nConnection: close\r\n\r\n");
    QByteArray response;
    waitFor([&] {
        response.append(socket.readAll());
        return socket.state() == QAbstractSocket::UnconnectedState;
    });
    return response;
}

}

struct DiscordVoiceTest
{
    static bool oauth(QSettings &settings)
    {
        DiscordOAuth oauth(settings);
        BrowserCapture browser;
        QDesktopServices::setUrlHandler(u"https"_s, &browser, "open");
        oauth.setClientId(applicationId);
        QString failure;
        QObject::connect(&oauth, &DiscordOAuth::failed, &browser, [&](const QString &value) { failure = value; });
        oauth.authorize();
        QDesktopServices::unsetUrlHandler(u"https"_s);
        const QUrlQuery query(browser.url);
        const auto state = query.queryItemValue(u"state"_s).toLatin1();
        const auto challenge = QCryptographicHash::hash(oauth.m_verifier.toLatin1(), QCryptographicHash::Sha256)
            .toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals);
        const QUrl redirect(DiscordOAuth::redirectUri());
        return check(browser.url.host() == u"discord.com"_s && browser.url.scheme() == u"https"_s
                && query.queryItemValue(u"response_type"_s) == u"code"_s && state.size() >= 40
                && query.queryItemValue(u"code_challenge_method"_s) == u"S256"_s
                && query.queryItemValue(u"code_challenge"_s).toLatin1() == challenge
                && query.queryItemValue(u"scope"_s).contains(u"rpc.voice.write"_s),
                "The browser must use the official PKCE authorization URL")
            && check(oauth.busy() && oauth.m_callback.serverAddress() == QHostAddress::LocalHost,
                "OAuth callback must bind only to the loopback address")
            && check(callback(redirect, "state=wrong&code=fake").startsWith("HTTP/1.1 400") && oauth.busy(),
                "An unrelated callback cannot consume the active login")
            && check(callback(redirect, "error=access_denied&state=" + state).startsWith("HTTP/1.1 200")
                && !oauth.busy() && !failure.isEmpty() && !oauth.usable(),
                "A valid cancellation must close the OAuth attempt without exchanging a code");
    }

    static bool storedGrant(QSettings &settings)
    {
        DiscordOAuth oauth(settings);
        oauth.setClientId(applicationId);
        oauth.m_accessToken = mockAccess;
        oauth.m_refreshToken = u"mock-oauth-refresh-token"_s;
        oauth.m_expiresAt = QDateTime::currentMSecsSinceEpoch() + 3600000;
        oauth.saveGrant();
        settings.sync();
        const auto saved = settings.value(u"discord/grant"_s).toByteArray();
        if (!check(!saved.contains("mock-oauth-"), "Credentials must never be stored in plain text"))
            return false;
#ifdef Q_OS_WIN
        DiscordOAuth restored(settings);
        restored.setClientId(applicationId);
        if (!check(!saved.isEmpty() && restored.usable() && restored.renewable()
                && restored.accessToken() == mockAccess, "Windows must restore the protected OAuth grant"))
            return false;
        restored.setClientId(voiceId);
        if (!check(!restored.usable() && !restored.renewable(), "A grant must be bound to its Application ID"))
            return false;

        MockDiscord discord;
        const auto endpoint = u"sekai-discord-upgrade-"_s + QUuid::createUuid().toString(QUuid::WithoutBraces);
        if (!check(discord.server.listen(endpoint), "Could not listen on the mock migration endpoint"))
            return false;
        settings.setValue(u"discord/clientId"_s, applicationId);
        settings.setValue(u"discord/linked"_s, true);
        {
            DiscordVoice upgraded(settings, true, applicationId, {endpoint});
            if (!check(waitFor([&] { return upgraded.canChangeVoice() && discord.authCount == 1; })
                    && !discord.wrongHandshake && !discord.wrongToken,
                    "Updating must reconnect with the same protected grant without opening sign-in"))
                return false;
        }
        settings.remove(u"discord/linked"_s);
        settings.remove(u"discord/clientId"_s);
#endif
        oauth.forget();
        return check(!settings.contains(u"discord/grant"_s), "Disconnect must remove the cached grant");
    }

    static bool voice(QSettings &settings)
    {
        MockDiscord discord;
        const auto endpoint = u"sekai-voice-test-"_s + QUuid::createUuid().toString(QUuid::WithoutBraces);
        if (!check(discord.server.listen(endpoint), "Could not listen on the mock Discord IPC endpoint"))
            return false;

        DiscordVoice invalid(settings, true, u"invalid"_s, {endpoint});
        invalid.connectDiscord();
        if (!check(!invalid.available() && !invalid.linked(), "An invalid build Application ID must not connect"))
            return false;

        settings.setValue(u"discord/clientId"_s, voiceId);
        DiscordVoice voice(settings, true, applicationId, {endpoint + u"-missing"_s, endpoint});
        voice.m_oauth.setClientId(applicationId);
        voice.m_oauth.m_accessToken = mockAccess;
        voice.m_oauth.m_expiresAt = QDateTime::currentMSecsSinceEpoch() + 3600000;
        voice.connectDiscord();
        if (!check(waitFor([&] { return voice.canChangeVoice() && discord.pongReceived
                && voice.m_subscribed.contains(u"SPEAKING_START"_s); }),
                "The handshake, fragmented READY, ping and authenticated subscriptions must work")
            || !check(!discord.wrongHandshake && !discord.wrongToken && voice.room() == u"Ночной эфир"_s
                && voice.participants().size() == 2,
                "Connect must use the configured app and expose the room and both users"))
            return false;

        discord.sendEvent(u"SPEAKING_START"_s, {{u"user_id"_s, peerId}});
        if (!check(waitFor([&] { return voice.participants().at(1).toMap().value(u"speaking"_s).toBool(); }),
                "Speaking events must update the visible participant"))
            return false;
        discord.sendEvent(u"VOICE_STATE_DELETE"_s, {{u"user_id"_s, peerId}});
        if (!check(waitFor([&] { return voice.participants().size() == 1; }),
                "Leaving participants must disappear from the panel"))
            return false;

        discord.rejectMutation = true;
        voice.toggleMute();
        if (!check(waitFor([&] { return discord.mutationCount == 1 && voice.canChangeVoice(); }) && !voice.muted(),
                "A rejected command must not optimistically mute the dock"))
            return false;
        voice.toggleMute();
        if (!check(waitFor([&] { return voice.muted() && voice.canChangeVoice(); })
                && discord.lastMutation.size() == 1 && discord.lastMutation.value(u"mute"_s).toBool(),
                "Mute must change only the documented mute setting"))
            return false;
        voice.toggleDeafen();
        if (!check(waitFor([&] { return voice.deafened() && voice.canChangeVoice(); })
                && discord.lastMutation.size() == 1 && discord.lastMutation.value(u"deaf"_s).toBool(),
                "Deafen must change only the documented deaf setting"))
            return false;
        voice.toggleDeafen();
        if (!check(waitFor([&] { return !voice.deafened() && voice.canChangeVoice(); }) && voice.muted(),
                "Undeafening must preserve the microphone state reported by Discord"))
            return false;

        discord.holdQuery = true;
        voice.refreshVoice();
        if (!check(waitFor([&] { return !discord.heldQuery.isEmpty(); }), "Expected the pending snapshot request"))
            return false;
        const auto oldChannel = discord.channel;
        discord.channel = {{u"id"_s, directId}, {u"type"_s, 1},
            {u"voice_states"_s, QJsonArray{member(ownId, u"self"_s), member(peerId, u"mira"_s, u"Мира"_s)}}};
        discord.sendEvent(u"VOICE_CHANNEL_SELECT"_s, {{u"channel_id"_s, directId}});
        discord.holdQuery = false;
        discord.reply(discord.heldQuery, oldChannel);
        if (!check(waitFor([&] { return voice.room() == u"Мира"_s
                && discord.subscriptions.contains(u"VOICE_STATE_CREATE:"_s + directId); })
                && voice.connected() && !discord.subscriptions.contains(u"VOICE_STATE_CREATE:"_s + voiceId),
                "A newer DM selection must supersede a stale snapshot and replace room subscriptions"))
            return false;

        discord.socket->disconnectFromServer();
        if (!check(waitFor([&] { return !voice.connected(); }), "Lost IPC must hide the active voice panel")
            || !check(waitFor([&] { return discord.authCount == 2 && voice.connected() && voice.canHangUp(); }, 4500),
                "Discord must reconnect and recover the selected channel without a second sign-in"))
            return false;
        voice.hangUp();
        if (!check(waitFor([&] { return !voice.connected(); }) && discord.channel.isEmpty()
                && discord.lastMutation.contains(u"channel_id"_s) && discord.lastMutation.value(u"channel_id"_s).isNull(),
                "Hang-up must send a null channel ID and close only after Discord replies"))
            return false;

        discord.writeScope = false;
        discord.channel = {{u"id"_s, voiceId}, {u"name"_s, u"Просмотр"_s}, {u"type"_s, 2}};
        discord.socket->disconnectFromServer();
        if (!check(waitFor([&] { return voice.connected() && discord.authCount == 3; }, 4500)
                && !voice.canHangUp() && !voice.canChangeVoice(), "Read-only grants must show voice without write controls"))
            return false;

        const auto count = discord.mutationCount;
        voice.hangUp();
        voice.toggleMute();
        voice.toggleDeafen();
        voice.disconnectDiscord();
        return check(!voice.connected() && !voice.linked() && discord.mutationCount == count && !discord.channel.isEmpty(),
            "Disconnecting the integration must leave Discord voice untouched");
    }
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir data;
    if (!data.isValid())
        return 1;
    QSettings settings(data.filePath(u"test.ini"_s), QSettings::IniFormat);
    return DiscordVoiceTest::oauth(settings) && DiscordVoiceTest::storedGrant(settings)
        && DiscordVoiceTest::voice(settings) ? 0 : 1;
}

#include "DiscordVoiceTest.moc"
