#include "UpdateInstaller.h"
#include "UpdateRelease.h"

#include <QCoreApplication>
#include <QFile>
#include <QJsonObject>
#include <QTemporaryDir>

#include <cstdlib>

namespace {

void check(bool condition, const char *message)
{
    if (!condition)
        qFatal("%s", message);
}

QJsonObject release(const QString &tag, bool preview, const QJsonArray &assets = {})
{
    return {{QStringLiteral("tag_name"), tag}, {QStringLiteral("prerelease"), preview},
        {QStringLiteral("draft"), false}, {QStringLiteral("published_at"), QStringLiteral("2026-11-23T13:00:00Z")},
        {QStringLiteral("assets"), assets}};
}

QJsonObject asset(const QString &name, qint64 size, const QString &digest)
{
    return {{QStringLiteral("name"), name}, {QStringLiteral("size"), size}, {QStringLiteral("digest"), digest},
        {QStringLiteral("state"), QStringLiteral("uploaded")},
        {QStringLiteral("browser_download_url"), QStringLiteral("https://other.example/installer.exe")}};
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    check(UpdateRelease::compareVersions(QStringLiteral("v1.3"), QStringLiteral("1.3.0")) == 0,
        "a patch-zero tag must compare equal to the short version");
    check(UpdateRelease::compareVersions(QStringLiteral("v1.4.0"), QStringLiteral("1.4.0-preview")) > 0,
        "a stable version must follow its prereleases");
    check(UpdateRelease::compareVersions(QStringLiteral("v1.4.0-preview.12"), QStringLiteral("v1.4.0-preview.2")) > 0,
        "numeric prerelease identifiers must be ordered numerically");
    check(UpdateRelease::compareVersions(QStringLiteral("v1.3.0"), QStringLiteral("1.4.0-preview")) < 0,
        "switching to the stable channel must not downgrade the installed app");

    const auto digest = QStringLiteral("sha256:") + QString(64, u'a');
    const QJsonArray assets{
        asset(QStringLiteral("SekaiSoundbar-1.4.0-Windows11-x64-Preview-Setup.exe"), 37700000, digest),
        asset(QStringLiteral("SekaiSoundbar-Windows11-x86-Setup.exe"), 9000, digest)
    };
    auto draft = release(QStringLiteral("v2.0.0-preview"), true, assets);
    draft.insert(QStringLiteral("draft"), true);
    auto unpublished = release(QStringLiteral("v2.1.0-preview"), true, assets);
    unpublished.remove(QStringLiteral("published_at"));
    const QJsonArray releases{
        draft, unpublished, release(QStringLiteral("v4.0.0-preview/extra"), true),
        release(QStringLiteral("v1.2.3-preview"), true), release(QStringLiteral("v1.4.0-preview"), true, assets),
        release(QStringLiteral("v1.3.0"), false),
        release(QStringLiteral("v1.3.0-preview"), false)
    };

    const auto preview = UpdateRelease::newest(releases, true);
    const auto stable = UpdateRelease::newest(releases, false);
    check(preview && preview->tag == QStringLiteral("v1.4.0-preview"), "the preview channel must ignore drafts");
    check(stable && stable->tag == QStringLiteral("v1.3.0"), "the stable channel must ignore prereleases");
    check(preview->hasInstaller() && preview->size == 37700000 && preview->sha256.size() == 32,
        "the x64 installer must have a valid SHA-256 and size");
    check(preview->installer.host() == QStringLiteral("github.com")
            && preview->installer.path().contains(QStringLiteral("/Aferon-08/dock-equalizer-windows/releases/download/")),
        "installer URLs must originate from the official repository");
    check(!stable->hasInstaller() && stable->page.host() == QStringLiteral("github.com"),
        "a release without a verified installer can still be opened in the browser");
    const auto invalid = UpdateRelease::newest({release(QStringLiteral("v1.4.0"), false,
        {asset(QStringLiteral("SekaiSoundbar-Windows11-x64-Setup.exe"), 512ll * 1024 * 1024 + 1, digest),
         asset(QStringLiteral("SekaiSoundbar-1.4.0-Windows11-x64-Setup.exe"), 100, QStringLiteral("sha256:bad"))})}, false);
    check(invalid && !invalid->hasInstaller(), "invalid checksums and oversized downloads must be rejected");

#ifdef Q_OS_WIN
    if (app.arguments().size() == 2) {
        const auto installer = app.arguments().at(1);
        check(UpdateInstaller::verifyPublisher(installer), "the signed release installer must pass publisher verification");
        QTemporaryDir directory;
        check(directory.isValid(), "cannot make temporary directory");
        const auto tampered = directory.filePath(QStringLiteral("modified.exe"));
        check(QFile::copy(installer, tampered), "cannot copy the test installer");
        QFile file(tampered);
        check(file.open(QIODevice::ReadWrite) && file.seek(64), "cannot open the test installer");
        char byte = 0;
        check(file.read(&byte, 1) == 1 && file.seek(64), "cannot read the test installer");
        byte ^= 1;
        check(file.write(&byte, 1) == 1 && file.flush(), "cannot change the test installer");
        file.close();
        check(!UpdateInstaller::verifyPublisher(tampered), "a modified installer must fail signature verification");
    }
#endif
    return EXIT_SUCCESS;
}
