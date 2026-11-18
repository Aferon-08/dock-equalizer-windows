#include "DesktopOverlay.h"
#include "MediaSessions.h"
#include "SystemAudio.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("SekaiSoundbar"));
    app.setApplicationDisplayName(QStringLiteral("Sekai Soundbar"));
    app.setQuitOnLastWindowClosed(false);

    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QQuickWindow::setDefaultAlphaBuffer(true);
#ifdef Q_OS_WIN
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
#endif

    DesktopOverlay desktop;
    const auto args = app.arguments();
    const bool liveInputs = !args.contains(QStringLiteral("--smoke-test"))
        && !args.contains(QStringLiteral("--demo-preview"));
    MediaSessions media(liveInputs);
    SystemAudio audio(liveInputs);
    QQmlApplicationEngine engine;
    engine.setInitialProperties({{QStringLiteral("desktop"), QVariant::fromValue(&desktop)},
                                 {QStringLiteral("mediaSessions"), QVariant::fromValue(&media)},
                                 {QStringLiteral("systemAudio"), QVariant::fromValue(&audio)}});
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule("Sekai.Soundbar", "Main");
    return app.exec();
}
