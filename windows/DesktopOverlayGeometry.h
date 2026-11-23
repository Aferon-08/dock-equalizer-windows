#pragma once

#include <QRect>
#include <QRegion>

#include <algorithm>
#include <cstdlib>
#include <limits>

namespace DesktopOverlayGeometry {

inline QRect compactNotificationArea(const QRect &zone, const QSize &minimum,
                                     const QRect &workArea, const QRegion &occluded)
{
    const QRect usable = zone.intersected(workArea);
    if (minimum.isEmpty() || usable.top() != zone.top()
            || usable.width() < minimum.width() || usable.height() < minimum.height())
        return {};

    // Keep the card at the dock's top inset. Any overlap along its height
    // rules out that horizontal span, even when several windows overlap it.
    const QRect strip(usable.topLeft(), QSize(usable.width(), minimum.height()));
    QRegion available(strip);
    for (const QRect &cover : occluded) {
        if (cover.intersects(strip))
            available -= QRect(cover.x(), strip.y(), cover.width(), strip.height());
    }

    const int center = 2 * zone.x() + zone.width();
    int bestDistance = std::numeric_limits<int>::max();
    QRect best;
    for (const QRect &candidate : available) {
        if (candidate.width() < minimum.width())
            continue;
        const int firstCenter = 2 * candidate.x() + minimum.width();
        const int lastCenter = 2 * (candidate.x() + candidate.width()) - minimum.width();
        const int distance = std::abs(center - std::clamp(center, firstCenter, lastCenter));
        if (distance < bestDistance || (distance == bestDistance && candidate.width() > best.width())) {
            best = candidate;
            bestDistance = distance;
        }
    }
    return best;
}

} // namespace DesktopOverlayGeometry
