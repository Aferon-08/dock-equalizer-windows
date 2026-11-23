#include "UpdateInstaller.h"

#ifdef Q_OS_WIN
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QSettings>

#include <QtCore/qt_windows.h>
#include <softpub.h>
#include <wincrypt.h>
#include <wintrust.h>

namespace {

bool matchesPublisher(PCCERT_CONTEXT certificate)
{
    if (!certificate)
        return false;
    // SHA-256 of the release publisher's DER SubjectPublicKeyInfo.
    constexpr auto publisher = "09df8bfac9a5e66b935f2134eb337138b86b42d6aa2c85248e642c08ba213652";
    BYTE *encoded = nullptr;
    DWORD size = 0;
    if (!CryptEncodeObjectEx(X509_ASN_ENCODING, X509_PUBLIC_KEY_INFO,
            &certificate->pCertInfo->SubjectPublicKeyInfo, CRYPT_ENCODE_ALLOC_FLAG, nullptr, &encoded, &size))
        return false;
    const auto digest = QCryptographicHash::hash(QByteArrayView(
        reinterpret_cast<const char *>(encoded), size), QCryptographicHash::Sha256).toHex();
    LocalFree(encoded);
    return digest == publisher;
}

} // namespace
#endif

QString UpdateInstaller::installedRoot(const QString &executable)
{
#ifdef Q_OS_WIN
    const QSettings registration(QStringLiteral(
        R"(HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Uninstall\SekaiSoundbar)"),
        QSettings::Registry64Format);
    const auto location = registration.value(QStringLiteral("InstallLocation")).toString();
    const auto runtime = registration.value(QStringLiteral("RuntimeFolder"), QStringLiteral("app")).toString();
    if (!QDir::isAbsolutePath(location)
            || (runtime != QStringLiteral("app") && runtime != QStringLiteral("app-update")))
        return {};
    const auto root = QDir(location).canonicalPath();
    if (root.isEmpty())
        return {};
    const auto registered = QFileInfo(QDir(root).filePath(runtime + QStringLiteral("/SekaiSoundbar.exe"))).canonicalFilePath();
    if (!registered.isEmpty() && QFileInfo(executable).canonicalFilePath().compare(registered, Qt::CaseInsensitive) == 0)
        return location;
#else
    Q_UNUSED(executable);
#endif
    return {};
}

bool UpdateInstaller::verifyPublisher(const QString &installer)
{
#ifdef Q_OS_WIN
    const auto filename = QDir::toNativeSeparators(installer).toStdWString();
    WINTRUST_FILE_INFO file{};
    file.cbStruct = sizeof(file);
    file.pcwszFilePath = filename.c_str();

    WINTRUST_DATA trust{};
    trust.cbStruct = sizeof(trust);
    trust.dwUIChoice = WTD_UI_NONE;
    trust.fdwRevocationChecks = WTD_REVOKE_NONE;
    trust.dwUnionChoice = WTD_CHOICE_FILE;
    trust.pFile = &file;
    trust.dwStateAction = WTD_STATEACTION_VERIFY;
    trust.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;
    GUID policy = WINTRUST_ACTION_GENERIC_VERIFY_V2;
    const auto status = WinVerifyTrust(nullptr, &policy, &trust);
    auto *provider = trust.hWVTStateData ? WTHelperProvDataFromStateData(trust.hWVTStateData) : nullptr;
    const auto *signer = provider ? WTHelperGetProvSignerFromChain(provider, 0, FALSE, 0) : nullptr;
    const auto certificate = signer && signer->csCertChain ? signer->pasCertChain[0].pCert : nullptr;
    // The pinned publisher is its own root. Accept that root policy error only
    // after Authenticode has validated both the PE digest and the signature.
    const bool pinnedRoot = status == CERT_E_UNTRUSTEDROOT && provider && provider->padwTrustStepErrors
        && provider->cdwTrustStepErrors > TRUSTERROR_STEP_FINAL_SIGPROV
        && provider->padwTrustStepErrors[TRUSTERROR_STEP_FINAL_OBJPROV] == ERROR_SUCCESS
        && provider->padwTrustStepErrors[TRUSTERROR_STEP_FINAL_SIGPROV] == ERROR_SUCCESS
        && certificate && CertVerifyTimeValidity(nullptr, certificate->pCertInfo) == 0;
    const bool verified = (status == ERROR_SUCCESS || pinnedRoot) && matchesPublisher(certificate);
    trust.dwStateAction = WTD_STATEACTION_CLOSE;
    WinVerifyTrust(nullptr, &policy, &trust);
    return verified;
#else
    Q_UNUSED(installer);
    return false;
#endif
}

bool UpdateInstaller::start(const QString &installer, const QByteArray &sha256, const QString &installRoot)
{
#ifdef Q_OS_WIN
    QFile script(QStringLiteral(":/sekai-update/ApplyUpdate.ps1"));
    if (!script.open(QIODevice::ReadOnly))
        return false;
    const auto code = QString::fromUtf8(script.readAll());
    const auto encoded = QByteArray(reinterpret_cast<const char *>(code.utf16()), code.size() * 2).toBase64();

    wchar_t system[MAX_PATH + 1]{};
    const auto length = GetSystemDirectoryW(system, MAX_PATH + 1);
    if (!length || length > MAX_PATH)
        return false;
    const auto powershell = QDir(QString::fromWCharArray(system, length))
        .filePath(QStringLiteral("WindowsPowerShell/v1.0/powershell.exe"));

    FILETIME created{}, exited{}, kernel{}, user{};
    if (!GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user))
        return false;
    const auto startedAt = (quint64(created.dwHighDateTime) << 32) | created.dwLowDateTime;
    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("SEKAI_UPDATE_PROCESS"), QString::number(QCoreApplication::applicationPid()));
    environment.insert(QStringLiteral("SEKAI_UPDATE_STARTED"), QString::number(startedAt));
    environment.insert(QStringLiteral("SEKAI_UPDATE_ROOT"), QDir::toNativeSeparators(installRoot));
    environment.insert(QStringLiteral("SEKAI_UPDATE_SETUP"), QDir::toNativeSeparators(installer));
    environment.insert(QStringLiteral("SEKAI_UPDATE_SHA256"), QString::fromLatin1(sha256.toHex()));

    QProcess helper;
    helper.setProgram(powershell);
    helper.setArguments({QStringLiteral("-NoLogo"), QStringLiteral("-NoProfile"), QStringLiteral("-NonInteractive"),
        QStringLiteral("-WindowStyle"), QStringLiteral("Hidden"), QStringLiteral("-EncodedCommand"), QString::fromLatin1(encoded)});
    helper.setProcessEnvironment(environment);
    helper.setWorkingDirectory(QDir::tempPath());
    helper.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *arguments) {
        arguments->flags |= CREATE_NO_WINDOW;
    });
    return helper.startDetached();
#else
    Q_UNUSED(installer);
    Q_UNUSED(sha256);
    Q_UNUSED(installRoot);
    return false;
#endif
}
