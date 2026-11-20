#include "DesktopOverlay.h"
#include "DisplaySettings.h"
#include "DockAppearance.h"
#include "LyricsAlignment.h"
#include "LyricsImport.h"
#include "LyricsSearch.h"
#include "MediaSessions.h"
#include "StartupSettings.h"
#include "SystemAudio.h"

#include <QAction>
#include <QApplication>
#include <QCursor>
#include <QMenu>
#include <QNetworkProxyFactory>
#include <QPainter>
#include <QPainterPath>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QScopeGuard>
#include <QSettings>
#include <QSystemTrayIcon>

#include <map>
#include <memory>

namespace {

QIcon soundbarIcon()
{
    QPixmap image(64, 64);
    image.fill(Qt::transparent);
    QPainter paint(&image);
    paint.setRenderHint(QPainter::Antialiasing);
    paint.setPen(Qt::NoPen);
    paint.setBrush(QColor(26, 47, 41));
    paint.drawRoundedRect(QRectF(3, 3, 58, 58), 15, 15);
    QPainterPath drop(QPointF(32, 11));
    drop.cubicTo(37, 22, 47, 30, 47, 39);
    drop.cubicTo(47, 56, 17, 56, 17, 39);
    drop.cubicTo(17, 30, 27, 22, 32, 11);
    paint.setBrush(QColor(150, 220, 192));
    paint.drawPath(drop);
    paint.end();
    return QIcon(image);
}

std::unique_ptr<QWindow> createWindow(QQmlComponent &component, const QVariantMap &properties,
                                      QScreen *screen = nullptr)
{
    std::unique_ptr<QObject> object(component.beginCreate(component.engine()->rootContext()));
    if (!object) {
        qWarning().noquote() << component.errorString();
        return {};
    }

    component.setInitialProperties(object.get(), properties);
    auto *window = qobject_cast<QWindow *>(object.get());
    if (window && screen)
        window->setScreen(screen);
    component.completeCreate();

    if (!window || component.isError()) {
        qWarning().noquote() << component.errorString();
        return {};
    }
    object.release();
    return std::unique_ptr<QWindow>(window);
}

struct ScreenDock {
    std::unique_ptr<DesktopOverlay> desktop;
    std::unique_ptr<QWindow> window;
};

} // namespace

#ifdef Q_OS_WIN
#include <d3d11.h>

namespace {

bool hasHardwareD3d11()
{
    ID3D11Device *device = nullptr;
    const auto result = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION, &device, nullptr, nullptr);
    if (device)
        device->Release();
    return SUCCEEDED(result);
}

} // namespace
#endif

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("SekaiSoundbar"));
    app.setApplicationDisplayName(QStringLiteral("Sekai Soundbar"));
    app.setApplicationVersion(QStringLiteral(SOUNDBAR_VERSION));
    app.setQuitOnLastWindowClosed(false);

    const auto args = app.arguments();
    const bool smokeMode = args.contains(QStringLiteral("--smoke-test"));
    const bool software = args.contains(QStringLiteral("--software-rendering"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QQuickWindow::setDefaultAlphaBuffer(true);
#ifdef Q_OS_WIN
    // The installer uses this same guard while switching the runtime folder.
    const HANDLE instance = smokeMode ? nullptr : CreateMutexW(nullptr, FALSE, L"Local\\SekaiSoundbar.Instance");
    const bool alreadyRunning = instance && GetLastError() == ERROR_ALREADY_EXISTS;
    const auto releaseInstance = qScopeGuard([instance] { if (instance) CloseHandle(instance); });
    if (alreadyRunning)
        return 0;
    QQuickWindow::setGraphicsApi(software || !hasHardwareD3d11()
        ? QSGRendererInterface::Software : QSGRendererInterface::Direct3D11);
    QNetworkProxyFactory::setUseSystemConfiguration(true);
#else
    if (software)
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
#endif

    const bool demoPreview = args.contains(QStringLiteral("--demo-preview"));
    const bool liveInputs = !smokeMode && !demoPreview;
    MediaSessions media(liveInputs);
    SystemAudio audio(liveInputs);
    LyricsImport lyrics;
    LyricsSearch search;
    LyricsAlignment alignment;
    QSettings settings(QStringLiteral("SekaiSoundbar"), QStringLiteral("Settings"));
    DockAppearance appearance(smokeMode ? nullptr : &settings);
    DisplaySettings displays(smokeMode ? nullptr : &settings);
    StartupSettings startup(!smokeMode);
    const auto autoSearchSetting = QStringLiteral("lyrics/automatic");
    const auto proxySetting = QStringLiteral("lyrics/proxy");
    search.setAutomatic(settings.value(autoSearchSetting, true).toBool());
    search.configureProxy(settings.value(proxySetting).toString());
    QObject::connect(&search, &LyricsSearch::automaticChanged, &app, [&] {
        settings.setValue(autoSearchSetting, search.automatic());
    });
    QObject::connect(&search, &LyricsSearch::proxyAddressChanged, &app, [&] {
        settings.setValue(proxySetting, search.proxyAddress());
    });
    QObject::connect(&media, &MediaSessions::changed, &search, [&] {
        search.setTrack(media.trackKey(), media.trackTitle(), media.trackArtist(),
                        media.trackAlbum(), media.length());
    });
    QQmlEngine engine;
    QObject::connect(&engine, &QQmlEngine::quit, &app, &QCoreApplication::quit);
    QObject::connect(&engine, &QQmlEngine::exit, &app, &QCoreApplication::exit);
    QQmlComponent stateComponent(&engine, u"Sekai.Soundbar", u"ApplicationState");
    std::unique_ptr<QObject> appState(stateComponent.createWithInitialProperties({
        {QStringLiteral("mediaSessions"), QVariant::fromValue(&media)},
        {QStringLiteral("lyricsAlignment"), QVariant::fromValue(&alignment)}
    }));
    if (!appState) {
        qWarning().noquote() << stateComponent.errorString();
        return 1;
    }

    QQmlComponent settingsComponent(&engine, u"Sekai.Soundbar", u"SettingsWindow");
    auto settingsWindow = createWindow(settingsComponent, {
        {QStringLiteral("appearance"), QVariant::fromValue(&appearance)},
        {QStringLiteral("displays"), QVariant::fromValue(&displays)},
        {QStringLiteral("startup"), QVariant::fromValue(&startup)},
        {QStringLiteral("lyricsSearch"), QVariant::fromValue(&search)}
    });
    if (!settingsWindow)
        return 1;

    QQmlComponent dockComponent(&engine, u"Sekai.Soundbar", u"Main");
    QVariantMap properties{
        {QStringLiteral("appState"), QVariant::fromValue(appState.get())},
        {QStringLiteral("mediaSessions"), QVariant::fromValue(&media)},
        {QStringLiteral("systemAudio"), QVariant::fromValue(&audio)},
        {QStringLiteral("lyricsImport"), QVariant::fromValue(&lyrics)},
        {QStringLiteral("lyricsSearch"), QVariant::fromValue(&search)},
        {QStringLiteral("lyricsAlignment"), QVariant::fromValue(&alignment)},
        {QStringLiteral("appearance"), QVariant::fromValue(&appearance)}
    };
    const auto smoke = args.indexOf(QStringLiteral("--smoke-test"));
    if (smoke >= 0 && smoke + 2 < args.size()) {
        properties.insert(QStringLiteral("smokeLrc"), QUrl::fromLocalFile(args.at(smoke + 1)));
        properties.insert(QStringLiteral("smokeWordtime"), QUrl::fromLocalFile(args.at(smoke + 2)));
    }

    std::map<QScreen *, ScreenDock> docks;
    QObject viewConnections;
    const auto updatePreview = [&] {
        auto dock = docks.find(settingsWindow->screen());
        if (dock == docks.end())
            dock = docks.begin();
        QObject *window = dock == docks.end() ? nullptr : dock->second.window.get();
        settingsWindow->setProperty("previewDock", QVariant::fromValue(window));
    };
    const auto openSettings = [&](const QString &section, QScreen *screen) {
        if (!settingsWindow->isVisible()) {
            if (!screen)
                screen = QGuiApplication::screenAt(QCursor::pos());
            if (!screen)
                screen = QGuiApplication::primaryScreen();
            if (screen) {
                const auto area = screen->availableGeometry();
                const auto size = settingsWindow->size().boundedTo(area.size() - QSize(32, 32))
                    .expandedTo(settingsWindow->minimumSize());
                settingsWindow->setScreen(screen);
                settingsWindow->resize(size);
                settingsWindow->setPosition(area.topLeft() + QPoint((area.width() - size.width()) / 2,
                    (area.height() - size.height()) / 2));
            }
        }
        if (!section.isEmpty())
            settingsWindow->setProperty("section", section);
        updatePreview();
        if (settingsWindow->windowState() == Qt::WindowMinimized)
            settingsWindow->showNormal();
        else
            settingsWindow->show();
        settingsWindow->raise();
        settingsWindow->requestActivate();
    };

    const auto syncDocks = [&] {
        const auto enabled = displays.enabledScreens();
        settingsWindow->setProperty("previewDock", QVariant::fromValue<QObject *>(nullptr));
        for (auto it = docks.begin(); it != docks.end();) {
            if (!enabled.contains(it->first))
                it = docks.erase(it);
            else
                ++it;
        }
        for (auto *screen : enabled) {
            if (docks.count(screen))
                continue;
            auto desktop = std::make_unique<DesktopOverlay>(screen);
            auto initial = properties;
            initial.insert(QStringLiteral("desktop"), QVariant::fromValue(desktop.get()));
            auto window = createWindow(dockComponent, initial, screen);
            if (!window)
                continue;
            QObject::connect(desktop.get(), &DesktopOverlay::settingsRequested, &viewConnections,
                [&, source = QPointer<QScreen>(screen)](const QString &section) { openSettings(section, source); },
                Qt::QueuedConnection);
            docks.emplace(screen, ScreenDock{std::move(desktop), std::move(window)});
        }
        updatePreview();
    };

    QObject::connect(settingsWindow.get(), &QWindow::screenChanged, &viewConnections, updatePreview);
    QObject::connect(&displays, &DisplaySettings::enabledScreensChanged, &viewConnections, syncDocks);
    syncDocks();
    if (smokeMode && docks.empty())
        return 1;

    QMenu trayMenu;
    QSystemTrayIcon tray;
    if (!smokeMode) {
        const auto showDocks = [&docks] {
            for (const auto &dock : docks)
                emit dock.second.desktop->showRequested();
        };
        auto *showDock = trayMenu.addAction(QStringLiteral("Показать док"), showDocks);
        const auto updateTray = [&displays, &media, showDock, demoPreview] {
            showDock->setEnabled(displays.enabledCount() > 0 && (demoPreview || media.player()));
        };
        updateTray();
        QObject::connect(&media, &MediaSessions::changed, showDock, updateTray);
        QObject::connect(&displays, &DisplaySettings::enabledScreensChanged, showDock, updateTray);
        trayMenu.addAction(QStringLiteral("Настройки…"), [&] { openSettings({}, nullptr); });
        trayMenu.addSeparator();
        trayMenu.addAction(QStringLiteral("Выход"), &app, &QCoreApplication::quit);
        tray.setContextMenu(&trayMenu);
        tray.setIcon(soundbarIcon());
        tray.setToolTip(QStringLiteral("Sekai Soundbar"));
        QObject::connect(&tray, &QSystemTrayIcon::activated, &viewConnections, [showDocks](QSystemTrayIcon::ActivationReason reason) {
            if (reason == QSystemTrayIcon::DoubleClick)
                showDocks();
        });
        tray.show();
        if (args.contains(QStringLiteral("--settings")))
            openSettings({}, nullptr);
    }
    return app.exec();
}
