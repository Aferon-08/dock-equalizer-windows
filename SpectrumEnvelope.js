.pragma library

const BASE_GAIN = 2.8

function reset() {
    return { at: 0, peak: 0, gain: BASE_GAIN, levels: [] }
}

function clamp(value, min, max) {
    return Math.min(max, Math.max(min, value))
}

function follow(previous, target, elapsed, attack, release) {
    const timeConstant = target > previous ? attack : release
    return previous + (target - previous) * -Math.expm1(-elapsed / timeConstant)
}

function update(state, input, stamp) {
    const elapsed = state.at ? clamp(stamp - state.at, 0, 250) : 1000 / 30
    state.at = stamp

    const peak = Math.max(0, ...input)
    const gatePosition = clamp((peak - 1.5) / 2, 0, 1)
    const gate = gatePosition * gatePosition * (3 - 2 * gatePosition)
    state.peak = follow(state.peak, peak, elapsed, 95, 1450)
    // The gain falls quickly after a loud entrance and rises slowly in a
    // quiet passage. A closed gate never teaches it to amplify silence.
    const targetGain = gatePosition > 0.5 ? clamp(280 / Math.max(1, state.peak), 0.65, 5.5) : BASE_GAIN
    state.gain = follow(state.gain, targetGain, elapsed, 1600, 130)

    const drive = []
    const bands = []
    const attack = -Math.expm1(-elapsed / 48)
    const release = -Math.expm1(-elapsed / 145)
    for (let i = 0; i < input.length; i++) {
        const amplified = Math.max(0, input[i] - 0.7) * gate * state.gain
        // Keep a soft knee on transients while gain is still adapting.
        const target = amplified <= 520 ? amplified : 520 - 480 * Math.expm1((520 - amplified) / 480)
        const previous = state.levels[i] || 0
        const level = previous + (target - previous) * (target > previous ? attack : release)
        state.levels[i] = target === 0 && level < 0.5 ? 0 : level
        drive.push(target)
        bands.push(Math.round(state.levels[i]))
    }
    return { bands, drive, audible: gatePosition > 0.5 }
}
