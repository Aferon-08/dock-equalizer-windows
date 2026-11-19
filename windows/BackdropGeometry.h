#pragma once

#include <QRect>

namespace BackdropGeometry {

// Qt Quick scene coordinates are logical. Capture surfaces and Win32 monitor
// origins are physical pixels, including on monitors left of the desktop origin.
inline QRect captureRect(const QRectF &scene, const QPoint &origin, qreal scale, const QRect &monitor)
{
    return QRectF(QPointF(origin) + scene.topLeft() * scale, scene.size() * scale)
        .toAlignedRect().intersected(monitor);
}

inline QRectF sceneRect(const QRect &pixels, const QPoint &origin, qreal scale)
{
    return QRectF(QPointF(pixels.topLeft() - origin) / scale, QSizeF(pixels.size()) / scale);
}

} // namespace BackdropGeometry
