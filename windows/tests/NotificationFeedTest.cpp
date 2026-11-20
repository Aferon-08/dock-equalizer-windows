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
    return 0;
}
