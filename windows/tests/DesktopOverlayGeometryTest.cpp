#include "DesktopOverlayGeometry.h"

#include <QDebug>

using DesktopOverlayGeometry::compactNotificationArea;

namespace {

bool expectArea(const char *description, const QRect &expected, const QRect &actual)
{
    if (expected == actual)
        return true;
    qCritical() << description << "expected" << expected << "but received" << actual;
    return false;
}

} // namespace

int main()
{
    // Native pixels for a monitor to the left of the primary at 150% DPI.
    const QRect workArea(-1920, 0, 1920, 1014);
    const QRect zone(-1770, 12, 1620, 114);
    const QSize minimum(606, 114);
    const QRegion leftCover(QRect(-1920, 0, 600, 54));
    const QRegion rightCover(QRect(-850, 70, 700, 100));

    bool passed = expectArea("clear zone", zone, compactNotificationArea(zone, minimum, workArea, {}));
    passed &= expectArea("partial cover leaves a compact card", QRect(-1320, 12, 1170, 114),
        compactNotificationArea(zone, minimum, workArea, leftCover));
    passed &= expectArea("several windows obstruct different rows", {},
        compactNotificationArea(zone, minimum, workArea, leftCover | rightCover));
    passed &= expectArea("nearest fitting strip to the middle", QRect(-940, 12, 790, 114),
        compactNotificationArea(zone, minimum, workArea, QRegion(QRect(-1090, 0, 150, 130))));
    passed &= expectArea("window below the compact card", zone,
        compactNotificationArea(zone, minimum, workArea, QRegion(QRect(-1920, 126, 1920, 900))));
    passed &= expectArea("only space on this monitor is eligible", {},
        compactNotificationArea(QRect(-150, 12, 800, 114), minimum, workArea, {}));
    passed &= expectArea("exact minimum fits on the monitor", QRect(-606, 12, 606, 114),
        compactNotificationArea(QRect(-606, 12, 1060, 114), minimum, workArea, {}));
    return passed ? 0 : 1;
}
