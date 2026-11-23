#include "DiscordVoice.h"

#include <QBuffer>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QEventLoop>
#include <QImage>
#include <QJsonDocument>
#include <QLocalServer>
#include <QLocalSocket>
#include <QNetworkProxy>
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
            {u"voice_states"_s, QJsonArray{member(peerId, u"mira"_s, u"Мира"_s), member(ownId, u"self"_s),
                QJsonObject{{u"user"_s, QJsonObject{{u"id"_s, peerId}, {u"global_name"_s, u"Мирослава"_s},
                    {u"avatar"_s, u"../../наружу"_s}}}}}}};
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
    QJsonObject authUser{{u"id"_s, ownId}};
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
    bool voiceStatusSupported = true;
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
            reply(request, QJsonObject{{u"user"_s, authUser}, {u"scopes"_s, scopes},
                {u"application"_s, QJsonObject{{u"id"_s, applicationId}}}});
        } else if (command == u"SUBSCRIBE"_s || command == u"UNSUBSCRIBE"_s) {
            if (event == u"VOICE_CONNECTION_STATUS"_s && !voiceStatusSupported) {
                reply(request, {}, 4002);
                return;
            }
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

class MockTokenEndpoint
{
public:
    MockTokenEndpoint()
    {
        QObject::connect(&server, &QTcpServer::newConnection, &server, [this] {
            auto *socket = server.nextPendingConnection();
            QObject::connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            QObject::connect(socket, &QTcpSocket::readyRead, socket, [this, socket, buffer = QByteArray{}]() mutable {
                buffer += socket->readAll();
                const auto headerEnd = buffer.indexOf("\r\n\r\n");
                if (headerEnd < 0)
                    return;
                qsizetype length = 0;
                for (const auto &line : buffer.left(headerEnd).split('\n')) {
                    if (line.toLower().startsWith("content-length:"))
                        length = line.mid(15).trimmed().toLongLong();
                }
                if (buffer.size() < headerEnd + 4 + length)
                    return;

                requestHeaders = buffer.left(headerEnd);
                form.setQuery(QString::fromUtf8(buffer.mid(headerEnd + 4, length)));
                ++requestCount;
                if (holdResponse)
                    return;
                socket->write("HTTP/1.1 " + status + "\r\nContent-Type: application/json\r\nConnection: close\r\n"
                    "Content-Length: " + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                socket->disconnectFromHost();
            });
        });
    }

    QTcpServer server;
    QByteArray status = "403 Forbidden";
    QByteArray body = "{}";
    QByteArray requestHeaders;
    QUrlQuery form;
    int requestCount = 0;
    bool holdResponse = false;
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

    static bool tokenExchange(QSettings &settings)
    {
        MockTokenEndpoint endpoint;
        if (!check(endpoint.server.listen(QHostAddress::LocalHost), "Could not listen on the mock token proxy"))
            return false;
        DiscordOAuth oauth(settings);
        oauth.setClientId(applicationId);
        oauth.m_tokenEndpoint = QUrl(u"http://discord.invalid/api/v10/oauth2/token"_s);
        oauth.setProxy(QNetworkProxy(QNetworkProxy::HttpProxy, u"127.0.0.1"_s, endpoint.server.serverPort()));

        BrowserCapture browser;
        QString failure;
        QString verifier;
        bool granted = false;
        QObject::connect(&oauth, &DiscordOAuth::failed, &browser, [&](const QString &value) { failure = value; });
        QObject::connect(&oauth, &DiscordOAuth::granted, &browser, [&] { granted = true; });
        const auto confirm = [&] {
            QDesktopServices::setUrlHandler(u"https"_s, &browser, "open");
            oauth.authorize();
            QDesktopServices::unsetUrlHandler(u"https"_s);
            verifier = oauth.m_verifier;
            const QUrlQuery query(browser.url);
            const auto state = query.queryItemValue(u"state"_s).toLatin1();
            return callback(QUrl(DiscordOAuth::redirectUri()), "code=test-code&state=" + state)
                .startsWith("HTTP/1.1 200");
        };
        if (!check(confirm() && waitFor([&] { return failure.contains(u"HTTP 403"_s); }),
                "The loopback callback must work with a proxy and expose a rejected HTTP status")
            || !check(endpoint.requestHeaders.startsWith("POST http://discord.invalid/api/v10/oauth2/token")
                    && endpoint.requestHeaders.toLower().contains("\r\nuser-agent: discordbot (https://github.com/"
                        "aferon-08/sekaipop-dock-equalizer-windows, 1.0)\r\n"),
                "The token request must send Discord's User-Agent through the selected proxy")
            || !check(endpoint.form.queryItemValue(u"grant_type"_s) == u"authorization_code"_s
                    && endpoint.form.queryItemValue(u"client_id"_s) == applicationId
                    && endpoint.form.queryItemValue(u"code"_s) == u"test-code"_s
                    && endpoint.form.queryItemValue(u"code_verifier"_s) == verifier
                    && endpoint.form.queryItemValue(u"redirect_uri"_s, QUrl::FullyDecoded) == DiscordOAuth::redirectUri(),
                "The token request must include the original redirect URI and PKCE verifier"))
            return false;

        endpoint.status = "200 OK";
        endpoint.body = R"({"access_token":"test-access","refresh_token":"test-refresh","expires_in":3600,
            "scope":"identify rpc rpc.voice.read rpc.voice.write"})";
        failure.clear();
        if (!check(confirm() && waitFor([&] { return granted; }) && oauth.usable() && oauth.renewable(),
                "A successful exchange through the proxy must authorize Discord"))
            return false;

        endpoint.status = "400 Bad Request";
        endpoint.body = R"({"error":"invalid_grant"})";
        oauth.refresh();
        return check(waitFor([&] { return !failure.isEmpty(); }) && !oauth.renewable()
                && failure.contains(u"Срок сохранённого разрешения"_s)
                && !settings.contains(u"discord/grant"_s)
                && endpoint.form.queryItemValue(u"grant_type"_s) == u"refresh_token"_s,
            "An expired grant must be cleared and explained in settings after a proxied refresh");
    }

    static bool proxyPreference(QSettings &settings)
    {
        DiscordVoice voice(settings, true, applicationId);
        if (!check(voice.proxyMode() == u"system"_s
                && voice.m_oauth.m_network.proxy().type() == QNetworkProxy::DefaultProxy
                && voice.m_avatarNetwork.proxy().type() == QNetworkProxy::DefaultProxy,
                "Discord must start with the system proxy unless a preset was selected"))
            return false;
        voice.setProxyMode(u"incy-http"_s);
        const auto http = voice.m_oauth.m_network.proxy();
        if (!check(http.type() == QNetworkProxy::HttpProxy && http.hostName() == u"127.0.0.1"_s && http.port() == 10809
                && voice.m_avatarNetwork.proxy() == http,
                "The INCY HTTP preset must use the local HTTP proxy"))
            return false;

        voice.setProxyMode(u"incy-socks5"_s);
        DiscordVoice restarted(settings, true, applicationId);
        const auto remembered = restarted.m_oauth.m_network.proxy();
        if (!check(restarted.proxyMode() == u"incy-socks5"_s && remembered.type() == QNetworkProxy::Socks5Proxy
                && remembered.hostName() == u"127.0.0.1"_s && remembered.port() == 10808
                && restarted.m_avatarNetwork.proxy() == remembered,
                "Discord must remember the selected proxy across restarts"))
            return false;

        restarted.setProxyMode(u"direct"_s);
        DiscordVoice direct(settings, true, applicationId);
        if (!check(direct.proxyMode() == u"direct"_s && direct.m_oauth.m_network.proxy().type() == QNetworkProxy::NoProxy
                && direct.m_avatarNetwork.proxy().type() == QNetworkProxy::NoProxy,
                "The direct route must ignore the system proxy for OAuth and avatars after restart"))
            return false;

        direct.setProxyMode(u"system"_s);
        direct.setProxyMode(u"invalid"_s);
        DiscordVoice system(settings, true, applicationId);
        const bool valid = check(system.proxyMode() == u"system"_s
                && system.m_oauth.m_network.proxy().type() == QNetworkProxy::DefaultProxy
                && system.m_avatarNetwork.proxy().type() == QNetworkProxy::DefaultProxy,
            "Switching back to the system route must clear the proxy override");
        settings.remove(u"discord/proxyMode"_s);
        return valid;
    }

    static bool recoverFromTokenTimeout(QSettings &settings)
    {
        MockTokenEndpoint proxy;
        MockTokenEndpoint server;
        if (!check(proxy.server.listen(QHostAddress::LocalHost) && server.server.listen(QHostAddress::LocalHost),
                "Could not start the mock proxy and direct endpoint"))
            return false;

        DiscordOAuth oauth(settings);
        oauth.setClientId(applicationId);
        QString failure;
        int grants = 0;
        QObject::connect(&oauth, &DiscordOAuth::failed, &oauth, [&](const QString &message) { failure = message; });
        QObject::connect(&oauth, &DiscordOAuth::granted, &oauth, [&] { ++grants; });
        QUrlQuery parameters;
        parameters.addQueryItem(u"grant_type"_s, u"authorization_code"_s);
        parameters.addQueryItem(u"code"_s, u"mock-code"_s);

        proxy.holdResponse = true;
        oauth.m_exchangeTimeout.setInterval(400);
        oauth.m_tokenEndpoint = QUrl(u"http://discord.invalid/api/v10/oauth2/token"_s);
        oauth.setProxy(QNetworkProxy(QNetworkProxy::HttpProxy, u"127.0.0.1"_s, proxy.server.serverPort()));
        oauth.exchange(parameters, false);
        if (!check(waitFor([&] { return !failure.isEmpty(); }) && !oauth.busy() && grants == 0
                && proxy.requestCount == 1 && failure.contains(u"обмен кода входа"_s) && failure.contains(u"INCY HTTP"_s),
                "A stalled proxy must report the login stage and route without replaying the authorization code"))
            return false;

        failure.clear();
        oauth.m_exchangeTimeout.setInterval(1400);
        oauth.setProxy(QNetworkProxy::NoProxy);
        oauth.m_tokenEndpoint = QUrl(u"http://127.0.0.1:%1/api/v10/oauth2/token"_s.arg(server.server.serverPort()));
        server.status = "200 OK";
        server.body = R"({"access_token":"direct-access","refresh_token":"direct-refresh","expires_in":3600,
            "scope":"identify rpc rpc.voice.read rpc.voice.write"})";
        parameters.removeAllQueryItems(u"code"_s);
        parameters.addQueryItem(u"code"_s, u"new-code"_s);
        oauth.exchange(parameters, false);
        if (!check(waitFor([&] { return grants == 1; }) && oauth.usable() && oauth.renewable()
                && server.requestHeaders.startsWith("POST /api/v10/oauth2/token HTTP/1.1")
                && server.form.queryItemValue(u"code"_s) == u"new-code"_s && proxy.requestCount == 1,
                "A fresh direct request must reach the endpoint after a proxy timeout"))
            return false;

        server.holdResponse = true;
        oauth.m_exchangeTimeout.setInterval(400);
        oauth.refresh();
        const bool valid = check(waitFor([&] { return !failure.isEmpty(); }) && !oauth.busy()
                && failure.contains(u"обновление доступа"_s) && failure.contains(u"Прямое"_s)
                && oauth.usable() && oauth.renewable() && server.requestCount == 2,
                "A direct refresh timeout must keep the grant, report the route and avoid retransmission");
        oauth.forget();
        return valid;
    }

    static bool avatarDownload(QSettings &settings)
    {
        MockTokenEndpoint proxy;
        if (!check(proxy.server.listen(QHostAddress::LocalHost), "Could not listen on the mock avatar proxy"))
            return false;
        proxy.status = "200 OK";
        proxy.body.clear();
        QImage pixels(2, 2, QImage::Format_RGB32);
        pixels.fill(Qt::green);
        QBuffer buffer(&proxy.body);
        if (!check(buffer.open(QIODevice::WriteOnly) && pixels.save(&buffer, "PNG"), "Could not create the mock PNG"))
            return false;

        DiscordVoice voice(settings, true, applicationId);
        voice.m_avatarNetwork.setProxy(QNetworkProxy(QNetworkProxy::HttpProxy, u"127.0.0.1"_s, proxy.server.serverPort()));
        const QUrl url(u"http://discord.invalid/avatar.png"_s);
        voice.fetchAvatar(url);
        if (!check(waitFor([&] { return voice.m_avatars.contains(url); })
                && voice.m_avatars.value(url).size() == pixels.size()
                && voice.m_avatars.value(url).pixelColor(0, 0) == QColor(Qt::green)
                && proxy.requestHeaders.startsWith("GET http://discord.invalid/avatar.png")
                && !proxy.requestHeaders.toLower().contains("authorization:")
                && !proxy.requestHeaders.toLower().contains("cookie:"),
                "Avatar bytes must use the selected proxy, carry no grant or cookies, and stay in memory"))
            return false;

        proxy.body = "An invalid image";
        const QUrl invalid(u"http://discord.invalid/invalid.png"_s);
        voice.fetchAvatar(invalid);
        if (!check(waitFor([&] { return voice.m_avatars.contains(invalid); }) && voice.m_avatars.value(invalid).isNull(),
                "An invalid image must leave the initials fallback available"))
            return false;
        voice.syncAvatars({});
        return check(voice.m_avatars.isEmpty() && voice.m_avatarRequests.isEmpty(),
            "Avatar data must be released on leaving the voice channel");
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
        MockTokenEndpoint avatarProxy;
        const auto endpoint = u"sekai-voice-test-"_s + QUuid::createUuid().toString(QUuid::WithoutBraces);
        if (!check(discord.server.listen(endpoint), "Could not listen on the mock Discord IPC endpoint")
            || !check(avatarProxy.server.listen(QHostAddress::LocalHost), "Could not listen on the mock CDN proxy"))
            return false;
        const auto hash = u"a_0123456789abcdef0123456789abcdef"_s;
        discord.authUser.insert(u"global_name"_s, u"Алекс Р."_s);
        discord.authUser.insert(u"avatar"_s, hash);

        DiscordVoice invalid(settings, true, u"invalid"_s, {endpoint});
        invalid.connectDiscord();
        if (!check(!invalid.available() && !invalid.linked(), "An invalid build Application ID must not connect"))
            return false;

        settings.setValue(u"discord/clientId"_s, voiceId);
        DiscordVoice voice(settings, true, applicationId, {endpoint + u"-missing"_s, endpoint});
        voice.m_avatarNetwork.setProxy(QNetworkProxy(QNetworkProxy::HttpProxy, u"127.0.0.1"_s,
            avatarProxy.server.serverPort()));
        voice.m_oauth.setClientId(applicationId);
        voice.m_oauth.m_accessToken = mockAccess;
        voice.m_oauth.m_expiresAt = QDateTime::currentMSecsSinceEpoch() + 3600000;
        voice.connectDiscord();
        if (!check(waitFor([&] { return voice.canChangeVoice() && discord.pongReceived
                && voice.m_subscribed.contains(u"SPEAKING_START"_s) && voice.m_voiceStatusSubscribed; }),
                "The handshake, fragmented READY, ping and authenticated subscriptions must work")
            || !check(!discord.wrongHandshake && !discord.wrongToken && voice.room() == u"Ночной эфир"_s
                && voice.participantCount() == 2 && voice.voiceStatus() == u"unknown"_s,
                "Connect must expose the selected room and deduplicate users without inferring the voice status"))
            return false;

        const auto own = voice.participants().at(0).toMap();
        const auto peer = voice.participants().at(1).toMap();
        const QUrl peerDefault(u"https://cdn.discordapp.com/embed/avatars/%1.png"_s.arg((peerId.toULongLong() >> 22) % 6));
        if (!check(own.value(u"participantId"_s) == ownId && own.value(u"localUser"_s).toBool()
                && own.value(u"name"_s) == u"Алекс Р."_s
                && own.value(u"avatarUrl"_s).toUrl() == QUrl(u"https://cdn.discordapp.com/avatars/%1/%2.png?size=128"_s.arg(ownId, hash))
                && peer.value(u"participantId"_s) == peerId && !peer.value(u"localUser"_s).toBool()
                && peer.value(u"name"_s) == u"Мира"_s && peer.value(u"avatarUrl"_s).toUrl() == peerDefault,
                "Rows must use stable IDs, self first, nicknames and validated custom or default CDN paths"))
            return false;

        const auto setStatus = [&](const QString &state, const QString &expected) {
            discord.sendEvent(u"VOICE_CONNECTION_STATUS"_s, {{u"state"_s, state}});
            return check(waitFor([&] { return voice.voiceStatus() == expected; }) && voice.connected(),
                "Voice status must follow the confirmed RPC state while selection remains active");
        };
        if (!setStatus(u"CONNECTED"_s, u"connecting"_s) || !setStatus(u"VOICE_CONNECTED"_s, u"connected"_s)
            || !setStatus(u"NO_ROUTE"_s, u"disconnected"_s) || !setStatus(u"ICE_CHECKING"_s, u"connecting"_s)
            || !setStatus(u"VOICE_DISCONNECTED"_s, u"disconnected"_s) || !setStatus(u"NEW_STATE"_s, u"unknown"_s)
            || !setStatus(u"VOICE_CONNECTED"_s, u"connected"_s))
            return false;

        auto *model = voice.participantModel();
        const QPersistentModelIndex peerIndex(model->index(1, 0));
        const auto speakingRole = model->roleNames().key("speaking");
        int modelResets = 0;
        QObject::connect(model, &QAbstractItemModel::modelReset, &voice, [&] { ++modelResets; });
        discord.sendEvent(u"SPEAKING_START"_s, {{u"user_id"_s, peerId}});
        if (!check(waitFor([&] { return peerIndex.data(speakingRole).toBool(); }) && modelResets == 0
                && model == voice.participantModel() && voice.participantCount() == 2,
                "Speaking events must update the existing participant row without rebuilding the model"))
            return false;
        discord.sendEvent(u"VOICE_STATE_UPDATE"_s, {{u"user_id"_s, peerId}, {u"nick"_s, QJsonValue()},
            {u"voice_state"_s, QJsonObject{{u"self_mute"_s, true}}}});
        if (!check(waitFor([&] { return peerIndex.data(model->roleNames().key("micOff")).toBool(); })
                && !peerIndex.data(speakingRole).toBool() && peerIndex.data(model->roleNames().key("name")) == u"Мирослава"_s,
                "A partial voice-state update must preserve identity, use the global name and suppress muted speech"))
            return false;
        discord.sendEvent(u"VOICE_STATE_DELETE"_s, {{u"user_id"_s, peerId}});
        if (!check(waitFor([&] { return voice.participantCount() == 1; }) && !peerIndex.isValid(),
                "Leaving participants must disappear from the model and count"))
            return false;
        const auto rejoined = member(peerId, u"mira"_s, u"Алекс Р."_s);
        discord.sendEvent(u"VOICE_STATE_CREATE"_s, rejoined);
        discord.sendEvent(u"VOICE_STATE_CREATE"_s, rejoined);
        if (!check(waitFor([&] { return voice.participantCount() == 2; })
                && voice.participants().at(1).toMap().value(u"participantId"_s) == peerId
                && voice.participants().at(1).toMap().value(u"name"_s) == own.value(u"name"_s),
                "Repeated join events must deduplicate by ID and allow equal names"))
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
            {u"voice_states"_s, QJsonArray{member(ownId, u"self"_s, u"Алекс в Discord"_s),
                member(peerId, u"mira"_s, u"Мира"_s)}}};
        discord.sendEvent(u"VOICE_CHANNEL_SELECT"_s, {{u"channel_id"_s, directId}});
        if (!check(waitFor([&] { return voice.voiceStatus() == u"unknown"_s; }) && voice.channelId() == voiceId,
                "A new selection must invalidate the old status before its snapshot arrives"))
            return false;
        discord.sendEvent(u"VOICE_CONNECTION_STATUS"_s, {{u"state"_s, u"VOICE_CONNECTED"_s}, {u"channel_id"_s, voiceId}});
        discord.sendEvent(u"VOICE_CONNECTION_STATUS"_s, {{u"state"_s, u"VOICE_CONNECTING"_s}});
        discord.holdQuery = false;
        discord.reply(discord.heldQuery, oldChannel);
        if (!check(waitFor([&] { return voice.room() == u"Мира"_s
                && discord.subscriptions.contains(u"VOICE_STATE_CREATE:"_s + directId); })
                && voice.channelId() == directId && voice.voiceStatus() == u"connecting"_s
                && voice.participants().at(0).toMap().value(u"name"_s) == u"Алекс в Discord"_s
                && !discord.subscriptions.contains(u"VOICE_STATE_CREATE:"_s + voiceId),
                "A newer DM selection must replace the stale snapshot, subscriptions and old voice status"))
            return false;

        discord.socket->disconnectFromServer();
        if (!check(waitFor([&] { return !voice.connected(); }) && voice.voiceStatus() == u"unknown"_s
                && voice.participantCount() == 0, "Lost IPC must clear the live roster and reset voice status")
            || !check(waitFor([&] { return discord.authCount == 2 && voice.connected() && voice.canHangUp(); }, 4500)
                && voice.voiceStatus() == u"unknown"_s,
                "Discord must reconnect and recover the selected channel without a second sign-in"))
            return false;
        voice.hangUp();
        if (!check(waitFor([&] { return !voice.connected(); }) && discord.channel.isEmpty()
                && discord.lastMutation.contains(u"channel_id"_s) && discord.lastMutation.value(u"channel_id"_s).isNull(),
                "Hang-up must send a null channel ID and close only after Discord replies"))
            return false;

        discord.writeScope = false;
        discord.voiceStatusSupported = false;
        discord.channel = {{u"id"_s, voiceId}, {u"name"_s, u"Просмотр"_s}, {u"type"_s, 2}};
        discord.socket->disconnectFromServer();
        if (!check(waitFor([&] { return voice.connected() && discord.authCount == 3 && voice.m_settingsKnown; }, 4500)
                && !voice.canHangUp() && !voice.canChangeVoice() && !voice.m_voiceStatusSubscribed
                && voice.participantCount() == 1 && voice.voiceStatus() == u"unknown"_s,
                "Read-only grants and unsupported status subscriptions must leave the selected roster accessible"))
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
    app.setApplicationVersion(u"1.0"_s);
    QTemporaryDir data;
    if (!data.isValid())
        return 1;
    QSettings settings(data.filePath(u"test.ini"_s), QSettings::IniFormat);
    return DiscordVoiceTest::oauth(settings) && DiscordVoiceTest::tokenExchange(settings)
        && DiscordVoiceTest::proxyPreference(settings) && DiscordVoiceTest::recoverFromTokenTimeout(settings)
        && DiscordVoiceTest::avatarDownload(settings)
        && DiscordVoiceTest::storedGrant(settings)
        && DiscordVoiceTest::voice(settings) ? 0 : 1;
}

#include "DiscordVoiceTest.moc"
