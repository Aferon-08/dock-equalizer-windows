#include "DockAppearance.h"

#include <QSettings>

#include <algorithm>
#include <cmath>

namespace {

struct Slider
{
    const char *key;
    const char16_t *label;
    double initial;
    double minimum;
    double maximum;
    double step;
    bool pixels = false;
};

constexpr Slider settings[] = {
    {"glassOpacity", u"Непрозрачность корпуса", .78, .1, 1, .02},
    {"glassRefraction", u"Сила преломления", 1, 0, 2, .05},
    {"glassBlur", u"Матовость лирики", 3.8, 0, 8, .2, true},
    {"glassDarkening", u"Затемнение лирики", .23, 0, .8, .01},
    {"glassLight", u"Яркость музыкальной подсветки", 1, 0, 2, .05},
};

const QString glassEnabled = QStringLiteral("dockGlass");
const QString desktopGlass = QStringLiteral("desktopGlass");
const QString captureBorderless = QStringLiteral("captureBorderless");

QString key(const QString &name)
{
    return QStringLiteral("appearance/") + name;
}

} // namespace

DockAppearance::DockAppearance(QSettings *settingsStore)
    : m_settings(settingsStore)
{
    m_values.insert(glassEnabled, !m_settings || m_settings->value(key(glassEnabled), true).toBool());
    m_values.insert(desktopGlass, m_settings && m_settings->value(key(desktopGlass), false).toBool());
    m_values.insert(captureBorderless, m_settings && m_settings->value(key(captureBorderless), false).toBool());
    for (const auto &setting : settings) {
        const auto name = QString::fromLatin1(setting.key);
        double value = setting.initial;
        if (m_settings) {
            bool ok = false;
            const auto saved = m_settings->value(key(name)).toDouble(&ok);
            if (ok && std::isfinite(saved))
                value = std::clamp(saved, setting.minimum, setting.maximum);
        }
        m_values.insert(name, value);
    }
}

QVariantList DockAppearance::sliders() const
{
    QVariantList result;
    for (const auto &setting : settings) {
        result.append(QVariantMap{{QStringLiteral("key"), QString::fromLatin1(setting.key)},
            {QStringLiteral("label"), QString::fromUtf16(setting.label)}, {QStringLiteral("minimum"), setting.minimum},
            {QStringLiteral("maximum"), setting.maximum}, {QStringLiteral("step"), setting.step},
            {QStringLiteral("pixels"), setting.pixels}});
    }
    return result;
}

void DockAppearance::setGlassEnabled(bool enabled)
{
    setValue(glassEnabled, enabled);
}

void DockAppearance::setDesktopGlass(bool enabled)
{
    setValue(desktopGlass, enabled);
}

void DockAppearance::setCaptureBorderless(bool enabled)
{
    setValue(captureBorderless, enabled);
}

void DockAppearance::setNumber(const QString &name, double value)
{
    if (!std::isfinite(value))
        return;
    for (const auto &setting : settings) {
        if (name == QLatin1String(setting.key)) {
            setValue(name, std::clamp(value, setting.minimum, setting.maximum));
            return;
        }
    }
}

void DockAppearance::reset()
{
    m_values.insert(glassEnabled, true);
    m_values.insert(desktopGlass, false);
    m_values.insert(captureBorderless, false);
    if (m_settings) {
        m_settings->remove(key(glassEnabled));
        m_settings->remove(key(desktopGlass));
        m_settings->remove(key(captureBorderless));
    }
    for (const auto &setting : settings) {
        const auto name = QString::fromLatin1(setting.key);
        m_values.insert(name, setting.initial);
        if (m_settings)
            m_settings->remove(key(name));
    }
    emit changed();
}

void DockAppearance::setValue(const QString &name, const QVariant &value)
{
    if (m_values.value(name) == value)
        return;
    m_values.insert(name, value);
    if (m_settings)
        m_settings->setValue(key(name), value);
    emit changed();
}
