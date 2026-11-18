import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const tracker = vm.createContext({})
const source = fs.readFileSync(new URL("../BeatTracker.js", import.meta.url), "utf8")
vm.runInContext(source.replace(/^\.pragma.*$/m, ""), tracker)

function kick(t, channel=0, size=150) {
    return {t, bins: channel === 0 ? [29, 30, 31] : [32, 33, 34], size}
}

function kicks(from, to, period, channel) {
    const events = []
    for (let t = from; t < to; t += period) events.push(kick(t, channel))
    return events
}

function simulate(events, until, fixedBands=null) {
    const steps = [27, 39, 31, 34, 28, 40]
    const state = tracker.reset()
    const samples = []
    let index = 0
    for (let at = 1000; at < until; at += steps[index++ % steps.length]) {
        const input = fixedBands ?? Array(64).fill(0)
        if (!fixedBands) {
            for (const event of events) {
                const age = at - event.t
                if (age >= 0 && age < 115) {
                    for (const bin of event.bins) input[bin] += event.size * Math.exp(-age / 39)
                }
            }
        }
        samples.push(tracker.update(state, input, at, input.some(v => v > 2.5)))
    }
    return samples
}

const tone = Array(64).fill(0)
tone[30] = 100
const held = simulate([], 7000, tone)
assert(held[0].onset > .7)
assert(held.at(-1).energy > .3)
assert.equal(held.at(-1).bpm, 0)
assert.equal(held.at(-1).beat, 0)
assert(held.at(-1).onset < .001, "One transient must not turn sustained energy into a beat")

for (const channel of [0, 1]) {
    const series = simulate(kicks(1200, 9000, 500, channel), 9000)
    assert(Math.abs(series.at(-1).bpm - 120) < 4)
    assert(series.at(-1).confidence > .78, "Either channel can supply equally strong bass")
}

const score = [
    ...kicks(1200, 8200, 500, 0).filter(event => event.t !== 5200),
    ...kicks(8200, 15800, 625, 1)
]
// The lighter treble notes happen halfway between the primary 120 BPM beats.
for (let t = 1450; t < 8200; t += 500) score.push({t, bins: [3, 4, 60, 61], size: 44})
const series = simulate(score, 19300)
const mixed = series.filter(sample => sample.at >= 3900 && sample.at <= 8150)
assert(mixed.every(sample => sample.bpm > 114 && sample.bpm < 126), "Offbeats and a skipped beat preserve the tempo")
assert(mixed.some(sample => sample.confidence > .8))
assert(series.some(sample => sample.at > 14500 && sample.at < 15500
    && Math.abs(sample.bpm - 96) < 4 && sample.confidence > .74), "The new tempo locks after repeated evidence")
const changes = series.filter(sample => sample.at > 3900 && sample.at < 15500)
const roundedJump = Math.max(...changes.slice(1).map((sample, i) => Math.abs(sample.bpm - changes[i].bpm)))
assert(roundedJump < 2, "A tempo transition eases the rate")
assert(series.at(-1).confidence < .08, "Long gaps release the beat lock")
assert(series.at(-1).energy < .01)

const irregular = simulate([1100, 1455, 2300, 2675, 3270, 4240, 4530, 5290, 5760, 6680, 7070, 7590]
    .map(t => kick(t)), 8000)
assert(irregular.some(sample => sample.onset > .6))
assert(irregular.every(sample => sample.confidence < .37), "Irregular accents leave breathing in charge")

const motion = tracker.motionState(44)
const locked = {bpm: 120, confidence: .92, onset: .8, beat: .6, energy: .4}
for (let at = 1000; at < 4100; at += 16) {
    const before = motion.phase
    tracker.animate(motion, .016, {...locked, at, phase: (at / 500) % 1}, at)
    const distance = (motion.phase - before + 1) % 1
    assert(distance <= .041, "Clock corrections may speed up the pulse without a phase jump")
}
assert(motion.weight > .96 && motion.bpm > 118 && motion.flash > .5)
for (let at = 4100; at < 8000; at += 16) {
    tracker.animate(motion, .016, {...locked, at, confidence: .24, phase: .9}, at)
}
assert(motion.weight < .01 && motion.bpm < 45 && motion.flash < .012)
assert(motion.pulse > .18 && motion.pulse < .46, "Weak confidence still produces gentle light")
tracker.animate(motion, .016, {...locked, at: 1000, phase: .6}, 8000)
assert(motion.weight < .01, "Old snapshots cannot restart the heartbeat")

console.log("PASS stereo bass, quiet breath, steady sync through offbeats, gentle tempo changes and silence")
