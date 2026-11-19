#include "LyricsHttp.h"

#include <QDir>
#include <QFileInfo>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QSslSocket>
#include <QTimer>

#ifdef Q_OS_WIN
#include <QtCore/qt_windows.h>
#endif

#include <utility>

namespace {

constexpr qsizetype responseLimit = 2 * 1024 * 1024;
constexpr qsizetype curlTrailer = 4; // A newline followed by the three-digit HTTP status.
constexpr auto userAgent = "SekaiSoundbar (https://github.com/Aferon-08/sekaipop-dock-equalizer-windows)";

QString curlError(int code)
{
    QString reason;
    switch (code) {
    case 5:
    case 97: reason = QStringLiteral("ошибка прокси"); break;
    case 6: reason = QStringLiteral("DNS не нашёл сервер"); break;
    case 7: reason = QStringLiteral("не удалось подключиться"); break;
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

void LyricsHttp::get(const QUrl &url, Completion done)
{
    if (m_curl.isEmpty())
        getWithQt(url, std::move(done));
    else
        getWithCurl(url, std::move(done));
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

void LyricsHttp::getWithQt(const QUrl &url, Completion done)
{
    if (url.scheme() == QStringLiteral("https") && !QSslSocket::supportsSsl()) {
        done({0, {}, QStringLiteral("HTTPS недоступен. Распакуйте ZIP целиком.")});
        return;
    }

    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", userAgent);
    request.setRawHeader("Accept", "application/json");
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
    auto error = request.bytes.size() > responseLimit ? QStringLiteral("слишком большой ответ")
        : status >= 400 ? QString{} : qtError(reply->error());
    request.done({status, std::move(request.bytes), std::move(error)});
}

void LyricsHttp::getWithCurl(const QUrl &url, Completion done)
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
        it->bytes += process->read(responseLimit + curlTrailer + 1 - it->bytes.size());
        if (it->bytes.size() > responseLimit + curlTrailer)
            process->kill();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, url](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            auto request = m_curlRequests.take(process);
            process->deleteLater();
            m_curl.clear();
            if (request.done)
                getWithQt(url, std::move(request.done));
        }
    });
    connect(process, &QProcess::finished, this, [this, process](int code, QProcess::ExitStatus status) {
        finishCurl(process, code, status == QProcess::CrashExit);
    });
    QTimer::singleShot(16000, process, [process] {
        if (process->state() != QProcess::NotRunning) {
            process->setProperty("lyricsTimedOut", true);
            process->kill();
        }
    });
    // Disable curl's config file. Keep its usual proxy environment and TLS verification.
    process->start(m_curl, {QStringLiteral("--disable"), QStringLiteral("--silent"),
        QStringLiteral("--globoff"), QStringLiteral("--proto"), u'=' + url.scheme(),
        QStringLiteral("--connect-timeout"), QStringLiteral("8"),
        QStringLiteral("--max-time"), QStringLiteral("14"),
        QStringLiteral("--max-filesize"), QString::number(responseLimit),
        QStringLiteral("--user-agent"), QString::fromLatin1(userAgent),
        QStringLiteral("--header"), QStringLiteral("Accept: application/json"),
        QStringLiteral("--write-out"), QStringLiteral(R"(\n%{http_code})"),
        QStringLiteral("--url"), QString::fromLatin1(url.toEncoded())}, QIODevice::ReadOnly);
}

void LyricsHttp::finishCurl(QProcess *process, int exitCode, bool crashed)
{
    auto request = m_curlRequests.take(process);
    if (!request.done)
        return;
    process->deleteLater();
    if (request.bytes.size() <= responseLimit + curlTrailer)
        request.bytes += process->read(responseLimit + curlTrailer + 1 - request.bytes.size());

    Result result;
    if (request.bytes.size() > responseLimit + curlTrailer) {
        result.error = QStringLiteral("слишком большой ответ");
    } else if (process->property("lyricsTimedOut").toBool()) {
        result.error = curlError(28);
    } else if (crashed) {
        result.error = QStringLiteral("curl завершился аварийно");
    } else if (exitCode != 0) {
        result.error = curlError(exitCode);
    } else if (request.bytes.size() >= curlTrailer
            && request.bytes.at(request.bytes.size() - curlTrailer) == '\n') {
        result.status = request.bytes.right(3).toInt();
        request.bytes.chop(curlTrailer);
        result.body = std::move(request.bytes);
    } else {
        result.error = QStringLiteral("нет HTTP-ответа (curl)");
    }
    request.done(std::move(result));
}
