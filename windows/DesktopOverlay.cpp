#include "DesktopOverlay.h"

#include <QGuiApplication>
#include <QPainterPath>
#include <QRegion>
#include <QScreen>
#include <QTimer>
#include <QWindow>

#include <utility>

#ifdef Q_OS_WIN
#include <QtCore/qt_windows.h>
#include <dwmapi.h>
#endif

namespace {

QRegion roundedRegion(const QRectF &rect, qreal radius)
{
    if (rect.isEmpty())
        return {};

    QPainterPath outline;
    outline.addRoundedRect(rect, radius, radius);
    return QRegion(outline.toFillPolygon().toPolygon());
}

#ifdef Q_OS_WIN
bool fullscreenOnPrimaryMonitor()
{
    const HWND foreground = GetForegroundWindow();
    if (!foreground)
        return false;

    const HWND window = GetAncestor(foreground, GA_ROOT);
    if (!window || window == GetShellWindow() || window == GetDesktopWindow()
            || !IsWindowVisible(window) || IsIconic(window))
        return false;

    DWORD processId = 0;
    GetWindowThreadProcessId(window, &processId);
    if (processId == GetCurrentProcessId())
        return false;

    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    if (IsZoomed(window) && ((style & WS_CAPTION) == WS_CAPTION || (style & WS_THICKFRAME)))
        return false;

    // The Windows primary monitor contains the native origin. Use native
    // monitor bounds here so mixed DPI and taskbar placement do not affect the test.
    const HMONITOR monitor = MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info))
        return false;

    RECT bounds{};
    if (FAILED(DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS, &bounds, sizeof(bounds)))
            && !GetWindowRect(window, &bounds))
        return false;

    constexpr LONG tolerance = 1;
    return bounds.left <= info.rcMonitor.left + tolerance
        && bounds.top <= info.rcMonitor.top + tolerance
        && bounds.right >= info.rcMonitor.right - tolerance
        && bounds.bottom >= info.rcMonitor.bottom - tolerance;
}
#endif

} // namespace

DesktopOverlay::DesktopOverlay(QObject *parent)
    : QObject(parent)
{
    trackPrimaryScreen(QGuiApplication::primaryScreen());
    connect(qGuiApp, &QGuiApplication::primaryScreenChanged, this, &DesktopOverlay::trackPrimaryScreen);

#ifdef Q_OS_WIN
    // F11 and borderless transitions can resize the existing foreground HWND.
    auto *timer = new QTimer(this);
    timer->setInterval(150);
    connect(timer, &QTimer::timeout, this, &DesktopOverlay::updateFullscreenState);
    timer->start();

    auto *pointerTimer = new QTimer(this);
    pointerTimer->setInterval(16);
    connect(pointerTimer, &QTimer::timeout, this, &DesktopOverlay::updatePointerPassthrough);
    pointerTimer->start();
#endif
}

void DesktopOverlay::trackPrimaryScreen(QScreen *screen)
{
    if (m_screen)
        disconnect(m_screen, nullptr, this, nullptr);
    m_screen = screen;
    if (screen)
        connect(screen, &QScreen::availableGeometryChanged, this, &DesktopOverlay::updateWorkArea);
    updateWorkArea();
    updateFullscreenState();
}

void DesktopOverlay::updateWorkArea()
{
    const QRect area = m_screen ? m_screen->availableGeometry() : QRect{};
    if (m_workArea != area) {
        m_workArea = area;
        emit workAreaChanged();
    }
}

void DesktopOverlay::updateFullscreenState()
{
#ifdef Q_OS_WIN
    const bool active = fullscreenOnPrimaryMonitor();
    if (m_fullscreenActive != active) {
        m_fullscreenActive = active;
        emit fullscreenActiveChanged();
    }
#endif
}

void DesktopOverlay::setPanelRegion(QWindow *window, const QRectF &body, qreal radius,
                                    const QRectF &leftWing, const QRectF &rightWing)
{
    if (!window || body.isEmpty())
        return;

    QRegion shape = roundedRegion(body, radius);
    for (const QRectF &wing : {leftWing, rightWing})
        shape |= roundedRegion(wing, wing.height() / 2);
    shape &= QRect(QPoint(), window->size());
#ifdef Q_OS_WIN
    // A native window region also clips the accelerated swapchain. Keep the
    // surface intact and switch pointer handling over the transparent area.
    m_panel = window;
    m_panelRegion = std::move(shape);
    updatePointerPassthrough();
#else
    if (window->mask() != shape)
        window->setMask(shape);
#endif
}

void DesktopOverlay::updatePointerPassthrough()
{
#ifdef Q_OS_WIN
    if (!m_panel || !m_panel->isVisible() || !m_panel->handle())
        return;

    const HWND hwnd = reinterpret_cast<HWND>(m_panel->winId());
    POINT cursor{};
    if (!GetCursorPos(&cursor) || !ScreenToClient(hwnd, &cursor))
        return;

    const qreal dpi = m_panel->devicePixelRatio();
    const QPoint local(qRound(cursor.x / dpi), qRound(cursor.y / dpi));
    const bool pass = QRect(QPoint(), m_panel->size()).contains(local)
        && !m_panelRegion.contains(local) && GetCapture() != hwnd;
    const LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    const LONG_PTR next = pass ? style | WS_EX_TRANSPARENT : style & ~WS_EX_TRANSPARENT;
    if ((style & WS_EX_LAYERED) && next != style)
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, next);
#endif
}
