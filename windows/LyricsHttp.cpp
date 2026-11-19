#include "LyricsHttp.h"

#include <QDir>
#include <QFileInfo>
#include <QHostAddress>
#include <QJsonDocument>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSslSocket>
#include <QStringList>
#include <QTimer>

#ifdef Q_OS_WIN
#include <QtCore/qt_windows.h>
#endif

#include <utility>

namespace {

constexpr qsizetype responseLimit = 2 * 1024 * 1024;
constexpr qsizetype curlTrailerLimit = 160;
constexpr QByteArrayView curlTrailerPrefix = "SEKAI_HTTP ";
constexpr auto userAgent = "SekaiSoundbar (https://github.com/Aferon-08/sekaipop-dock-equalizer-windows)";

QString curlError(int code)
{
    QString reason;
    switch (code) {
    case 5:
    case 97: reason = QStringLiteral("ошибка прокси"); break;
    case 6: reason = QStringLiteral("DNS не нашёл сервер"); break;
    case 7: reason = QStringLiteral("не удалось подключиться"); break;
    case 18:
    case 56: reason = QStringLiteral("ответ оборвался"); break;
    case 28: reason = QStringLiteral("истекло время ожидания"); break;
    case 35:
    case 51:
    case 60:
    case 77: reason = QStringLiteral("ошибка TLS"); break;
    case 63: return QStringLiteral("слишком большой ответ");
    default: reason = QStringLiteral("ошибка запроса"); break;
    }
    return QStringLiteral("%1 (curl %2)").arg(reason).arg(code);
}

struct CurlTiming
{
    qsizetype bodyEnd = -1;
    int status = 0;
    int proxyStatus = 0;
    double dns = 0;
    double tcp = 0;
    double tls = 0;
    double firstByte = 0;
};

int httpStatus(const QByteArray &value)
{
    bool valid = false;
    const int status = value.toInt(&valid);
    return valid && value.size() == 3 && status >= 100 && status <= 599 ? status : 0;
}

CurlTiming readTiming(const QByteArray &bytes)
{
    const auto separator = bytes.lastIndexOf('\n');
    if (separator < 0 || bytes.size() - separator > curlTrailerLimit)
        return {};
    const auto trailer = QByteArrayView(bytes).sliced(separator + 1);
    if (!trailer.startsWith(curlTrailerPrefix))
        return {};
    const auto parts = trailer.sliced(curlTrailerPrefix.size()).toByteArray().split(' ');
    if (parts.size() != 6)
        return {};
    return {separator, httpStatus(parts[0]), httpStatus(parts[1]), parts[2].toDouble(), parts[3].toDouble(),
        parts[4].toDouble(), parts[5].toDouble()};
}

QString interruptedTransfer(int code, const CurlTiming &timing, bool https)
{
    const QString base = curlError(code);
    if (timing.bodyEnd < 0)
        return base;
    if (timing.status >= 200) {
        return base + QStringLiteral(" · HTTP %1, получено %2 Б").arg(timing.status).arg(timing.bodyEnd);
    }
    if (timing.firstByte > 0 || timing.tls > 0 || (!https && timing.tcp > 0))
        return base + QStringLiteral(" · ожидание HTTP-ответа");
    if (timing.tcp > 0)
        return base + QStringLiteral(" · после TCP, до HTTPS");
    if (timing.dns > 0)
        return base + QStringLiteral(" · после DNS, до TCP");
    return base + QStringLiteral(" · соединение не установлено");
}

bool completeJson(int status, const QByteArray &body)
{
    return status >= 200 && status < 300 && !QJsonDocument::fromJson(body).isNull();
}

QString qtError(QNetworkReply::NetworkError error)
{
    switch (error) {
    case QNetworkReply::NoError: return {};
    case QNetworkReply::HostNotFoundError: return QStringLiteral("DNS не нашёл сервер (Qt)");
    case QNetworkReply::SslHandshakeFailedError: return QStringLiteral("ошибка TLS (Qt)");
    case QNetworkReply::ProxyConnectionRefusedError:
    case QNetworkReply::ProxyConnectionClosedError:
    case QNetworkReply::ProxyNotFoundError:
    case QNetworkReply::ProxyTimeoutError:
    case QNetworkReply::ProxyAuthenticationRequiredError:
        return QStringLiteral("ошибка прокси (Qt %1)").arg(int(error));
    case QNetworkReply::TimeoutError:
    case QNetworkReply::OperationCanceledError: return QStringLiteral("истекло время ожидания (Qt)");
    default: return QStringLiteral("ошибка подключения (Qt %1)").arg(int(error));
    }
}

} // namespace

LyricsHttp::LyricsHttp(QString curlExecutable)
    : m_curl(std::move(curlExecutable))
{
}

LyricsHttp::~LyricsHttp()
{
    cancel();
}

QString LyricsHttp::windowsCurl()
{
#ifdef Q_OS_WIN
    wchar_t directory[MAX_PATH + 1]{};
    const auto length = GetSystemDirectoryW(directory, MAX_PATH + 1);
    if (length > 0 && length <= MAX_PATH) {
        const auto path = QDir(QString::fromWCharArray(directory, length)).filePath(QStringLiteral("curl.exe"));
        if (QFileInfo(path).isFile())
            return path;
    }
#endif
    return {};
}

bool LyricsHttp::supportsHttps() const
{
    return !m_curl.isEmpty() || QSslSocket::supportsSsl();
}

bool LyricsHttp::setProxyAddress(const QString &address)
{
    const auto text = address.trimmed();
    QUrl proxy(text, QUrl::StrictMode);
    if (!text.isEmpty()) {
        if (proxy.scheme() == QStringLiteral("socks5"))
            proxy.setScheme(QStringLiteral("socks5h"));
        const auto host = proxy.host();
        if (!proxy.isValid() || (proxy.scheme() != QStringLiteral("http") && proxy.scheme() != QStringLiteral("socks5h"))
                || (host != QStringLiteral("localhost") && !QHostAddress(host).isLoopback()) || proxy.port() <= 0
                || proxy.authority().contains(u'@') || proxy.hasQuery() || proxy.hasFragment()
                || (!proxy.path().isEmpty() && proxy.path() != QStringLiteral("/")))
            return false;
        proxy.setPath(QString());
    }
    if (m_proxy == proxy)
        return true;

    cancel();
    m_proxy = proxy;
    if (m_proxy.isEmpty()) {
        m_network.setProxy(QNetworkProxy::DefaultProxy);
    } else {
        const auto type = m_proxy.scheme() == QStringLiteral("http") ? QNetworkProxy::HttpProxy : QNetworkProxy::Socks5Proxy;
        m_network.setProxy(QNetworkProxy(type, m_proxy.host(), quint16(m_proxy.port())));
    }
    m_network.clearConnectionCache();
    return true;
}

void LyricsHttp::get(const QUrl &url, Completion done, const QString &referer)
{
    if (m_curl.isEmpty())
        getWithQt(url, std::move(done), referer);
    else
        getWithCurl(url, std::move(done), referer);
}

void LyricsHttp::cancel()
{
    const auto replies = m_qtRequests.keys();
    const auto processes = m_curlRequests.keys();
    m_qtRequests.clear();
    m_curlRequests.clear();
    for (auto *reply : replies) {
        disconnect(reply, nullptr, this, nullptr);
        reply->abort();
        reply->deleteLater();
    }
    for (auto *process : processes) {
        disconnect(process, nullptr, this, nullptr);
        process->kill();
        process->deleteLater();
    }
}

void LyricsHttp::getWithQt(const QUrl &url, Completion done, const QString &referer)
{
    if (url.scheme() == QStringLiteral("https") && !QSslSocket::supportsSsl()) {
        done({0, {}, QStringLiteral("HTTPS недоступен. Распакуйте ZIP целиком.")});
        return;
    }

    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", userAgent);
    request.setRawHeader("Accept", "application/json");
    request.setRawHeader("Connection", "close");
    if (!referer.isEmpty())
        request.setRawHeader("Referer", referer.toUtf8());
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::SameOriginRedirectPolicy);
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    request.setTransferTimeout(7500);
    auto *reply = m_network.get(request);
    m_qtRequests.insert(reply, {std::move(done), {}});
    reply->setReadBufferSize(responseLimit + 1);
    connect(reply, &QNetworkReply::readyRead, this, [this, reply] {
        auto it = m_qtRequests.find(reply);
        if (it == m_qtRequests.end())
            return;
        it->bytes += reply->read(responseLimit + 1 - it->bytes.size());
        if (it->bytes.size() > responseLimit)
            reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply] { finishQt(reply); });
    QTimer::singleShot(10000, reply, [reply] { if (!reply->isFinished()) reply->abort(); });
}

void LyricsHttp::finishQt(QNetworkReply *reply)
{
    auto request = m_qtRequests.take(reply);
    if (!request.done)
        return;
    reply->deleteLater();
    if (request.bytes.size() <= responseLimit && reply->isReadable())
        request.bytes += reply->read(responseLimit + 1 - request.bytes.size());
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const auto networkError = reply->error();
    const bool interrupted = networkError == QNetworkReply::TimeoutError
        || networkError == QNetworkReply::OperationCanceledError
        || networkError == QNetworkReply::RemoteHostClosedError;
    QString error;
    if (request.bytes.size() > responseLimit)
        error = QStringLiteral("слишком большой ответ");
    else if (status < 400 && !(interrupted && (status >= 300 || completeJson(status, request.bytes))))
        error = qtError(networkError);
    request.done({status, std::move(request.bytes), std::move(error)});
}

void LyricsHttp::getWithCurl(const QUrl &url, Completion done, const QString &referer)
{
    auto *process = new QProcess(this);
#ifdef Q_OS_WIN
    process->setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *args) {
        args->flags |= CREATE_NO_WINDOW;
    });
#endif
    process->setStandardErrorFile(QProcess::nullDevice());
    m_curlRequests.insert(process, {std::move(done), {}});
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process] {
        auto it = m_curlRequests.find(process);
        if (it == m_curlRequests.end())
            return;
        it->bytes += process->read(responseLimit + curlTrailerLimit + 1 - it->bytes.size());
        if (it->bytes.size() > responseLimit + curlTrailerLimit)
            process->kill();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, url, referer](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            auto request = m_curlRequests.take(process);
            process->deleteLater();
            m_curl.clear();
            if (request.done)
                getWithQt(url, std::move(request.done), referer);
        }
    });
    connect(process, &QProcess::finished, this, [this, process, url, referer](int code, QProcess::ExitStatus status) {
        finishCurl(process, code, status == QProcess::CrashExit, url, referer);
    });
    QTimer::singleShot(16000, process, [process] {
        if (process->state() != QProcess::NotRunning) {
            process->setProperty("lyricsTimedOut", true);
            process->kill();
        }
    });
    // Disable curl's config file. Keep its usual proxy environment and TLS verification.
    QStringList arguments{QStringLiteral("--disable"), QStringLiteral("--silent"),
        QStringLiteral("--globoff"), QStringLiteral("--proto"), u'=' + url.scheme(),
        QStringLiteral("--http1.1"), QStringLiteral("--header"), QStringLiteral("Connection: close"),
        QStringLiteral("--connect-timeout"), QStringLiteral("8"),
        QStringLiteral("--max-time"), QStringLiteral("14"),
        QStringLiteral("--max-filesize"), QString::number(responseLimit),
        QStringLiteral("--user-agent"), QString::fromLatin1(userAgent),
        QStringLiteral("--header"), QStringLiteral("Accept: application/json"),
        QStringLiteral("--write-out"),
        QStringLiteral(R"(\n)") + QString::fromLatin1(curlTrailerPrefix)
            + QStringLiteral("%{http_code} %{http_connect} %{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer}"),
        QStringLiteral("--url"), QString::fromLatin1(url.toEncoded())};
    if (!referer.isEmpty())
        arguments.append({QStringLiteral("--referer"), referer});
    if (!m_proxy.isEmpty())
        arguments.append({QStringLiteral("--proxy"), proxyAddress(), QStringLiteral("--noproxy"), QString()});
    process->start(m_curl, arguments, QIODevice::ReadOnly);
}

void LyricsHttp::finishCurl(QProcess *process, int exitCode, bool crashed, const QUrl &url, const QString &referer)
{
    auto request = m_curlRequests.take(process);
    if (!request.done)
        return;
    process->deleteLater();
    if (request.bytes.size() <= responseLimit + curlTrailerLimit)
        request.bytes += process->read(responseLimit + curlTrailerLimit + 1 - request.bytes.size());

    const auto timing = readTiming(request.bytes);
    const bool timedOut = exitCode == 28 || process->property("lyricsTimedOut").toBool();
    const bool interrupted = timedOut || exitCode == 18 || (exitCode == 56 && timing.status >= 200);
    const bool https = url.scheme() == QStringLiteral("https");
    Result result;
    if (request.bytes.size() > responseLimit + curlTrailerLimit || timing.bodyEnd > responseLimit) {
        result.error = QStringLiteral("слишком большой ответ");
    } else if (timing.status == 0 && timing.proxyStatus >= 300) {
        result.error = QStringLiteral("прокси HTTP %1 (curl %2)").arg(timing.proxyStatus).arg(exitCode);
    } else if (interrupted) {
        if (timing.bodyEnd >= 0)
            request.bytes.truncate(timing.bodyEnd);
        if (timing.status >= 300 || completeJson(timing.status, request.bytes)) {
            request.done({timing.status, std::move(request.bytes), {}});
            return;
        }
        result.error = interruptedTransfer(timedOut ? 28 : exitCode, timing, https);
        if (!https || QSslSocket::supportsSsl()) {
            getWithQt(url, [done = std::move(request.done), initialError = std::move(result.error)](Result fallback) {
                if (!fallback.error.isEmpty())
                    fallback.error = initialError + QStringLiteral(" / ") + fallback.error;
                done(std::move(fallback));
            }, referer);
            return;
        }
    } else if (crashed) {
        result.error = QStringLiteral("curl завершился аварийно");
    } else if (exitCode == 7 && !m_proxy.isEmpty()) {
        result.error = QStringLiteral("не удалось подключиться к локальному прокси (curl 7)");
    } else if (exitCode != 0) {
        result.error = curlError(exitCode);
    } else if (timing.bodyEnd >= 0 && timing.status > 0) {
        result.status = timing.status;
        request.bytes.truncate(timing.bodyEnd);
        result.body = std::move(request.bytes);
    } else {
        result.error = QStringLiteral("нет HTTP-ответа (curl)");
    }
    request.done(std::move(result));
}
