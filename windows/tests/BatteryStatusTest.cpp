#include "BatteryStatus.h"

#include <cstdio>

int main()
{
    BatteryStatus status(false);
    QList<QVariantMap> events;
    QObject::connect(&status, &BatteryStatus::notification, [&events](const QVariantMap &event) {
        events.append(event);
    });
    const auto check = [](bool condition, const char *message) {
        if (!condition)
            std::fprintf(stderr, "%s\n", message);
        return condition;
    };

    BatteryReading reading;
    reading.valid = reading.present = true;
    reading.ac = 0;
    reading.percent = 60;
    status.accept(reading);
    if (!check(events.isEmpty(), "The initial battery sample should be silent"))
        return 1;

    reading.ac = 1;
    reading.charging = true;
    reading.fullCapacity = 50000;
    reading.remainingCapacity = 30000;
    reading.chargeRate = 20000;
    status.accept(reading);
    if (!check(events.size() == 1 && events.last().value(QStringLiteral("state")).toString() == QStringLiteral("mains")
            && events.last().value(QStringLiteral("detail")).toString().contains(QStringLiteral("1 ч 0 мин")),
            "Connecting the charger should show a rate-based estimate"))
        return 1;

    status.accept({});
    reading.percent = 100;
    reading.charging = false;
    status.accept(reading);
    status.accept(reading);
    if (!check(events.size() == 2 && events.last().value(QStringLiteral("state")).toString() == QStringLiteral("full"),
            "Full charge is reported once, even after an unavailable sample"))
        return 1;

    reading.ac = 0;
    reading.remainingSeconds = 8100;
    status.accept(reading);
    if (!check(events.size() == 3 && events.last().value(QStringLiteral("state")).toString() == QStringLiteral("battery"),
            "Unplugging should show the battery state"))
        return 1;

    reading.present = false;
    status.accept(reading);
    if (!check(events.size() == 3 && status.snapshot().value(QStringLiteral("state")).toString() == QStringLiteral("noBattery"),
            "Systems without a battery should remain silent"))
        return 1;
    return 0;
}
