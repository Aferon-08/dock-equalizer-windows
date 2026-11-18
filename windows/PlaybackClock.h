#pragma once

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>

struct TimelineSample
{
    bool valid = false;
    bool playing = false;
    double position = 0;
    double duration = 0;
    double rate = 1;
    double ageSeconds = 0;
    std::int64_t sourceTimestamp = 0;
    std::int64_t observedMs = 0;
};

inline std::int64_t playbackTimeMs()
{
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

class PlaybackClock
{
public:
    void observe(const TimelineSample &sample, bool newTrack)
    {
        if (!sample.valid) {
            *this = PlaybackClock{};
            return;
        }

        const bool sameReport = m_valid && !newTrack
            && sample.sourceTimestamp == m_sourceTimestamp && sample.position == m_sourcePosition;
        const double rate = std::isfinite(sample.rate) && sample.rate != 0
            ? std::clamp(sample.rate, -16.0, 16.0) : 1.0;

        // Players can publish play/pause changes without a new timeline.
        // Rebase on the previous estimate for that transition, preserving seeks
        // (including a seek to zero) when a fresh report actually arrives.
        m_anchor = sameReport ? positionAt(sample.observedMs)
            : sample.position + (sample.playing ? sample.ageSeconds * rate : 0);
        m_anchorMs = sample.observedMs;
        m_sourceTimestamp = sample.sourceTimestamp;
        m_sourcePosition = sample.position;
        m_duration = sample.duration;
        m_rate = sample.playing ? rate : 0;
        m_valid = true;
    }

    double positionAt(std::int64_t nowMs) const
    {
        const double elapsed = std::max<std::int64_t>(0, nowMs - m_anchorMs) / 1000.0;
        const double value = std::max(0.0, m_anchor + m_rate * elapsed);
        return m_duration > 0 ? std::min(value, m_duration) : value;
    }

private:
    bool m_valid = false;
    double m_anchor = 0;
    double m_sourcePosition = 0;
    double m_duration = 0;
    double m_rate = 0;
    std::int64_t m_anchorMs = 0;
    std::int64_t m_sourceTimestamp = 0;
};
