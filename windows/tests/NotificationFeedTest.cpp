#include "DiscordNotificationProbe.h"
#include "NotificationFeed.h"

#include <cstdio>

int main()
{
    const auto check = [](bool condition, const char *message) {
        if (!condition)
            std::fprintf(stderr, "%s\n", message);
        return condition;
    };

    NotificationFeed feed;
    feed.reset(1000);
    if (!check(!feed.observe(1, 999), "An old notification should only seed the first snapshot")
        || !check(feed.observe(2, 1000), "The first new notification must be delivered")
        || !check(!feed.observe(2, 1000), "Duplicates in the same snapshot must be ignored"))
        return 1;
    feed.finish();

    if (!check(!feed.observe(1, 999) && !feed.observe(2, 1000), "Existing notifications must not be replayed")
        || !check(!feed.observe(4, 998), "The source can return older entries after its first snapshot")
        || !check(feed.observe(2, 1001), "A new notification can reuse an existing ID"))
        return 1;
    feed.finish();

    feed.reset(2000);
    if (!check(!feed.observe(2, 1001) && feed.observe(3, 2001), "Permission grants should start a new observation window"))
        return 1;

    const auto discord = QStringLiteral("com.squirrel.Discord.Discord");
    const auto packaged = QStringLiteral("OpaqueFamily!App");
    if (!check(DiscordNotificationProbe::source(discord, {}) == discord, "Discord's desktop ID should be visible in diagnostics")
        || !check(DiscordNotificationProbe::source(packaged, QStringLiteral("Discord PTB")) == packaged,
            "A recognized display name should preserve the Windows app ID")
        || !check(DiscordNotificationProbe::source(packaged, QStringLiteral("Incoming call from Discord")).isEmpty(),
            "Similar labels from other applications should not match the probe"))
        return 1;

    using Action = DiscordNotificationProbe::Action;
    DiscordNotificationProbe probe;
    if (!check(probe.observe({{1, 900, discord}}).isEmpty(), "Diagnostics should be opt-in"))
        return 1;
    probe.setActive(true);
    const auto baseline = probe.observe({{1, 900, discord}, {1, 900, discord}, {7, 700, {}}});
    if (!check(baseline.size() == 1 && baseline.first().action == Action::Present,
            "The baseline should distinguish existing entries from incoming ones and skip duplicates")
        || !check(probe.observe({{1, 900, {}}, {7, 700, {}}}).isEmpty(),
            "Temporary loss of source metadata should preserve known entries"))
        return 1;

    const auto change = probe.observe({{1, 1300, discord}, {7, 700, {}}});
    if (!check(change.size() == 2 && change.at(0).action == Action::Added && change.at(0).entry.createdAt == 1300
            && change.at(1).action == Action::Removed && change.at(1).entry.createdAt == 900,
            "Changed timestamps should distinguish a reused ID from the previous entry"))
        return 1;
    probe.setActive(false);
    if (!check(probe.observe({}).isEmpty(), "Stopping the probe should stop recording disappearances"))
        return 1;
    return 0;
}
