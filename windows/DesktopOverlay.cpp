#include "DesktopOverlay.h"

#include <QPainterPath>
#include <QRegion>
#include <QScreen>
#include <QTimer>
#include <QWindow>

#include <string_view>
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
QRect windowBounds(HWND window)
{
    RECT bounds{};
    if (FAILED(DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS, &bounds, sizeof(bounds)))
            && !GetWindowRect(window, &bounds))
        return {};
    return QRect(bounds.left, bounds.top, bounds.right - bounds.left, bounds.bottom - bounds.top);
}

bool visibleWindow(HWND window)
{
    DWORD cloaked = 0;
    return IsWindowVisible(window) && !IsIconic(window)
        && (FAILED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked, sizeof(cloaked))) || !cloaked);
}

bool desktopSurface(HWND window, HWND shell)
{
    if (window == shell)
        return true;
    // Explorer can move the icon surface to a WorkerW on a wallpaper change.
    if (!shell)
        return false;
    DWORD process = 0;
    DWORD shellProcess = 0;
    GetWindowThreadProcessId(shell, &shellProcess);
    GetWindowThreadProcessId(window, &process);
    return process == shellProcess && FindWindowExW(window, nullptr, L"SHELLDLL_DefView", nullptr);
}

bool applicationWindow(HWND window, HWND foreground, bool shellProcess)
{
    wchar_t name[128]{};
    const std::wstring_view type(name, size_t(GetClassNameW(window, name, 128)));
    if (type == L"Progman" || type == L"WorkerW" || type == L"SHELLDLL_DefView"
            || type == L"Shell_TrayWnd" || type == L"Shell_SecondaryTrayWnd"
            || type == L"Windows.UI.Composition.DesktopWindowContentBridge"
            || type == L"Windows.UI.Input.InputSite.WindowClass")
        return false;

    const LONG_PTR exStyle = GetWindowLongPtrW(window, GWL_EXSTYLE);
    if (exStyle & WS_EX_LAYERED) {
        DWORD flags = 0;
        BYTE alpha = 0;
        if ((exStyle & WS_EX_TRANSPARENT)
                || (GetLayeredWindowAttributes(window, nullptr, &alpha, &flags)
                    && (flags & LWA_ALPHA) && alpha == 0))
            return false;
    }

    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    if ((style & WS_CAPTION) == WS_CAPTION || (style & WS_THICKFRAME) || (exStyle & WS_EX_APPWINDOW))
        return true;
    if (type == L"Windows.UI.Core.CoreWindow")
        return false;
    if (window == foreground)
        return true;

    // Unframed shell hosts and click-through helpers may fill a monitor
    // without displaying an application window.
    return !shellProcess && !(exStyle & (WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TRANSPARENT))
        && !GetWindow(window, GW_OWNER) && GetWindowTextLengthW(window) > 0;
}

struct DesktopWindows
{
    HWND panel = nullptr;
    HWND shell = GetShellWindow();
    HWND foreground = GetAncestor(GetForegroundWindow(), GA_ROOT);
    DWORD shellProcess = 0;
    QRegion expanded;
    QRegion notification;
    HWND lastOrdinary = nullptr;
    bool passedPanel = false;
    bool needsRestack = false;
    bool obstructed = false;
    bool notificationObstructed = false;
};

BOOL CALLBACK scanDesktopWindow(HWND window, LPARAM data)
{
    auto &state = *reinterpret_cast<DesktopWindows *>(data);
    if (window == state.panel) {
        state.passedPanel = true;
        return TRUE;
    }
    if (!visibleWindow(window))
        return TRUE;
    if (desktopSurface(window, state.shell)) {
        state.needsRestack |= !state.passedPanel;
        return FALSE;
    }
    DWORD process = 0;
    GetWindowThreadProcessId(window, &process);
    if (process == GetCurrentProcessId() || window == GetDesktopWindow()
            || !applicationWindow(window, state.foreground, process == state.shellProcess))
        return TRUE;

    if (!(GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_TOPMOST)) {
        state.lastOrdinary = window;
        state.needsRestack |= state.passedPanel;
    }
    if ((!state.obstructed && !state.expanded.isEmpty())
        || (!state.notificationObstructed && !state.notification.isEmpty())) {
        const auto bounds = windowBounds(window);
        state.obstructed |= state.expanded.intersects(bounds);
        state.notificationObstructed |= state.notification.intersects(bounds);
    }
    return TRUE;
}

bool fullscreenOnMonitor(const QRect &monitorBounds)
{
    const HWND foreground = GetForegroundWindow();
    if (!foreground)
        return false;

    const HWND window = GetAncestor(foreground, GA_ROOT);
    if (!window || window == GetShellWindow() || window == GetDesktopWindow()
            || !visibleWindow(window))
        return false;

    DWORD processId = 0;
    DWORD shellProcess = 0;
    GetWindowThreadProcessId(window, &processId);
    if (const HWND shell = GetShellWindow())
        GetWindowThreadProcessId(shell, &shellProcess);
    if (processId == GetCurrentProcessId() || !applicationWindow(window, window, processId == shellProcess))
        return false;

    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    if (IsZoomed(window) && ((style & WS_CAPTION) == WS_CAPTION || (style & WS_THICKFRAME)))
        return false;

    return windowBounds(window).adjusted(-1, -1, 1, 1).contains(monitorBounds);
}
#endif

} // namespace

DesktopOverlay::DesktopOverlay(QScreen *screen)
    : m_screen(screen)
{
    connect(screen, &QScreen::availableGeometryChanged, this, [this] {
        updateWorkArea();
        updateDesktopState();
    });
    updateWorkArea();
    updateDesktopState();

#ifdef Q_OS_WIN
    // Sampling coalesces the window moves and z-order changes during a drag.
    auto *timer = new QTimer(this);
    timer->setInterval(100);
    connect(timer, &QTimer::timeout, this, &DesktopOverlay::updateDesktopState);
    timer->start();

    auto *pointerTimer = new QTimer(this);
    pointerTimer->setInterval(16);
    connect(pointerTimer, &QTimer::timeout, this, &DesktopOverlay::updatePointerPassthrough);
    pointerTimer->start();
#endif
}

void DesktopOverlay::updateWorkArea()
{
    const QRect area = m_screen ? m_screen->availableGeometry() : QRect{};
    if (m_workArea != area) {
        m_workArea = area;
        emit workAreaChanged();
    }
}

void DesktopOverlay::updateDesktopState()
{
#ifdef Q_OS_WIN
    const auto *native = m_screen ? m_screen->nativeInterface<QNativeInterface::QWindowsScreen>() : nullptr;
    const HMONITOR monitor = native ? native->handle() : nullptr;
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!monitor || !GetMonitorInfoW(monitor, &info))
        return;
    const QRect monitorBounds(info.rcMonitor.left, info.rcMonitor.top,
        info.rcMonitor.right - info.rcMonitor.left, info.rcMonitor.bottom - info.rcMonitor.top);

    const bool active = fullscreenOnMonitor(monitorBounds);
    if (m_fullscreenActive != active) {
        m_fullscreenActive = active;
        emit fullscreenActiveChanged();
    }
    if (!m_panel || m_expandedBounds.isEmpty())
        return;

    const HWND panel = m_panel->handle() ? reinterpret_cast<HWND>(m_panel->winId()) : nullptr;
    const qreal scale = m_screen->devicePixelRatio();
    const QPoint offset = m_panel->position() - m_workArea.topLeft();
    POINT clientOrigin{};
    const QPointF origin = panel && !IsIconic(panel)
        && MonitorFromWindow(panel, MONITOR_DEFAULTTONULL) == monitor && ClientToScreen(panel, &clientOrigin)
        ? QPointF(clientOrigin.x, clientOrigin.y)
        : QPointF(info.rcWork.left, info.rcWork.top) + offset * scale;
    const auto nativeRegion = [&](const QRectF &bounds, qreal radius) {
        return roundedRegion(QRectF(origin + bounds.topLeft() * scale, bounds.size() * scale),
                             radius * scale) & monitorBounds;
    };
    DesktopWindows windows;
    windows.panel = panel;
    if (windows.shell)
        GetWindowThreadProcessId(windows.shell, &windows.shellProcess);
    windows.expanded = nativeRegion(m_expandedBounds, m_expandedRadius);
    windows.notification = nativeRegion(m_notificationBounds, m_notificationRadius);
    EnumWindows(scanDesktopWindow, reinterpret_cast<LPARAM>(&windows));
    if (panel && m_panel->isVisible() && !active && windows.needsRestack) {
        SetWindowPos(panel, windows.lastOrdinary ? windows.lastOrdinary : HWND_TOP,
            0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }
    if (m_expandedObstructed != windows.obstructed) {
        m_expandedObstructed = windows.obstructed;
        emit expandedObstructedChanged();
    }
    if (m_notificationObstructed != windows.notificationObstructed) {
        m_notificationObstructed = windows.notificationObstructed;
        emit notificationObstructedChanged();
    }
#endif
}

void DesktopOverlay::setExpandedRegions(QWindow *window, const QRectF &player, qreal playerRadius,
                                        const QRectF &notification, qreal notificationRadius)
{
    if (!window)
        return;
    m_panel = window;
    m_expandedBounds = player;
    m_expandedRadius = playerRadius;
    m_notificationBounds = notification;
    m_notificationRadius = notificationRadius;
    updateDesktopState();
}

void DesktopOverlay::setPanelRegion(QWindow *window, const QRectF &body, qreal radius,
                                    const QRectF &leftWing, const QRectF &rightWing,
                                    const QRectF &miniPlayer)
{
    if (!window)
        return;

    QRegion shape = roundedRegion(body, radius);
    for (const QRectF &wing : {leftWing, rightWing, miniPlayer})
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
