#include "WindowsNotificationBanners.h"

#include <QCoreApplication>
#include <QDebug>
#include <QSettings>
#include <QTemporaryDir>
#include <QUuid>

namespace {

bool expect(bool condition, const char *message)
{
    if (!condition)
        qCritical("%s", message);
    return condition;
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir temporary;
    if (!temporary.isValid())
        return 1;
    const auto path = QStringLiteral("Software\\SekaiSoundbar\\BannerTest-") + QUuid::createUuid().toString(QUuid::WithoutBraces);
    QSettings registry(QStringLiteral("HKEY_CURRENT_USER\\") + path, QSettings::NativeFormat);
    const auto snipping = QStringLiteral("Microsoft.ScreenSketch_8wekyb3d8bbwe!App/");
    const auto disabled = QStringLiteral("Disabled.App/ShowBanner");
    const auto manual = QStringLiteral("Manual.App/ShowBanner");
    const auto newSender = QStringLiteral("New.App!App");
    const auto alarm = QStringLiteral("Microsoft.WindowsAlarms_8wekyb3d8bbwe!App/ShowBanner");
    const auto system = QStringLiteral("Windows.SystemToast.SecurityAndMaintenance/ShowBanner");
    const auto journal = temporary.filePath(QStringLiteral("banners.ini"));
    registry.setValue(snipping + QStringLiteral("ShowBanner"), 1);
    registry.setValue(snipping + QStringLiteral("Enabled"), 1);
    registry.setValue(snipping + QStringLiteral("ShowInActionCenter"), 1);
    registry.setValue(disabled, 0);
    registry.setValue(QStringLiteral("Manual.App/Enabled"), 1);
    registry.setValue(alarm, 1);
    registry.setValue(system, 1);
    registry.sync();

    bool ok = true;
    {
        QSettings settings(journal, QSettings::IniFormat);
        WindowsNotificationBanners banners(settings, path);
        const auto result = banners.suppress({newSender});
        ok &= expect(banners.available() && result.complete && result.hidden == 4, "Expected four app banner settings");
        ok &= expect(registry.value(snipping + QStringLiteral("ShowBanner")).toInt() == 0, "Snipping Tool banner must be disabled");
        ok &= expect(registry.value(snipping + QStringLiteral("Enabled")).toInt() == 1
            && registry.value(snipping + QStringLiteral("ShowInActionCenter")).toInt() == 1,
            "Notification delivery and the notification center must stay enabled");
        ok &= expect(registry.value(newSender + QStringLiteral("/ShowBanner"), -1).toInt() == 0,
            "A sender learned from the notification center needs a banner setting");
        ok &= expect(registry.value(alarm).toInt() == 1 && registry.value(system).toInt() == 1,
            "Alarms and system warnings must keep their original banner settings");

        registry.setValue(manual, 1);
        banners.suppress({newSender});
        ok &= expect(registry.value(manual).toInt() == 1, "A manual change must take precedence during the current session");
    }
    {
        QSettings settings(journal, QSettings::IniFormat);
        WindowsNotificationBanners banners(settings, path);
        ok &= expect(banners.restore(), "A new process must be able to recover the previous settings");
        ok &= expect(registry.value(snipping + QStringLiteral("ShowBanner")).toInt() == 1,
            "The explicit Snipping Tool setting must be restored");
        ok &= expect(!registry.contains(newSender + QStringLiteral("/ShowBanner")), "An absent banner setting must be removed");
        ok &= expect(registry.value(disabled, -1).toInt() == 0 && registry.value(manual, -1).toInt() == 1,
            "Pre-existing suppression and a later manual edit must be preserved");
        ok &= expect(!settings.contains(QStringLiteral("notifications/bannerBackup")), "Successful restoration must clear the journal");
    }
    registry.clear();
    registry.sync();
    return ok ? 0 : 1;
}
