#include "ArtworkColor.h"

#include <QColorSpace>
#include <QImage>

#include <algorithm>
#include <array>

namespace {

struct HueSample
{
    double weight = 0;
    double red = 0;
    double green = 0;
    double blue = 0;

    void add(QRgb pixel, double amount)
    {
        weight += amount;
        red += amount * qRed(pixel);
        green += amount * qGreen(pixel);
        blue += amount * qBlue(pixel);
    }
};

} // namespace

QColor artworkAccent(const QImage &artwork)
{
    if (artwork.isNull())
        return {};

    QImage sample = artwork.scaled(QSize(48, 48), Qt::KeepAspectRatio, Qt::SmoothTransformation);
    if (sample.colorSpace().isValid() && sample.colorSpace() != QColorSpace::SRgb)
        sample.convertToColorSpace(QColorSpace::SRgb);
    sample = sample.convertToFormat(QImage::Format_ARGB32);

    constexpr int hueSections = 24;
    std::array<HueSample, hueSections> hues{};
    double opacity = 0;
    for (int y = 0; y < sample.height(); ++y) {
        const auto *pixels = reinterpret_cast<const QRgb *>(sample.constScanLine(y));
        for (int x = 0; x < sample.width(); ++x) {
            const QRgb pixel = pixels[x];
            if (qAlpha(pixel) < 40)
                continue;
            const double alpha = qAlpha(pixel) / 255.0;
            opacity += alpha;

            const int low = std::min({qRed(pixel), qGreen(pixel), qBlue(pixel)});
            const int high = std::max({qRed(pixel), qGreen(pixel), qBlue(pixel)});
            const double chroma = (high - low) / 255.0;
            if (chroma < 0.15)
                continue;

            const float hue = QColor::fromRgb(pixel).hslHueF();
            const auto index = std::min(hueSections - 1, int(hue * hueSections));
            hues[index].add(pixel, alpha * chroma);
        }
    }
    if (opacity == 0)
        return {};

    // Merge neighboring hue samples so colors close to a bin boundary compete
    // together, including reds that wrap around the color wheel.
    HueSample strongest;
    for (int i = 0; i < hueSections; ++i) {
        const auto &previous = hues[(i + hueSections - 1) % hueSections];
        const auto &current = hues[i];
        const auto &next = hues[(i + 1) % hueSections];
        const double weight = previous.weight + current.weight + next.weight;
        if (weight > strongest.weight) {
            strongest = {weight, previous.red + current.red + next.red,
                previous.green + current.green + next.green, previous.blue + current.blue + next.blue};
        }
    }
    if (strongest.weight < opacity * 0.035)
        return QColor(195, 195, 195);

    const auto dominant = QColor::fromRgbF(strongest.red / (255 * strongest.weight),
        strongest.green / (255 * strongest.weight), strongest.blue / (255 * strongest.weight));
    const float saturation = std::clamp(dominant.hslSaturationF() * 0.65f, 0.36f, 0.62f);
    return QColor::fromHslF(dominant.hslHueF(), saturation, 0.74f);
}
