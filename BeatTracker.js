.pragma library

const MIN_PERIOD = 60000 / 210
const MAX_PERIOD = 60000 / 55

function clamp(value, low, high) {
    return Math.min(high, Math.max(low, value))
}

function follow(value, target, dt, attack, release) {
    const time = target > value ? attack : release
    return value + (target - value) * -Math.expm1(-dt / time)
}

function phaseDifference(target, phase) {
    const offset = target - phase
    return offset - Math.round(offset)
}

function reset() {
    return { at: 0, spectrum: Array(32).fill(0), baseline: 0, recentFlux: 0,
        onsetAt: 0, onset: 0, accentAt: 0, energy: 0,
        interval: 0, repeats: 0, period: 0, matchedAt: 0, quality: 0,
        bpm: 0, phase: 0, correction: 0, confidence: 0 }
}

function reading(s) {
    return { at: s.at, bpm: s.bpm, phase: s.phase, confidence: s.confidence,
        beat: s.confidence * Math.exp(-s.phase * 5.8),
        onset: s.onset, energy: s.energy }
}

function observeAccent(s, at) {
    const interval = s.accentAt ? at - s.accentAt : 0
    s.accentAt = at
    // A frame is about 33 ms. Allow that quantization when following a grid.
    if (interval >= MIN_PERIOD - 24 && interval <= MAX_PERIOD + 24) {
        if (Math.abs(interval - s.interval) <= Math.max(54, s.interval * .10)) {
            s.interval += (interval - s.interval) * .32
            s.repeats = Math.min(8, s.repeats + 1)
        } else {
            s.interval = interval
            s.repeats = 1
        }
    } else {
        s.interval = 0
        s.repeats = 0
    }

    if (s.repeats) {
        const ratio = s.period ? s.interval / s.period : 1
        const related = Math.abs(ratio - .5) < .09 || Math.abs(ratio - 2) < .16
        const required = s.period ? (related ? 6 : 4) : 3
        if (s.repeats >= required && (!s.period || Math.abs(ratio - 1) > .12)) {
            s.period = clamp(s.interval, MIN_PERIOD, MAX_PERIOD)
            s.matchedAt = at
            s.quality = .76
            if (!s.bpm) {
                s.bpm = 60000 / s.period
                s.phase = 0
            }
            s.correction = phaseDifference(0, s.phase)
            return
        }
    }

    if (!s.period) return
    const gap = at - s.matchedAt
    const beats = Math.round(gap / s.period)
    if (beats < 1 || beats > 3) return
    const tolerance = Math.max(60, s.period * .14)
    const error = Math.abs(gap - beats * s.period)
    if (error > tolerance) return
    // An offbeat does not move the grid. A missing accent may span a
    // whole pulse, so allow integer steps when the next onset still fits.
    const measured = clamp(gap / beats, MIN_PERIOD, MAX_PERIOD)
    s.period += (measured - s.period) * (beats === 1 ? .22 : .10)
    s.matchedAt = at
    s.quality += (1 - .55 * error / tolerance - .05 * (beats - 1) - s.quality) * .24
    s.correction = phaseDifference(0, s.phase)
}

function update(s, bands, at, audible) {
    const dt = s.at ? clamp(at - s.at, 0, 250) : 1000 / 30
    const advance = dt * s.bpm / 60000
    const correction = clamp(s.correction * -Math.expm1(-dt / 180), -advance * .24, advance * .24)
    s.phase = (s.phase + advance + correction) % 1
    s.correction -= correction
    s.at = at

    let flux = 0
    let power = 0
    for (let i = 0; i < 32; i++) {
        // CAVA stereo puts the low bins next to each other in the middle.
        const amplitude = audible ? Math.max(bands[31 - i] || 0, bands[32 + i] || 0) : 0
        const compressed = Math.log1p(amplitude / 16)
        const weight = i < 8 ? 2.5 : i < 23 ? 1 : .55
        flux += Math.max(0, compressed - s.spectrum[i]) * weight
        power += amplitude * amplitude
        s.spectrum[i] = compressed
    }
    flux /= 40
    const rms = Math.sqrt(power / 32)
    s.energy = follow(s.energy, rms / (rms + 22), dt, 110, 390)
    s.recentFlux = Math.max(flux, s.recentFlux * Math.exp(-dt / 1500))
    s.onset *= Math.exp(-dt / 125)
    if (flux > Math.max(.006, s.baseline * 2.2 + .0025) && at - s.onsetAt >= 140) {
        const strength = clamp(flux / Math.max(.018, s.recentFlux), 0, 1)
        s.onset = Math.max(s.onset, strength)
        s.onsetAt = at
        if (strength >= .40) observeAccent(s, at)
    }
    s.baseline = follow(s.baseline, flux, dt, 540, 1100)

    let trust = 0
    if (s.period) {
        const age = (at - s.matchedAt) / s.period
        trust = s.quality * clamp((3.2 - age) / 1.75, 0, 1)
        if (age > 4.6) {
            s.period = 0
            s.correction = 0
        } else {
            s.bpm = follow(s.bpm, 60000 / s.period, dt, 730, 790)
        }
    }
    s.confidence = follow(s.confidence, trust, dt, 290, 490)
    if (!s.period && s.confidence < .015) s.bpm = 0
    return reading(s)
}

function motionState(restBpm) {
    return { restBpm, bpm: restBpm, phase: 0, weight: 0, flash: 0, pulse: .32, energy: 0 }
}

function animate(motion, seconds, rhythm, at) {
    const dt = clamp(seconds, 0, .08) * 1000
    const fresh = rhythm && rhythm.at > 0 && Math.abs(at - rhythm.at) <= 260
    const confidence = fresh ? rhythm.confidence : 0
    const blend = clamp((confidence - .37) / .42, 0, 1)
    const target = blend * blend * (3 - 2 * blend)
    motion.weight = follow(motion.weight, target, dt, 420, 560)
    const bpm = fresh && rhythm.bpm > 0 ? rhythm.bpm : motion.restBpm
    motion.bpm = follow(motion.bpm, motion.restBpm + motion.weight * (bpm - motion.restBpm), dt, 570, 660)

    const advance = dt * motion.bpm / 60000
    let correction = 0
    if (fresh && target > 0) {
        const phase = (rhythm.phase + Math.max(0, at - rhythm.at) * rhythm.bpm / 60000) % 1
        const error = phaseDifference(phase, (motion.phase + advance) % 1)
        correction = clamp(error * target * dt / 420, -advance * .26, advance * .26)
    }
    motion.phase = (motion.phase + advance + correction) % 1
    const breathing = .32 + .13 * Math.cos(motion.phase * Math.PI * 2)
    const heartbeat = Math.exp(-Math.pow((motion.phase - .1) / .065, 2))
        + .45 * Math.exp(-Math.pow((motion.phase - .31) / .08, 2))
    motion.pulse = breathing + (heartbeat - breathing) * motion.weight
    const flash = fresh ? motion.weight * (rhythm.beat * .86 + rhythm.onset * .14) : 0
    motion.flash = follow(motion.flash, flash, dt, 45, 165)
    motion.energy = follow(motion.energy, fresh ? rhythm.energy : 0, dt, 150, 400)
    return motion
}
