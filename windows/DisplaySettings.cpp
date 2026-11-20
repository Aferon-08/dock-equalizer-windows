#include "DisplaySettings.h"

#include <QGuiApplication>
#include <QSettings>
#include <QSize>

#include <algorithm>
#include <utility>

#ifdef Q_OS_WIN
#include <QtCore/qt_windows.h>
#endif

namespace {

const auto settingsKey = QStringLiteral("displays/preference");

struct DisplayIdentity {
    QString id;
    QSize resolution;
    int number;
};

DisplayIdentity identify(QScreen *screen, int number)
{
#ifdef Q_OS_WIN
    const auto *native = screen->nativeInterface<QNativeInterface::QWindowsScreen>();
    MONITORINFOEXW info{};
    info.cbSize = sizeof(info);
    if (native && GetMonitorInfoW(native->handle(), reinterpret_cast<MONITORINFO *>(&info))) {
        const auto device = QString::fromWCharArray(info.szDevice);
        const auto suffix = device.lastIndexOf(QStringLiteral("DISPLAY"), -1, Qt::CaseInsensitive);
        bool numbered = false;
        const int deviceNumber = suffix >= 0 ? device.mid(suffix + 7).toInt(&numbered) : 0;
        const auto &rect = info.rcMonitor;
        const QSize resolution(rect.right - rect.left, rect.bottom - rect.top);

        // The monitor interface path distinguishes identical displays and
        // survives rearranging the desktop or changing its primary screen.
        DISPLAY_DEVICEW monitor{};
        monitor.cb = sizeof(monitor);
        QString id = device;
        if (EnumDisplayDevicesW(info.szDevice, 0, &monitor, EDD_GET_DEVICE_INTERFACE_NAME) && monitor.DeviceID[0])
            id = QString::fromWCharArray(monitor.DeviceID);
        return {id.toLower(), resolution, numbered && deviceNumber > 0 ? deviceNumber : number};
    }
#endif
    const auto name = screen->name();
    const auto id = name.isEmpty() ? QString::number(number) : name;
    return {id, screen->size() * screen->devicePixelRatio(), number};
}

} // namespace

DisplaySettings::DisplaySettings(QSettings *settings)
    : m_settings(settings)
    , m_preferences(settings ? settings->value(settingsKey).toMap() : QVariantMap{})
{
    for (auto *screen : QGuiApplication::screens())
        watch(screen);
    connect(qGuiApp, &QGuiApplication::screenAdded, this, [this](QScreen *screen) {
        watch(screen);
        refresh();
    });
    connect(qGuiApp, &QGuiApplication::screenRemoved, this, &DisplaySettings::refresh);
    connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this, &DisplaySettings::refresh);
    refresh();
}

void DisplaySettings::watch(QScreen *screen)
{
    connect(screen, &QScreen::geometryChanged, this, &DisplaySettings::refresh);
    connect(screen, &QScreen::logicalDotsPerInchChanged, this, &DisplaySettings::refresh);
}

void DisplaySettings::refresh()
{
    const auto previous = enabledScreens();
    QList<Display> displays;
    const auto *primary = QGuiApplication::primaryScreen();
    int number = 0;
    for (auto *screen : QGuiApplication::screens()) {
        const auto identity = identify(screen, ++number);
        const auto model = screen->model().trimmed();
        auto name = tr("Монитор %1").arg(identity.number);
        if (!model.isEmpty())
            name += QStringLiteral(" · ") + model;
        auto details = tr("%1 × %2").arg(identity.resolution.width()).arg(identity.resolution.height());
        if (screen == primary)
            details += QStringLiteral(" · ") + tr("Основной");
        const auto enabled = m_preferences.isEmpty() ? screen == primary
            : m_preferences.value(identity.id, false).toBool();
        displays.append({screen, identity.id, name, details, identity.number, enabled});
    }
    std::stable_sort(displays.begin(), displays.end(), [](const Display &first, const Display &second) {
        return first.number < second.number;
    });

    beginResetModel();
    m_displays = std::move(displays);
    endResetModel();
    emit displaysChanged();
    if (previous != enabledScreens())
        emit enabledScreensChanged();
}

QList<QScreen *> DisplaySettings::enabledScreens() const
{
    QList<QScreen *> screens;
    for (const auto &display : m_displays) {
        if (display.enabled && display.screen)
            screens.append(display.screen);
    }
    return screens;
}

void DisplaySettings::setDockEnabled(const QString &id, bool enabled)
{
    for (int row = 0; row < count(); ++row) {
        auto &display = m_displays[row];
        if (display.id != id || !display.screen)
            continue;
        if (display.enabled == enabled)
            return;
        if (m_preferences.isEmpty()) {
            for (const auto &connected : std::as_const(m_displays))
                m_preferences.insert(connected.id, connected.enabled);
        }
        display.enabled = enabled;
        m_preferences.insert(id, enabled);
        if (m_settings)
            m_settings->setValue(settingsKey, m_preferences);
        emit dataChanged(index(row), index(row), {DockEnabled});
        emit enabledScreensChanged();
        return;
    }
}

int DisplaySettings::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : count();
}

QVariant DisplaySettings::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid))
        return {};
    const auto &display = m_displays.at(index.row());
    switch (role) {
    case Id: return display.id;
    case Name: return display.name;
    case Details: return display.details;
    case DockEnabled: return display.enabled;
    default: return {};
    }
}

QHash<int, QByteArray> DisplaySettings::roleNames() const
{
    return {{Id, "monitorId"}, {Name, "monitorName"}, {Details, "monitorDetails"}, {DockEnabled, "dockEnabled"}};
}
