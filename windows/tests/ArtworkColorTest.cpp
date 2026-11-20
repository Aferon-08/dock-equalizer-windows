#include "../ArtworkColor.h"

#include <QDebug>
#include <QImage>

int main()
{
    QImage cover(48, 48, QImage::Format_ARGB32);
    cover.fill(Qt::transparent);
    if (artworkAccent({}).isValid() || artworkAccent(cover).isValid()) {
        qCritical() << "An absent or transparent cover must fall back to the dock palette";
        return 1;
    }

    cover.fill(Qt::white);
    for (int y = 8; y < 25; ++y) {
        const QColor shade = (y % 2 == 0) ? QColor(213, 40, 32) : QColor(215, 24, 73);
        for (int x = 8; x < 39; ++x)
            cover.setPixelColor(x, y, shade);
    }
    const QColor warm = artworkAccent(cover);
    if (!warm.isValid() || warm.red() <= warm.blue() || warm.red() <= warm.green()
            || warm.lightnessF() < 0.65 || warm.lightnessF() > 0.82) {
        qCritical() << "A visible red accent must stand out against a light background" << warm;
        return 1;
    }

    cover.fill(QColor(231, 28, 113, 0));
    for (int y = 15; y < 34; ++y) {
        for (int x = 12; x < 36; ++x)
            cover.setPixelColor(x, y, QColor(26, 92, 217));
    }
    const QColor cool = artworkAccent(cover);
    if (!cool.isValid() || cool.blue() <= cool.red() || cool.blue() <= cool.green()) {
        qCritical() << "Transparent pixels must not affect the selected accent" << cool;
        return 1;
    }

    cover.fill(QColor(30, 30, 30));
    const QColor monochrome = artworkAccent(cover);
    if (!monochrome.isValid() || monochrome.saturation() != 0 || monochrome.lightnessF() < 0.65) {
        qCritical() << "Monochrome artwork needs a readable neutral accent" << monochrome;
        return 1;
    }
}
