#include "DiscordOAuth.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QRandomGenerator>
#include <QSettings>
#include <QTcpSocket>
#include <QUrlQuery>
#include <utility>

#ifdef Q_OS_WIN
#include <windows.h>
#include <wincrypt.h>
#endif

using namespace Qt::StringLiterals;

namespace {

constexpr quint16 callbackPort = 43827;
constexpr qsizetype maxHeader = 8192;
constexpr qint64 maxReply = 64 * 1024;
constexpr int tokenTimeoutMs = 30000;
const auto callbackPath = u"/discord/callback"_s;
const auto grantKey = u"discord/grant"_s;

QString randomValue()
{
    QByteArray bytes;
    for (int index = 0; index < 8; ++index) {
        const auto value = QRandomGenerator::system()->generate();
        bytes.append(reinterpret_cast<const char *>(&value), sizeof(value));
    }
    return QString::fromLatin1(bytes.toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals));
}

QByteArray formBody(const QUrlQuery &parameters)
{
    QByteArray body;
    for (const auto &[key, value] : parameters.queryItems(QUrl::FullyDecoded)) {
        if (!body.isEmpty())
            body.append('&');
        body.append(QUrl::toPercentEncoding(key) + '=' + QUrl::toPercentEncoding(value));
    }
    return body;
}

QString routeName(QNetworkProxy::ProxyType type)
{
    switch (type) {
    case QNetworkProxy::NoProxy:
        return u"Прямое"_s;
    case QNetworkProxy::HttpProxy:
        return u"INCY HTTP"_s;
    case QNetworkProxy::Socks5Proxy:
        return u"INCY SOCKS5"_s;
    default:
        return u"Системное"_s;
    }
}

QString exchangeFailure(int status, QNetworkReply::NetworkError networkError, const QString &error,
                        bool refreshing, bool timedOut, QNetworkProxy::ProxyType route)
{
    if (error == u"invalid_grant"_s) {
        return refreshing ? u"Срок сохранённого разрешения истёк. Нажмите «Подключить Discord»."_s
                          : u"Discord отклонил код входа. Подключитесь снова и подтвердите доступ в новой вкладке."_s;
    }
    if (error == u"invalid_scope"_s)
        return u"Discord отклонил запрос на доступ к голосовым каналам (invalid_scope)."_s;
    if (error == u"invalid_client"_s || error == u"unauthorized_client"_s || error == u"invalid_request"_s)
        return u"Discord отклонил запрос Sekai Soundbar (%1)."_s.arg(error);
    if (status == 429)
        return u"Discord ограничил частоту запросов (HTTP 429). Попробуйте подключиться чуть позже."_s;
    const auto connection = u" Соединение «%1»."_s.arg(routeName(route));
    if (timedOut || networkError == QNetworkReply::TimeoutError) {
        return (refreshing ? u"Discord не ответил вовремя на обновление доступа."_s
                           : u"Discord не ответил вовремя на обмен кода входа."_s) + connection;
    }
    if (status && status != 200)
        return u"Запрос на вход в Discord завершился с ошибкой HTTP %1."_s.arg(status);

    switch (networkError) {
    case QNetworkReply::SslHandshakeFailedError:
        return u"Док не смог установить защищённое соединение с Discord (TLS)."_s + connection;
    case QNetworkReply::ProxyConnectionRefusedError:
    case QNetworkReply::ProxyConnectionClosedError:
    case QNetworkReply::ProxyNotFoundError:
    case QNetworkReply::ProxyTimeoutError:
    case QNetworkReply::ProxyAuthenticationRequiredError:
        return u"Прокси не открыл соединение с Discord (сеть %1)."_s.arg(int(networkError)) + connection;
    case QNetworkReply::NoError:
        return u"Discord вернул некорректный ответ при входе (HTTP %1)."_s.arg(status);
    default:
        return u"Док не смог связаться с Discord (сеть %1)."_s.arg(int(networkError)) + connection;
    }
}

void sendPage(QTcpSocket &socket, bool received)
{
    const QByteArray header = received ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 400 Bad Request\r\n";
    const QByteArray message = received
        ? "<!doctype html><meta charset=utf-8><title>Sekai Soundbar</title>"
          "<p>Ответ Discord получен. Вернитесь в Sekai Soundbar.</p>"
        : "<!doctype html><meta charset=utf-8><title>Sekai Soundbar</title>"
          "<p>Этот запрос не совпадает с активным входом в Sekai Soundbar.</p>";
    socket.write(header + "Content-Type: text/html; charset=utf-8\r\n"
        "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n"
        "Content-Length: " + QByteArray::number(message.size()) + "\r\n\r\n" + message);
    socket.disconnectFromHost();
}

QByteArray protectGrant(QByteArray bytes, bool encrypt)
{
#ifdef Q_OS_WIN
    if (bytes.isEmpty() || bytes.size() > maxReply)
        return {};
    DATA_BLOB input{DWORD(bytes.size()), reinterpret_cast<BYTE *>(bytes.data())};
    DATA_BLOB output{};
    const BOOL success = encrypt
        ? CryptProtectData(&input, L"Sekai Soundbar Discord OAuth", nullptr, nullptr, nullptr,
              CRYPTPROTECT_UI_FORBIDDEN, &output)
        : CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output);
    if (!success)
        return {};
    const QByteArray result(reinterpret_cast<const char *>(output.pbData), output.cbData);
    SecureZeroMemory(output.pbData, output.cbData);
    LocalFree(output.pbData);
    return result;
#else
    Q_UNUSED(bytes);
    Q_UNUSED(encrypt);
    return {};
#endif
}

}

DiscordOAuth::DiscordOAuth(QSettings &settings, QObject *parent)
    : QObject(parent), m_settings(settings)
{
    m_callback.setProxy(QNetworkProxy::NoProxy);
    m_callback.setMaxPendingConnections(8);
    m_consentTimeout.setSingleShot(true);
    m_exchangeTimeout.setSingleShot(true);
    m_exchangeTimeout.setInterval(tokenTimeoutMs);
    connect(&m_callback, &QTcpServer::newConnection, this, &DiscordOAuth::acceptCallbacks);
    connect(&m_consentTimeout, &QTimer::timeout, this, [this] {
        cancel();
        emit failed(u"Время входа истекло. Подключите Discord ещё раз."_s);
    });
    connect(&m_exchangeTimeout, &QTimer::timeout, this, [this] {
        if (m_reply)
            m_reply->abort();
    });
}

DiscordOAuth::~DiscordOAuth()
{
    cancel();
}

QString DiscordOAuth::redirectUri()
{
    return u"http://127.0.0.1:%1%2"_s.arg(callbackPort).arg(callbackPath);
}

QStringList DiscordOAuth::scopes()
{
    return {u"identify"_s, u"rpc"_s, u"rpc.voice.read"_s, u"rpc.voice.write"_s};
}

void DiscordOAuth::setProxy(const QNetworkProxy &proxy)
{
    m_network.setProxy(proxy);
    m_network.clearConnectionCache();
}

void DiscordOAuth::setClientId(const QString &clientId)
{
    if (m_clientId == clientId)
        return;
    cancel();
    m_clientId = clientId;
    m_accessToken.clear();
    m_refreshToken.clear();
    m_expiresAt = 0;
    restoreGrant();
}

bool DiscordOAuth::usable() const
{
    return !m_accessToken.isEmpty() && m_expiresAt - QDateTime::currentMSecsSinceEpoch() > 60000;
}

void DiscordOAuth::authorize()
{
    if (m_clientId.isEmpty() || busy())
        return;
    if (!m_callback.listen(QHostAddress::LocalHost, callbackPort)) {
        emit failed(u"Порт для входа в Discord занят. Закройте другое приложение на порту %1 и повторите."_s
            .arg(callbackPort));
        return;
    }

    m_state = randomValue();
    m_verifier = randomValue();
    const auto challenge = QCryptographicHash::hash(m_verifier.toLatin1(), QCryptographicHash::Sha256)
        .toBase64(QByteArray::Base64UrlEncoding | QByteArray::OmitTrailingEquals);
    QUrl url(u"https://discord.com/oauth2/authorize"_s);
    QUrlQuery query;
    query.addQueryItem(u"client_id"_s, m_clientId);
    query.addQueryItem(u"response_type"_s, u"code"_s);
    query.addQueryItem(u"redirect_uri"_s, redirectUri());
    query.addQueryItem(u"scope"_s, scopes().join(u' '));
    query.addQueryItem(u"state"_s, m_state);
    query.addQueryItem(u"code_challenge"_s, QString::fromLatin1(challenge));
    query.addQueryItem(u"code_challenge_method"_s, u"S256"_s);
    url.setQuery(query);
    if (!QDesktopServices::openUrl(url)) {
        cancel();
        emit failed(u"Не удалось открыть страницу входа в Discord."_s);
        return;
    }
    m_consentTimeout.start(180000);
    emit authorizing();
}

void DiscordOAuth::acceptCallbacks()
{
    while (auto *socket = m_callback.nextPendingConnection()) {
        socket->setReadBufferSize(maxHeader + 1);
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QTcpSocket::readyRead, this, [this, socket, buffer = QByteArray{}]() mutable {
            buffer.append(socket->readAll());
            if (buffer.size() > maxHeader || buffer.contains("\r\n\r\n")) {
                socket->disconnect(this);
                handleCallback(*socket, buffer);
            }
        });
        QTimer::singleShot(5000, socket, [socket] { socket->abort(); });
    }
}

void DiscordOAuth::handleCallback(QTcpSocket &socket, const QByteArray &request)
{
    const auto firstLine = request.left(request.indexOf("\r\n")).split(' ');
    const auto target = firstLine.size() == 3 ? QUrl::fromEncoded(firstLine.at(1), QUrl::StrictMode) : QUrl();
    const QUrlQuery query(target);
    const auto states = query.allQueryItemValues(u"state"_s, QUrl::FullyDecoded);
    const auto issuer = query.queryItemValue(u"iss"_s, QUrl::FullyDecoded);
    if (request.size() > maxHeader || firstLine.value(0) != "GET" || !target.isValid()
        || !target.isRelative() || !target.authority().isEmpty() || target.path() != callbackPath
        || m_state.isEmpty() || states.size() != 1 || states.front() != m_state
        || (!issuer.isEmpty() && issuer != u"https://discord.com"_s)) {
        sendPage(socket, false);
        return;
    }

    const auto codes = query.allQueryItemValues(u"code"_s, QUrl::FullyDecoded);
    const auto verifier = m_verifier;
    cancel();
    sendPage(socket, true);
    if (codes.size() != 1 || codes.front().isEmpty() || codes.front().size() > 1024) {
        const bool denied = query.queryItemValue(u"error"_s) == u"access_denied"_s;
        emit failed(denied ? u"Доступ не был подтверждён. Нажмите «Подключить Discord», чтобы повторить."_s
                           : u"Discord не выдал Sekai Soundbar разрешение на подключение."_s);
        return;
    }

    QUrlQuery parameters;
    parameters.addQueryItem(u"grant_type"_s, u"authorization_code"_s);
    parameters.addQueryItem(u"code"_s, codes.front());
    parameters.addQueryItem(u"code_verifier"_s, verifier);
    parameters.addQueryItem(u"redirect_uri"_s, redirectUri());
    exchange(parameters, false);
}

void DiscordOAuth::refresh()
{
    if (!renewable() || busy())
        return;
    QUrlQuery parameters;
    parameters.addQueryItem(u"grant_type"_s, u"refresh_token"_s);
    parameters.addQueryItem(u"refresh_token"_s, m_refreshToken);
    exchange(parameters, true);
}

void DiscordOAuth::exchange(QUrlQuery parameters, bool refreshing)
{
    parameters.addQueryItem(u"client_id"_s, m_clientId);
    QNetworkRequest request(m_tokenEndpoint);
    request.setRawHeader("User-Agent", "DiscordBot (https://github.com/Aferon-08/sekaipop-dock-equalizer-windows, "
        + QCoreApplication::applicationVersion().toUtf8() + ')');
    request.setRawHeader("Accept", "application/json");
    request.setHeader(QNetworkRequest::ContentTypeHeader, u"application/x-www-form-urlencoded"_s);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    // A new exchange should pick up changes to the Windows proxy or the INCY tunnel.
    m_network.clearConnectionCache();
    const auto route = m_network.proxy().type();
    auto *reply = m_network.post(request, formBody(parameters));
    m_reply = reply;
    m_exchangeTimeout.start();
    reply->setReadBufferSize(maxReply + 1);
    connect(reply, &QNetworkReply::downloadProgress, this, [reply](qint64 received, qint64 total) {
        if (received > maxReply || total > maxReply)
            reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, refreshing, route] {
        const bool timedOut = !m_exchangeTimeout.isActive() && reply->error() == QNetworkReply::OperationCanceledError;
        m_exchangeTimeout.stop();
        m_reply = nullptr;
        reply->deleteLater();
        const auto bytes = reply->readAll();
        const auto data = bytes.size() <= maxReply ? QJsonDocument::fromJson(bytes).object() : QJsonObject();
        const auto error = data.value(u"error"_s).toString();
        const auto access = data.value(u"access_token"_s).toString();
        const auto refresh = data.value(u"refresh_token"_s).toString();
        const auto lifetime = data.value(u"expires_in"_s).toInt();
        const auto grantedScopes = data.value(u"scope"_s).toString().split(u' ', Qt::SkipEmptyParts);
        const auto httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() != QNetworkReply::NoError || httpStatus != 200 || access.isEmpty()
            || access.size() > 4096 || refresh.size() > 4096 || lifetime <= 60) {
            if (refreshing && (error == u"invalid_grant"_s || error == u"invalid_client"_s))
                forget();
            emit failed(exchangeFailure(httpStatus, reply->error(), error, refreshing, timedOut, route));
            return;
        }
        if (!grantedScopes.contains(u"rpc"_s) || !grantedScopes.contains(u"rpc.voice.read"_s)) {
            forget();
            emit failed(u"Discord не выдал разрешение на чтение голосовых сессий RPC."_s);
            return;
        }
        m_accessToken = access;
        if (!refresh.isEmpty() || !refreshing)
            m_refreshToken = refresh;
        m_expiresAt = QDateTime::currentMSecsSinceEpoch() + qint64(lifetime) * 1000;
        saveGrant();
        emit granted();
    });
    emit exchanging();
}

void DiscordOAuth::cancel()
{
    m_callback.close();
    m_consentTimeout.stop();
    m_exchangeTimeout.stop();
    m_state.clear();
    m_verifier.clear();
    if (auto *reply = std::exchange(m_reply, nullptr)) {
        reply->disconnect(this);
        reply->abort();
        reply->deleteLater();
    }
}

void DiscordOAuth::forget()
{
    m_accessToken.clear();
    m_refreshToken.clear();
    m_expiresAt = 0;
    m_settings.remove(grantKey);
}

void DiscordOAuth::restoreGrant()
{
    const auto data = QJsonDocument::fromJson(protectGrant(m_settings.value(grantKey).toByteArray(), false)).object();
    if (m_clientId.isEmpty() || data.value(u"client_id"_s).toString() != m_clientId)
        return;
    m_accessToken = data.value(u"access_token"_s).toString();
    m_refreshToken = data.value(u"refresh_token"_s).toString();
    m_expiresAt = data.value(u"expires_at"_s).toInteger();
}

void DiscordOAuth::saveGrant()
{
    const QJsonObject data{{u"client_id"_s, m_clientId}, {u"access_token"_s, m_accessToken},
        {u"refresh_token"_s, m_refreshToken}, {u"expires_at"_s, m_expiresAt}};
    const auto encrypted = protectGrant(QJsonDocument(data).toJson(QJsonDocument::Compact), true);
    if (!encrypted.isEmpty())
        m_settings.setValue(grantKey, encrypted);
}
