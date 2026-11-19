#include "../BackdropGeometry.h"

#include <QDebug>

int main()
{
    using BackdropGeometry::captureRect;
    using BackdropGeometry::sceneRect;
    const QRect primary(0, 0, 2560, 1440);
    const QPoint origin(610, 0);
    const QRectF panel(0, -24, 720, 210);
    const QRect clipped = captureRect(panel, origin, 1.5, primary);
    if (clipped != QRect(610, 0, 1080, 279)
            || sceneRect(clipped, origin, 1.5) != QRectF(0, 0, 720, 186)) {
        qCritical() << "Capture must clip the panel to the top monitor edge without shifting its image";
        return 1;
    }

    const QRect rotated(-1200, -400, 1200, 1920);
    const QPoint offset(-1000, -360);
    const QRect crop = captureRect(QRectF(11.5, 12.5, 400.2, 205.4), offset, 1.25, rotated);
    if (crop != QRect(-986, -345, 501, 258)
            || !sceneRect(crop, offset, 1.25).contains(QRectF(11.5, 12.5, 400.2, 205.4))
            || !captureRect(QRectF(1000, 0, 200, 200), offset, 1.25, rotated).isEmpty()) {
        qCritical() << "Capture must round outward and stay on the selected monitor at fractional DPI";
        return 1;
    }
    return 0;
}
