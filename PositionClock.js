.pragma library

function start(epoch, stamp, playback, rate) {
    return { epoch, anchor: 0, at: stamp, playback, rate, known: false, source: "waiting",
        pending: null, seekUntil: 0, ignoredZeros: 0, seekRevision: 0 }
}

function estimate(s, stamp) {
    const elapsed = s.playback === "playing" ? Math.max(0, stamp - s.at) / 1000 : 0
    return s.anchor + elapsed * s.rate
}

function playbackChanged(s, playback, rate, stamp) {
    if (s.playback === playback && s.rate === rate) return s
    const stopped = playback === "stopped" || playback === "absent"
    return Object.assign({}, s, { at: stamp, anchor: stopped ? 0 : estimate(s, stamp),
        playback, rate, pending: null, seekUntil: 0 })
}

function seek(s, seconds, stamp, local) {
    if (!Number.isFinite(seconds) || seconds < 0) return s
    return Object.assign({}, s, { anchor: seconds, at: stamp, known: true, pending: null,
        source: local ? "control" : "seeked", seekUntil: stamp + (local ? 1450 : 700),
        seekRevision: s.seekRevision + 1 })
}

function observe(s, seconds, stamp, source, epoch) {
    if (epoch !== s.epoch || !Number.isFinite(seconds) || seconds < 0 || s.playback === "stopped")
        return s
    if (!s.known)
        return Object.assign({}, s, { anchor: seconds, at: stamp, known: true, source })

    const predicted = estimate(s, stamp)
    if (seconds < .05 && predicted > 1.3)
        return Object.assign({}, s, { ignoredZeros: s.ignoredZeros + 1, pending: null })

    const delta = seconds - predicted
    if (Math.abs(delta) <= .6) {
        // Late/coarse updates must not wind back a steadily playing clock.
        const anchor = s.playback === "playing" ? predicted + Math.max(0, delta) * .3 : seconds
        return Object.assign({}, s, { anchor, at: stamp, source, pending: null,
            seekUntil: Math.abs(delta) < .25 ? 0 : s.seekUntil })
    }
    if (stamp < s.seekUntil) return s

    // Fallback for a player that moved without sending Seeked. Repeated
    // stale positions and a single delayed reply cannot start another epoch.
    const previous = s.pending
    if (previous && Math.abs(seconds - previous.seconds) < .002)
        return s
    const rate = s.playback === "playing" ? s.rate : 0
    const consistent = previous && Math.abs(seconds - previous.seconds - (stamp - previous.at) * rate / 1000) < .38
    const pending = { seconds, at: stamp, since: consistent ? previous.since : stamp,
        count: consistent ? previous.count + 1 : 1 }
    if (pending.count >= 3 && stamp - pending.since >= 1100)
        return Object.assign({}, seek(s, seconds, stamp, false), { source: "confirmed-position" })
    return Object.assign({}, s, { pending })
}
