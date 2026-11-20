#include "StartupSettings.h"

#include <QCoreApplication>
#include <QDir>
#include <QSettings>

namespace {

#ifdef Q_OS_WIN
const auto runKey = QStringLiteral(R"(HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run)");
const auto entry = QStringLiteral("SekaiSoundbar");
#endif

} // namespace

StartupSettings::StartupSettings(bool writable)
    : m_available(
#ifdef Q_OS_WIN
        writable
#else
        false
#endif
    )
    , m_command(u'"' + QDir::toNativeSeparators(QCoreApplication::applicationFilePath()) + u'"')
{
    Q_UNUSED(writable);
    refresh();
}

void StartupSettings::refresh()
{
#ifdef Q_OS_WIN
    if (m_available) {
        const QSettings run(runKey, QSettings::Registry64Format);
        m_registeredCommand = run.value(entry).toString();
    }
#endif
    emit changed();
}

void StartupSettings::setEnabled(bool enabled)
{
#ifdef Q_OS_WIN
    if (m_available) {
        QSettings run(runKey, QSettings::Registry64Format);
        if (enabled)
            run.setValue(entry, m_command);
        else
            run.remove(entry);
        run.sync();
        m_error = run.status() == QSettings::NoError ? QString{} : tr("Не удалось изменить автозапуск в Windows.");
        refresh();
    }
#else
    Q_UNUSED(enabled);
#endif
}
