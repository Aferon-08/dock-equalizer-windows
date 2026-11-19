#include "DesktopOverlay.h"
#include "DockAppearance.h"
#include "LyricsAlignment.h"
#include "LyricsImport.h"
#include "LyricsSearch.h"
#include "MediaSessions.h"
#include "SystemAudio.h"

#include <QGuiApplication>
#include <QNetworkProxyFactory>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSettings>

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
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("SekaiSoundbar"));
    app.setApplicationDisplayName(QStringLiteral("Sekai Soundbar"));
    app.setQuitOnLastWindowClosed(false);

    const auto args = app.arguments();
    const bool smokeMode = args.contains(QStringLiteral("--smoke-test"));
    const bool software = args.contains(QStringLiteral("--software-rendering"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QQuickWindow::setDefaultAlphaBuffer(true);
#ifdef Q_OS_WIN
    QQuickWindow::setGraphicsApi(software || !hasHardwareD3d11()
        ? QSGRendererInterface::Software : QSGRendererInterface::Direct3D11);
    QNetworkProxyFactory::setUseSystemConfiguration(true);
#else
    if (software)
        QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
#endif

    DesktopOverlay desktop;
    const bool liveInputs = !smokeMode && !args.contains(QStringLiteral("--demo-preview"));
    MediaSessions media(liveInputs);
    SystemAudio audio(liveInputs);
    LyricsImport lyrics;
    LyricsSearch search;
    LyricsAlignment alignment;
    QSettings settings(QStringLiteral("SekaiSoundbar"), QStringLiteral("Settings"));
    DockAppearance appearance(smokeMode ? nullptr : &settings);
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
    QVariantMap properties{{QStringLiteral("desktop"), QVariant::fromValue(&desktop)},
                           {QStringLiteral("mediaSessions"), QVariant::fromValue(&media)},
                           {QStringLiteral("systemAudio"), QVariant::fromValue(&audio)},
                           {QStringLiteral("lyricsImport"), QVariant::fromValue(&lyrics)},
                           {QStringLiteral("lyricsSearch"), QVariant::fromValue(&search)},
                           {QStringLiteral("lyricsAlignment"), QVariant::fromValue(&alignment)},
                           {QStringLiteral("appearance"), QVariant::fromValue(&appearance)}};
    const auto smoke = args.indexOf(QStringLiteral("--smoke-test"));
    if (smoke >= 0 && smoke + 2 < args.size()) {
        properties.insert(QStringLiteral("smokeLrc"), QUrl::fromLocalFile(args.at(smoke + 1)));
        properties.insert(QStringLiteral("smokeWordtime"), QUrl::fromLocalFile(args.at(smoke + 2)));
    }
    QQmlApplicationEngine engine;
    engine.setInitialProperties(properties);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Sekai.Soundbar", "Main");
    return app.exec();
}
