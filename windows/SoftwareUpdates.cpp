#include "SoftwareUpdates.h"
#include "UpdateInstaller.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QTemporaryDir>
#include <QTimer>
#include <QUrlQuery>
#include <QDir>

#include <utility>

using namespace Qt::StringLiterals;

namespace {

const auto releaseChannel = u"release"_s;
const auto previewChannel = u"prerelease"_s;
const auto channelKey = u"updates/channel"_s;
const auto automaticKey = u"updates/automatic"_s;
const auto attemptKey = u"updates/attemptedTag"_s;
const auto api = u"https://api.github.com/repos/Aferon-08/dock-equalizer-windows/releases"_s;
constexpr int pageSize = 30;
constexpr qsizetype metadataLimit = 2 * 1024 * 1024;

bool allowDownloadRedirect(const QUrl &url)
{
    const auto host = url.host();
    return url.scheme() == u"https"_s && url.port(443) == 443 && url.userInfo().isEmpty()
        && (host == u"github.com"_s || host == u"release-assets.githubusercontent.com"_s
            || host == u"objects.githubusercontent.com"_s || host == u"github-releases.githubusercontent.com"_s);
}

} // namespace

SoftwareUpdates::SoftwareUpdates(QSettings &settings, QString version, bool enabled)
    : m_settings(settings)
    , m_version(std::move(version))
    , m_enabled(enabled)
    , m_installRoot(enabled ? UpdateInstaller::installedRoot(QCoreApplication::applicationFilePath()) : QString())
    , m_channel(settings.value(channelKey, m_version.contains(u'-') ? previewChannel : releaseChannel).toString())
    , m_automatic(settings.value(automaticKey, true).toBool())
{
    if (m_channel != previewChannel)
        m_channel = releaseChannel;
    m_status = m_enabled ? tr("Обновления проверяются при запуске программы.")
                         : tr("Проверка обновлений доступна в версии для Windows.");
    const auto attempt = m_settings.value(attemptKey).toString();
    if (!m_installRoot.isEmpty() && !attempt.isEmpty() && UpdateRelease::compareVersions(m_version, attempt) >= 0)
        m_settings.remove(attemptKey);
}

SoftwareUpdates::~SoftwareUpdates()
{
    shutdown();
}

void SoftwareUpdates::setChannel(const QString &channel)
{
    if (!m_enabled || m_stopping || installing() || channel == m_channel
            || (channel != releaseChannel && channel != previewChannel))
        return;
    cancelRequest();
    m_operation = Operation::Idle;
    m_release.reset();
    m_announcedTag.clear();
    m_channel = channel;
    m_settings.setValue(channelKey, channel);
    check();
}

void SoftwareUpdates::setAutomatic(bool automatic)
{
    if (!m_enabled || m_stopping || installing() || automatic == m_automatic)
        return;
    m_automatic = automatic;
    m_settings.setValue(automaticKey, automatic);
    if (!automatic && m_operation == Operation::Downloading && m_automaticDownload) {
        cancelRequest();
        setStatus(tr("Доступно обновление %1.").arg(updateVersion()));
        announce();
    } else {
        emit changed();
        if (automatic && !busy() && canInstall() && m_settings.value(attemptKey).toString() != m_release->tag)
            startDownload(true);
    }
}

void SoftwareUpdates::check()
{
    if (!m_enabled || m_stopping || busy())
        return;
    m_release.reset();
    setStatus(tr("Проверяем обновления…"), Operation::Checking);
    checkPage(1);
}

void SoftwareUpdates::checkPage(int page)
{
    m_page = page;
    if (m_channel == releaseChannel) {
        startRequest(QUrl(api + u"/latest"_s));
    } else {
        QUrl url(api);
        QUrlQuery query;
        query.addQueryItem(u"per_page"_s, QString::number(pageSize));
        query.addQueryItem(u"page"_s, QString::number(page));
        url.setQuery(query);
        startRequest(url);
    }
}

void SoftwareUpdates::startRequest(const QUrl &url)
{
    const bool download = m_operation == Operation::Downloading;
    QNetworkRequest request(url);
    request.setRawHeader("User-Agent", "SekaiSoundbar/" + m_version.toLatin1());
    request.setRawHeader("Accept", download ? "application/octet-stream" : "application/vnd.github+json");
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
        download ? QNetworkRequest::UserVerifiedRedirectPolicy : QNetworkRequest::SameOriginRedirectPolicy);
    request.setMaximumRedirectsAllowed(4);
    request.setTransferTimeout(download ? 25000 : 10000);
    m_reply = m_network.get(request);
    m_reply->setReadBufferSize(128 * 1024);
    if (download) {
        connect(m_reply, &QNetworkReply::redirected, this, [this](const QUrl &url) {
            if (allowDownloadRedirect(url))
                emit m_reply->redirectAllowed();
            else
                fail(tr("GitHub перенаправил загрузку на неподдерживаемый адрес."));
        });
    }
    connect(m_reply, &QNetworkReply::readyRead, this, &SoftwareUpdates::readReply);
    connect(m_reply, &QNetworkReply::finished, this, &SoftwareUpdates::finishReply);
    QTimer::singleShot(download ? 300000 : 15000, m_reply, [reply = m_reply] {
        if (!reply->isFinished())
            reply->abort();
    });
}

void SoftwareUpdates::readReply()
{
    const auto data = m_reply->readAll();
    if (m_reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() != 200)
        return;
    if (m_operation == Operation::Checking) {
        if (m_response.size() + data.size() > metadataLimit) {
            fail(tr("GitHub вернул слишком большой список выпусков."));
            return;
        }
        m_response += data;
        return;
    }

    if (m_file.size() + data.size() > m_release->size || m_file.write(data) != data.size()) {
        fail(tr("Не удалось сохранить установщик или его размер не совпадает с указанным."));
        return;
    }
    m_hash.addData(data);
    const auto progress = int(m_file.size() * 100 / m_release->size);
    if (progress != m_progress) {
        m_progress = progress;
        setStatus(tr("Загрузка версии %1 · %2 %").arg(updateVersion()).arg(progress), Operation::Downloading);
    }
}

void SoftwareUpdates::finishReply()
{
    auto *reply = m_reply;
    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (reply->error() != QNetworkReply::NoError || httpStatus != 200) {
        if (m_operation == Operation::Checking && httpStatus == 404 && m_channel == releaseChannel) {
            cancelRequest();
            acceptRelease(std::nullopt);
        } else {
            fail(httpStatus >= 400 ? tr("GitHub вернул ошибку HTTP %1.").arg(httpStatus)
                : tr("Не удалось получить обновления от GitHub. Проверьте подключение к сети."));
        }
        return;
    }

    if (reply->bytesAvailable())
        readReply();
    if (m_reply != reply)
        return;
    m_reply = nullptr;
    const bool nextPage = reply->rawHeader("Link").contains("rel=\"next\"");
    reply->deleteLater();

    if (m_operation == Operation::Downloading) {
        finishDownload();
        return;
    }

    const auto json = QJsonDocument::fromJson(std::exchange(m_response, {}));
    const bool prerelease = m_channel == previewChannel;
    if ((prerelease && !json.isArray()) || (!prerelease && !json.isObject())) {
        fail(tr("GitHub вернул некорректный список выпусков."));
        return;
    }
    auto release = UpdateRelease::newest(prerelease ? json.array() : QJsonArray{json.object()}, prerelease);
    if (!release && prerelease && nextPage) {
        checkPage(m_page + 1);
        return;
    }
    acceptRelease(std::move(release));
}

void SoftwareUpdates::acceptRelease(std::optional<UpdateRelease> release)
{
    if (!release) {
        setStatus(tr("В выбранном канале пока нет выпусков."));
        return;
    }
    if (UpdateRelease::compareVersions(release->tag, m_version) <= 0) {
        setStatus(tr("Для этого канала установлена актуальная версия."));
        return;
    }

    m_release = std::move(release);
    const auto tag = m_release->tag;
    if (m_automatic && canInstall() && m_settings.value(attemptKey).toString() != tag) {
        startDownload(true);
        return;
    }
    if (m_settings.value(attemptKey).toString() == tag)
        setStatus(tr("Предыдущая установка версии %1 не завершилась. Можно повторить её вручную.").arg(updateVersion()));
    else if (m_installRoot.isEmpty())
        setStatus(tr("Доступна версия %1. Откройте страницу выпуска, чтобы скачать установщик.").arg(updateVersion()));
    else if (!m_release->hasInstaller())
        setStatus(tr("Доступна версия %1. Проверенный установщик пока недоступен.").arg(updateVersion()));
    else
        setStatus(tr("Доступно обновление %1.").arg(updateVersion()));
    announce();
}

void SoftwareUpdates::install()
{
    if (!m_stopping && !busy() && canInstall())
        startDownload(false);
}

void SoftwareUpdates::startDownload(bool automatic)
{
    m_staging = std::make_unique<QTemporaryDir>(QDir::temp().filePath(u"sekai-update-XXXXXX"_s));
    m_file.setFileName(m_staging->filePath(u"SekaiSoundbar-Setup.exe"_s));
    if (!m_staging->isValid() || !m_file.open(QIODevice::WriteOnly)) {
        fail(tr("Не удалось создать папку для загрузки установщика."));
        return;
    }
    m_hash.reset();
    m_progress = -1;
    m_automaticDownload = automatic;
    setStatus(tr("Загружаем версию %1…").arg(updateVersion()), Operation::Downloading);
    startRequest(m_release->installer);
}

void SoftwareUpdates::finishDownload()
{
    const auto size = m_file.size();
    const auto installer = m_file.fileName();
    const bool written = m_file.flush();
    m_file.close();
    if (!written || size != m_release->size || m_hash.result() != m_release->sha256) {
        fail(tr("Контрольная сумма установщика не совпала. Установка отменена."));
        return;
    }
    if (!UpdateInstaller::verifyPublisher(installer)) {
        fail(tr("Не удалось подтвердить подпись Sekai Soundbar. Установка отменена."));
        return;
    }

    const auto attempt = m_settings.value(attemptKey);
    m_settings.setValue(attemptKey, m_release->tag);
    m_settings.sync();
    if (m_settings.status() != QSettings::NoError || !UpdateInstaller::start(installer, m_release->sha256, m_installRoot)) {
        m_settings.setValue(attemptKey, attempt);
        fail(tr("Не удалось запустить установку. Попробуйте ещё раз или скачайте установщик со страницы выпуска."));
        return;
    }
    m_staging->setAutoRemove(false);
    setStatus(tr("Закрываем док для установки версии %1…").arg(updateVersion()), Operation::Launching);
    emit installationStarted();
}

void SoftwareUpdates::openRelease() const
{
    if (m_release)
        QDesktopServices::openUrl(m_release->page);
}

void SoftwareUpdates::cancelRequest()
{
    if (auto *reply = std::exchange(m_reply, nullptr)) {
        reply->disconnect(this);
        reply->abort();
        reply->deleteLater();
    }
    m_response.clear();
    m_file.close();
    m_staging.reset();
}

void SoftwareUpdates::shutdown()
{
    m_stopping = true;
    cancelRequest();
}

void SoftwareUpdates::fail(const QString &error)
{
    cancelRequest();
    setStatus(error);
    announce();
}

void SoftwareUpdates::setStatus(const QString &status, Operation operation)
{
    m_status = status;
    m_operation = operation;
    emit changed();
}

void SoftwareUpdates::announce()
{
    if (m_release && m_announcedTag != m_release->tag) {
        m_announcedTag = m_release->tag;
        emit updateAvailable(updateVersion());
    }
}
