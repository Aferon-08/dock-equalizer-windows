.pragma library

var successTtl = 6 * 60 * 60 * 1000
var failureTtl = 15000
function eligible(entries, id, now, force) {
    return /^[A-Za-z0-9_-]{11}$/.test(id)
        && (force || !entries[id] || entries[id].expires <= now)
}
function remember(entries, id, seconds, now) {
    const updated = Object.assign({}, entries)
    const ok = Number.isFinite(seconds) && seconds > 0 && seconds <= 604800
    const previous = updated[id]
    delete updated[id] // Most recently completed requests go at the end.
    updated[id] = { seconds: ok ? seconds : previous ? previous.seconds : 0,
        expires: now + (ok ? successTtl : failureTtl), failed: !ok }
    const keys = Object.keys(updated)
    if (keys.length > 64) delete updated[keys[0]]
    return updated
}
