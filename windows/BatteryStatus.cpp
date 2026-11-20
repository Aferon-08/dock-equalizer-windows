#include "BatteryStatus.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

#ifdef Q_OS_WIN
#include <QtCore/qt_windows.h>
#include <powrprof.h>
#endif

namespace {

QString timeText(int minutes)
{
    return minutes < 60 ? QStringLiteral("%1 мин").arg(minutes)
        : QStringLiteral("%1 ч %2 мин").arg(minutes / 60).arg(minutes % 60);
}

} // namespace

BatteryStatus::BatteryStatus(bool enabled)
{
#ifdef Q_OS_WIN
    if (enabled) {
        m_timer.setInterval(1500);
        connect(&m_timer, &QTimer::timeout, this, [this] { accept(readBattery()); });
        QTimer::singleShot(0, this, [this] { accept(readBattery()); });
        m_timer.start();
    }
#else
    Q_UNUSED(enabled);
#endif
}

BatteryReading BatteryStatus::readBattery()
{
    BatteryReading reading;
#ifdef Q_OS_WIN
    SYSTEM_POWER_STATUS status{};
    if (!GetSystemPowerStatus(&status))
        return reading;
    reading.valid = true;
    reading.percent = status.BatteryLifePercent <= 100 ? int(status.BatteryLifePercent) : -1;
    reading.ac = status.ACLineStatus <= 1 ? int(status.ACLineStatus) : -1;
    if (status.BatteryFlag == 255 && reading.percent < 0)
        return {};
    reading.present = status.BatteryFlag == 255 ? reading.percent >= 0 : !(status.BatteryFlag & 128);
    reading.charging = status.BatteryFlag != 255 && (status.BatteryFlag & 8);
    if (status.BatteryLifeTime <= 24 * 60 * 60)
        reading.remainingSeconds = int(status.BatteryLifeTime);

    if (reading.present && reading.ac == 1) {
        SYSTEM_BATTERY_STATE battery{};
        if (CallNtPowerInformation(SystemBatteryState, nullptr, 0, &battery, sizeof battery) == 0
            && battery.BatteryPresent && battery.Charging) {
            reading.charging = true;
            reading.fullCapacity = battery.MaxCapacity;
            reading.remainingCapacity = battery.RemainingCapacity;
            reading.chargeRate = qint32(battery.Rate);
        }
    }
#endif
    return reading;
}

void BatteryStatus::setSnapshot(QVariantMap snapshot)
{
    if (m_snapshot == snapshot)
        return;
    m_snapshot = std::move(snapshot);
    emit snapshotChanged();
}

void BatteryStatus::accept(const BatteryReading &reading)
{
    const qint64 gap = m_lastSample.isValid() ? m_lastSample.restart() : 0;
    if (!m_lastSample.isValid())
        m_lastSample.start();
    if (!reading.valid || reading.ac < 0) {
        setSnapshot({{QStringLiteral("state"), QStringLiteral("unavailable")}});
        return;
    }
    if (!reading.present) {
        m_ac = -1;
        m_full = false;
        m_chargeRate = 0;
        setSnapshot({{QStringLiteral("state"), QStringLiteral("noBattery")}});
        return;
    }

    const bool onMains = reading.ac == 1;
    const bool full = onMains && (reading.percent == 100 || (reading.percent < 0 && m_full));
    const bool sourceChanged = m_ac >= 0 && reading.ac != m_ac;
    const bool becameFull = m_ac == 1 && !m_full && full;
    if (sourceChanged || gap > 8000 || !reading.charging || reading.chargeRate <= 0)
        m_chargeRate = 0;
    if (onMains && reading.charging && reading.chargeRate > 0)
        m_chargeRate = m_chargeRate > 0 ? m_chargeRate * 0.7 + reading.chargeRate * 0.3 : reading.chargeRate;
    m_ac = reading.ac;
    m_full = full;

    const QString state = full ? QStringLiteral("full") : onMains ? QStringLiteral("mains") : QStringLiteral("battery");
    const QString status = full ? tr("Полный заряд") : reading.charging && onMains ? tr("Заряжается")
        : onMains ? tr("Подключена к сети") : tr("Питание от батареи");
    const QString summary = reading.percent >= 0 ? tr("%1 % · %2").arg(reading.percent).arg(status) : status;
    QString detail;
    if (full) {
        detail = tr("Батарея полностью заряжена.");
    } else if (onMains && reading.charging) {
        const double minutes = m_chargeRate > 0 && reading.fullCapacity > reading.remainingCapacity
            && reading.fullCapacity != std::numeric_limits<quint32>::max()
            ? 60.0 * (reading.fullCapacity - reading.remainingCapacity) / m_chargeRate : 0;
        detail = minutes > 0 && minutes <= 24 * 60
            ? tr("До полного заряда около %1.").arg(timeText(int(std::ceil(minutes))))
            : tr("Windows пока не предоставила данные для оценки времени зарядки.");
    } else if (onMains) {
        detail = tr("Питание подключено. Зарядка сейчас не идёт.");
    } else if (reading.remainingSeconds > 0) {
        detail = tr("Осталось около %1 работы.").arg(timeText(std::max(1, reading.remainingSeconds / 60)));
    } else {
        detail = tr("Windows не предоставила оценку оставшегося времени работы.");
    }

    QVariantMap snapshot{{QStringLiteral("state"), state}, {QStringLiteral("charge"), reading.percent},
        {QStringLiteral("summary"), summary}, {QStringLiteral("detail"), detail}};
    setSnapshot(snapshot);
    if (!sourceChanged && !becameFull)
        return;
    snapshot.insert(QStringLiteral("kind"), QStringLiteral("battery"));
    snapshot.insert(QStringLiteral("accent"), QStringLiteral("#a4e7cc"));
    snapshot.insert(QStringLiteral("source"), tr("Батарея"));
    snapshot.insert(QStringLiteral("liveBattery"), true);
    snapshot.insert(QStringLiteral("title"), sourceChanged
        ? (onMains ? tr("Зарядка подключена") : tr("Питание отключено")) : tr("Батарея заряжена"));
    emit notification(snapshot);
}
