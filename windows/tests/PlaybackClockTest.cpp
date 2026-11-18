#include "../PlaybackClock.h"

#include <cstdio>

int main()
{
    PlaybackClock clock;
    TimelineSample sample{true, true, 10, 120, 1, 0.25, 50, 1000};
    bool ok = true;
    const auto expect = [&](const char *description, double time, double expected) {
        const double actual = clock.positionAt(static_cast<std::int64_t>(time));
        if (std::abs(actual - expected) > 0.001) {
            std::fprintf(stderr, "%s: got %.3f, expected %.3f\n", description, actual, expected);
            ok = false;
        }
    };

    clock.observe(sample, true);
    expect("advance from source timestamp", 2000, 11.25);

    sample.observedMs = 2000;
    clock.observe(sample, false);
    expect("identical report does not rewind", 3000, 12.25);

    sample.observedMs = 3000;
    sample.playing = false;
    clock.observe(sample, false);
    expect("pause with a stale report freezes the estimate", 5000, 12.25);

    sample.observedMs = 5000;
    sample.playing = true;
    sample.rate = 1.5;
    clock.observe(sample, false);
    expect("resume at a different rate", 7000, 15.25);

    sample.observedMs = 7000;
    sample.position = 0;
    sample.ageSeconds = 0;
    ++sample.sourceTimestamp;
    clock.observe(sample, false);
    expect("seek back to zero", 7000, 0);
    expect("clamp to track duration", 100000, 120);

    sample.observedMs = 9000;
    clock.observe(sample, true);
    expect("new track resets even with the same report", 9000, 0);
    clock.observe({}, true);
    expect("disconnect clears the timeline", 10000, 0);
    return ok ? 0 : 1;
}
