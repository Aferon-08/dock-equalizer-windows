import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const envelope = vm.createContext({})
const source = fs.readFileSync(new URL("../SpectrumEnvelope.js", import.meta.url), "utf8")
vm.runInContext(source.replace(/^\.pragma.*$/m, ""), envelope)

function frame(peak) {
    const bands = Array(64).fill(0)
    bands[10] = peak
    return bands
}

const state = envelope.reset()
for (let t = 1000; t < 5000; t += 33) {
    const noise = envelope.update(state, frame(1.4), t)
    assert.equal(noise.audible, false)
    assert.equal(Math.max(...noise.bands), 0)
}
assert.equal(state.gain, 2.8, "Noise must not wind up the gain")

let result
for (let t = 5000; t < 9000; t += 33) {
    result = envelope.update(state, frame(3.3), t)
}
assert(result.audible && result.bands[10] >= 11, "Quiet audio survives the floor")
assert(state.gain > 4 && state.gain <= 5.5, "Quiet boost is bounded")

const loud = envelope.update(state, frame(640), 9000)
assert(loud.bands[10] > 20 && loud.bands[10] < 650, "A loud attack should start without snapping to full scale")
for (let t = 9033; t < 10800; t += 33) {
    result = envelope.update(state, frame(640), t)
}
assert(state.gain >= 0.65 && state.gain < 1, "Loud audio brings the gain down")
assert(result.bands[10] > 300 && result.bands[10] < 500)

const released = envelope.update(state, frame(0), 10800)
assert.equal(released.audible, false)
assert(released.bands[10] > 0 && released.bands[10] < result.bands[10],
    "Signal loss is immediate while the envelope releases")
for (let t = 10833; t <= 12200; t += 33) {
    result = envelope.update(state, frame(0), t)
}
assert.equal(Math.max(...result.bands), 0, "Release reaches exact zero")

function simulate(stamps) {
    const stable = envelope.reset()
    stable.at = 1000
    stable.peak = 100
    let bands
    for (const stamp of stamps) {
        bands = envelope.update(stable, frame(100), 1000 + stamp).bands
    }
    return bands[10]
}

assert.equal(simulate([30, 60, 90, 120]), simulate([13, 19, 71, 120]),
    "Equal elapsed time gives the same attack with identical or jittered packets")
assert.equal(simulate([30, 60, 90, 120]), simulate([15, 30, 40, 55, 59, 88, 120]),
    "Packet count does not change the envelope")
console.log("PASS bounded gain, quiet audio, silent floor, attack and release under jitter")
