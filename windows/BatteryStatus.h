#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

struct BatteryReading
{
    bool valid = false;
    bool present = false;
    bool charging = false;
    int ac = -1;
    int percent = -1;
    int remainingSeconds = -1;
    quint32 fullCapacity = 0;
    quint32 remainingCapacity = 0;
    int chargeRate = 0;
};

class BatteryStatus final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap snapshot READ snapshot NOTIFY snapshotChanged FINAL)

public:
    explicit BatteryStatus(bool enabled);
    QVariantMap snapshot() const { return m_snapshot; }
    void accept(const BatteryReading &reading);

signals:
    void snapshotChanged();
    void notification(const QVariantMap &event);

private:
    static BatteryReading readBattery();
    void setSnapshot(QVariantMap snapshot);

    int m_ac = -1;
    bool m_full = false;
    double m_chargeRate = 0;
    QElapsedTimer m_lastSample;
    QTimer m_timer;
    QVariantMap m_snapshot{{QStringLiteral("state"), QStringLiteral("unavailable")}};
};
