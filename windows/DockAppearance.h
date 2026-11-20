#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class QSettings;

class DockAppearance final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap values READ values NOTIFY changed FINAL)
    Q_PROPERTY(QVariantList sliders READ sliders CONSTANT FINAL)

public:
    explicit DockAppearance(QSettings *settings);

    QVariantMap values() const { return m_values; }
    QVariantList sliders() const;
    Q_INVOKABLE void setArtworkColors(bool enabled);
    Q_INVOKABLE void setWavyProgress(bool enabled);
    Q_INVOKABLE void setGlassEnabled(bool enabled);
    Q_INVOKABLE void setDesktopGlass(bool enabled);
    Q_INVOKABLE void setCaptureBorderless(bool enabled);
    Q_INVOKABLE void setNumber(const QString &name, double value);
    Q_INVOKABLE void reset();

signals:
    void changed();

private:
    void setValue(const QString &name, const QVariant &value);

    QSettings *const m_settings;
    QVariantMap m_values;
};
