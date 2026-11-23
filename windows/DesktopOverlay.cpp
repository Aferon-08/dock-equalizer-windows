#include "DesktopOverlay.h"
#include "DesktopOverlayGeometry.h"

#include <QEvent>
#include <QPainterPath>
#include <QPlatformSurfaceEvent>
#include <QRegion>
#include <QScreen>
#include <QTimer>
#include <QWindow>
#include <QtMath>

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

QRegion notificationPartsRegion(const QVariantList &parts)
{
    QRegion region;
    for (const auto &part : parts) {
        const auto shape = part.toMap();
        region |= roundedRegion(shape.value(QStringLiteral("box")).toRectF(),
                                shape.value(QStringLiteral("radius")).toReal());
    }
    return region;
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

bool fullscreenWindow(HWND window, const QRect &bounds, const QRect &monitor, const QRect &workArea)
{
    if (!bounds.adjusted(-1, -1, 1, 1).contains(monitor))
        return false;

    const LONG_PTR style = GetWindowLongPtrW(window, GWL_STYLE);
    const bool framed = (style & WS_CAPTION) == WS_CAPTION || (style & WS_THICKFRAME);
    return !IsZoomed(window) || !framed || !workArea.adjusted(-1, -1, 1, 1).contains(monitor);
}

struct DesktopWindows
{
    HMONITOR monitor = nullptr;
    QRect bounds;
    QRect workArea;
    QRect notificationWorkArea;
    HWND panel = nullptr;
    HWND shell = GetShellWindow();
    HWND foreground = GetAncestor(GetForegroundWindow(), GA_ROOT);
    DWORD shellProcess = 0;
    QRegion expanded;
    QRegion notification;
    QRect compactZone;
    QRegion compactOcclusion;
    QRegion fullscreenVisibleArea;
    HWND lastOrdinary = nullptr;
    bool foregroundOnMonitor = false;
    bool passedPanel = false;
    bool needsRestack = false;
    bool obstructed = false;
    bool notificationObstructed = false;
    bool fullscreen = false;
    bool bottomTaskbarVisible = false;
};

bool collectTaskbar(HWND window, DesktopWindows &state)
{
    wchar_t name[32]{};
    const std::wstring_view type(name, size_t(GetClassNameW(window, name, 32)));
    if (type != L"Shell_TrayWnd" && type != L"Shell_SecondaryTrayWnd")
        return false;
    if (MonitorFromWindow(window, MONITOR_DEFAULTTONULL) != state.monitor)
        return true;

    const QRect shown = windowBounds(window).intersected(state.bounds);
    // An auto-hidden taskbar leaves a thin activation strip at the edge.
    if (shown.width() <= 3 || shown.height() <= 3)
        return true;

    auto &area = state.notificationWorkArea;
    if (shown.width() > shown.height()) {
        if (shown.bottom() == state.bounds.bottom()) {
            area.setBottom(qMin(area.bottom(), shown.top() - 1));
            state.bottomTaskbarVisible = true;
        } else if (shown.top() == state.bounds.top()) {
            area.setTop(qMax(area.top(), shown.bottom() + 1));
        }
    } else if (shown.left() == state.bounds.left()) {
        area.setLeft(qMax(area.left(), shown.right() + 1));
    } else if (shown.right() == state.bounds.right()) {
        area.setRight(qMin(area.right(), shown.left() - 1));
    }
    return true;
}

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
    if (process == state.shellProcess && collectTaskbar(window, state))
        return TRUE;
    if (process == GetCurrentProcessId() || window == GetDesktopWindow()
            || !applicationWindow(window, state.foreground, process == state.shellProcess))
        return TRUE;

    if (!(GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_TOPMOST)) {
        state.lastOrdinary = window;
        state.needsRestack |= state.passedPanel;
    }

    const bool checkFullscreen = !state.fullscreen && (!state.foregroundOnMonitor || window == state.foreground)
        && !state.fullscreenVisibleArea.isEmpty();
    if (!checkFullscreen && state.compactZone.isEmpty()
            && (state.obstructed || state.expanded.isEmpty())
            && (state.notificationObstructed || state.notification.isEmpty()))
        return TRUE;

    const auto bounds = windowBounds(window);
    if (!bounds.intersects(state.bounds))
        return TRUE;

    state.obstructed |= state.expanded.intersects(bounds);
    state.notificationObstructed |= state.notification.intersects(bounds);
    state.compactOcclusion |= bounds.intersected(state.compactZone);

    // Respect the foreground window on its own monitor. On another monitor
    // a fullscreen window can still be visible behind small floating windows.
    if (checkFullscreen) {
        state.fullscreen = fullscreenWindow(window, bounds, state.bounds, state.workArea);
        state.fullscreenVisibleArea -= bounds;
    }
    return TRUE;
}

QRect logicalWorkArea(const QRect &logicalArea, const QRect &workArea, const QRect &visibleArea, qreal scale)
{
    return logicalArea.adjusted(qCeil((visibleArea.left() - workArea.left()) / scale),
        qCeil((visibleArea.top() - workArea.top()) / scale),
        -qCeil((workArea.right() - visibleArea.right()) / scale),
        -qCeil((workArea.bottom() - visibleArea.bottom()) / scale));
}

HRGN notificationShape(const QRectF &body, qreal radius, qreal scale)
{
    const QRect bounds = body.isEmpty() ? QRect{} : QRectF(body.topLeft() * scale, body.size() * scale).toAlignedRect();
    const int diameter = qBound(0, qRound(2 * radius * scale), qMin(bounds.width(), bounds.height()));
    return diameter > 0
        ? CreateRoundRectRgn(bounds.x(), bounds.y(), bounds.x() + bounds.width(), bounds.y() + bounds.height(),
                             diameter, diameter)
        : CreateRectRgn(bounds.x(), bounds.y(), bounds.x() + bounds.width(), bounds.y() + bounds.height());
}

void setNotificationMask(HWND window, const QRectF &body, qreal radius, const QVariantList &parts, qreal scale)
{
    // The card, pucks and moving icons use the same contour for rendering and input.
    const HRGN mask = notificationShape(body, radius, scale);
    if (!mask)
        return;
    for (const auto &part : parts) {
        const auto shape = part.toMap();
        const HRGN piece = notificationShape(shape.value(QStringLiteral("box")).toRectF(),
            shape.value(QStringLiteral("radius")).toReal(), scale);
        if (piece) {
            CombineRgn(mask, mask, piece, RGN_OR);
            DeleteObject(piece);
        }
    }
    if (!SetWindowRgn(window, mask, TRUE))
        DeleteObject(mask);
}
#endif

} // namespace

DesktopOverlay::DesktopOverlay(QScreen *screen)
    : m_screen(screen)
{
    connect(screen, &QScreen::geometryChanged, this, &DesktopOverlay::updateScreenGeometry);
    connect(screen, &QScreen::availableGeometryChanged, this, &DesktopOverlay::updateScreenGeometry);
    updateScreenGeometry();

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

void DesktopOverlay::updateScreenGeometry()
{
    const QRect previousScreenArea = std::exchange(m_screenArea, m_screen ? m_screen->geometry() : QRect{});
    const QRect previousWorkArea = std::exchange(m_workArea, m_screen ? m_screen->availableGeometry() : QRect{});
    if (m_screenArea != previousScreenArea)
        emit screenAreaChanged();
    if (m_workArea != previousWorkArea)
        emit workAreaChanged();
    updateDesktopState();
}

void DesktopOverlay::updateDesktopState()
{
    QRect notificationWorkArea = m_workArea;
    QRectF compactArea;
    bool active = false;
    bool bottomTaskbarVisible = false;
    bool obstructed = false;
    bool notificationObstructed = false;
#ifdef Q_OS_WIN
    const auto *native = m_screen ? m_screen->nativeInterface<QNativeInterface::QWindowsScreen>() : nullptr;
    const HMONITOR monitor = native ? native->handle() : nullptr;
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!monitor || !GetMonitorInfoW(monitor, &info))
        return;
    DesktopWindows windows;
    windows.monitor = monitor;
    windows.bounds = QRect(info.rcMonitor.left, info.rcMonitor.top,
        info.rcMonitor.right - info.rcMonitor.left, info.rcMonitor.bottom - info.rcMonitor.top);
    windows.workArea = QRect(info.rcWork.left, info.rcWork.top,
        info.rcWork.right - info.rcWork.left, info.rcWork.bottom - info.rcWork.top);
    windows.notificationWorkArea = windows.workArea;
    windows.foregroundOnMonitor = windows.foreground
        && MonitorFromWindow(windows.foreground, MONITOR_DEFAULTTONULL) == monitor;
    windows.fullscreenVisibleArea = QRegion(windows.workArea);
    if (windows.shell)
        GetWindowThreadProcessId(windows.shell, &windows.shellProcess);

    const qreal scale = m_screen->devicePixelRatio();
    QPointF origin;
    if (m_panel) {
        windows.panel = m_panel->handle() ? reinterpret_cast<HWND>(m_panel->winId()) : nullptr;
        const QPoint offset = m_panel->position() - m_workArea.topLeft();
        POINT clientOrigin{};
        origin = windows.panel && m_panel->isVisible() && !IsIconic(windows.panel)
            && MonitorFromWindow(windows.panel, MONITOR_DEFAULTTONULL) == monitor
            && ClientToScreen(windows.panel, &clientOrigin)
            ? QPointF(clientOrigin.x, clientOrigin.y)
            : QPointF(windows.workArea.topLeft()) + offset * scale;
        const auto nativeBounds = [&](const QRectF &bounds) {
            return QRectF(origin + bounds.topLeft() * scale, bounds.size() * scale);
        };
        windows.expanded = roundedRegion(nativeBounds(m_expandedBounds), m_expandedRadius * scale) & windows.bounds;
        windows.notification = roundedRegion(nativeBounds(m_notificationBounds), m_notificationRadius * scale) & windows.bounds;
        windows.compactZone = nativeBounds(m_compactNotificationZone).toAlignedRect();
    }

    EnumWindows(scanDesktopWindow, reinterpret_cast<LPARAM>(&windows));
    active = windows.fullscreen;
    obstructed = windows.obstructed;
    notificationObstructed = windows.notificationObstructed;
    notificationWorkArea = logicalWorkArea(m_workArea, windows.workArea, windows.notificationWorkArea, scale);
    bottomTaskbarVisible = windows.bottomTaskbarVisible && !active;
    if (windows.panel && m_panel->isVisible() && !active && windows.needsRestack) {
        SetWindowPos(windows.panel, windows.lastOrdinary ? windows.lastOrdinary : HWND_TOP,
            0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }
    const auto foreground = reinterpret_cast<WId>(windows.foreground);
    if (std::exchange(m_foregroundWindow, foreground) != foreground
            && m_notificationWindow && m_notificationWindow->isVisible())
        updateNotificationWindow(true);

    if (!active && !windows.compactZone.isEmpty()) {
        const QSize minimum(qCeil(m_compactNotificationMinimum.width() * scale),
                            qCeil(m_compactNotificationMinimum.height() * scale));
        const QRect fit = DesktopOverlayGeometry::compactNotificationArea(windows.compactZone, minimum,
            windows.notificationWorkArea.intersected(windows.bounds), windows.compactOcclusion);
        if (!fit.isEmpty()) {
            const QPointF offset = (QPointF(fit.topLeft()) - origin) / scale;
            compactArea = QRectF(QPointF(offset.x(), m_compactNotificationZone.y()),
                QSizeF(fit.width() / scale, m_compactNotificationMinimum.height())) & m_compactNotificationZone;
        }
    }
#else
    if (m_panel && !m_compactNotificationZone.isEmpty()) {
        const QSize minimum(qCeil(m_compactNotificationMinimum.width()), qCeil(m_compactNotificationMinimum.height()));
        const QRect fit = DesktopOverlayGeometry::compactNotificationArea(m_compactNotificationZone.toAlignedRect(),
            minimum, m_workArea.intersected(m_screenArea).translated(-m_panel->position()), {});
        if (!fit.isEmpty()) {
            compactArea = QRectF(QPointF(fit.x(), m_compactNotificationZone.y()),
                QSizeF(fit.width(), m_compactNotificationMinimum.height())) & m_compactNotificationZone;
        }
    }
#endif

    const bool fullscreenChanged = std::exchange(m_fullscreenActive, active) != active;
    const bool expandedChanged = std::exchange(m_expandedObstructed, obstructed) != obstructed;
    const bool extendedNotificationChanged = std::exchange(m_notificationObstructed, notificationObstructed)
        != notificationObstructed;
    const bool compactChanged = std::exchange(m_compactNotificationArea, compactArea) != compactArea;
    const bool taskbarChanged = std::exchange(m_bottomTaskbarVisible, bottomTaskbarVisible) != bottomTaskbarVisible;
    if (std::exchange(m_notificationWorkArea, notificationWorkArea) != notificationWorkArea)
        emit notificationWorkAreaChanged();
    if (taskbarChanged)
        emit bottomTaskbarVisibleChanged();
    if (fullscreenChanged)
        emit fullscreenActiveChanged();
    if (expandedChanged)
        emit expandedObstructedChanged();
    if (extendedNotificationChanged)
        emit notificationObstructedChanged();
    if (compactChanged)
        emit compactNotificationAreaChanged();
}

void DesktopOverlay::setCompactNotificationZone(QWindow *window, const QRectF &zone, const QSizeF &minimumSize)
{
    if (!window || (m_panel == window && m_compactNotificationZone == zone
            && m_compactNotificationMinimum == minimumSize))
        return;

    m_panel = window;
    m_compactNotificationZone = zone;
    m_compactNotificationMinimum = minimumSize;
    updateDesktopState();
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

void DesktopOverlay::setNotificationRegion(QWindow *window, const QRectF &body, qreal radius,
                                           const QVariantList &parts)
{
    if (!window || window == m_panel)
        return;

    const bool changedWindow = m_notificationWindow != window;
    if (changedWindow) {
        if (m_notificationWindow)
            m_notificationWindow->removeEventFilter(this);
        m_notificationWindow = window;
        window->installEventFilter(this);
    } else if (body == m_notificationBody && radius == m_notificationBodyRadius && parts == m_notificationParts) {
        return;
    }

    m_notificationBody = body;
    m_notificationBodyRadius = radius;
    m_notificationParts = parts;
    updateNotificationWindow(changedWindow);
}

bool DesktopOverlay::eventFilter(QObject *object, QEvent *event)
{
    if (object == m_notificationWindow) {
        const auto type = event->type();
        const bool created = type == QEvent::PlatformSurface
            && static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated;
        if (created || type == QEvent::Show || type == QEvent::DevicePixelRatioChange)
            updateNotificationWindow(created || type == QEvent::Show);
    }
    return QObject::eventFilter(object, event);
}

void DesktopOverlay::updateNotificationWindow(bool promote)
{
    auto *window = m_notificationWindow.data();
    if (!window)
        return;

#ifdef Q_OS_WIN
    if (!window->handle())
        return;

    const HWND hwnd = reinterpret_cast<HWND>(window->winId());
    const LONG_PTR style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
    if (!(style & WS_EX_NOACTIVATE))
        SetWindowLongPtrW(hwnd, GWL_EXSTYLE, style | WS_EX_NOACTIVATE);
    if (promote || !(style & WS_EX_TOPMOST)) {
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                     SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }
    setNotificationMask(hwnd, m_notificationBody, m_notificationBodyRadius, m_notificationParts, window->devicePixelRatio());
#else
    Q_UNUSED(promote);
    QRegion mask = roundedRegion(m_notificationBody, m_notificationBodyRadius) | notificationPartsRegion(m_notificationParts);
    if (mask.isEmpty())
        mask = QRegion(-2, -2, 1, 1);
    if (window->mask() != mask)
        window->setMask(mask);
#endif
}

void DesktopOverlay::setPanelRegion(QWindow *window, const QRectF &body, qreal radius,
                                    const QRectF &leftWing, const QRectF &rightWing,
                                    const QRectF &miniPlayer, const QRectF &neck,
                                    const QRectF &sideCall, const QRectF &sideCallNeck,
                                    const QVariantList &notificationParts)
{
    if (!window)
        return;

    QRegion shape = roundedRegion(body, radius);
    for (const QRectF &capsule : {leftWing, rightWing, neck, sideCall, sideCallNeck})
        shape |= roundedRegion(capsule, capsule.height() / 2);
    if (!miniPlayer.isEmpty())
        shape |= QRegion(miniPlayer.toAlignedRect(), QRegion::Ellipse);
    shape |= notificationPartsRegion(notificationParts);
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
