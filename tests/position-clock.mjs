import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const clock = vm.createContext({})
const source = fs.readFileSync(new URL("../PositionClock.js", import.meta.url), "utf8")
vm.runInContext(source.replace(/^\.pragma.*$/m, ""), clock)

let state = clock.start(1, 1000, "playing", 1)
state = clock.observe(state, 33, 1000, "mpris", 1)
for (let at = 1200; at < 2800; at += 250) {
    const next = clock.observe(state, 0, at, "mpris", 1)
    assert.equal(clock.estimate(next, at), clock.estimate(state, at))
    state = next
}
assert(state.ignoredZeros >= 6)
state = clock.observe(state, 34.9, 2950, "mpris", 1)
assert(clock.estimate(state, 2950) >= 34.95)

state = clock.seek(state, 0, 3000, false)
assert.equal(clock.estimate(state, 3000), 0)
assert.equal(clock.estimate(state, 3500), .5)
assert.equal(state.seekRevision, 1)
state = clock.playbackChanged(state, "paused", 1, 3500)
assert.equal(clock.estimate(state, 9900), .5)
state = clock.playbackChanged(state, "playing", 1.5, 10000)
assert.equal(clock.estimate(state, 11200), 2.3)

state = clock.start(2, 12000, "playing", 1)
assert.equal(clock.observe(state, 71, 12300, "mpris", 1), state)
state = clock.observe(state, 0, 12300, "mpris", 2)
assert.equal(clock.estimate(state, 12800), .5, "A verified new track can start from zero")

state = clock.seek(state, 22, 13000, true)
assert.equal(clock.observe(state, 110, 13500, "mpris", 2), state, "The old position cannot undo an optimistic seek")
state = clock.observe(state, 22.9, 13900, "mpris", 2)
for (let at = 14600; at < 17500; at += 700) state = clock.observe(state, 120, at, "mpris", 2)
assert(clock.estimate(state, 17500) < 27, "A fixed late observation must never be accepted")

state = clock.observe(state, 51, 18000, "mpris", 2)
state = clock.observe(state, 51.7, 18700, "mpris", 2)
state = clock.observe(state, 52.4, 19400, "mpris", 2)
assert.equal(state.source, "confirmed-position", "A coherent advancing position can recover a missing Seeked signal")
assert.equal(clock.estimate(state, 19500), 52.5)
console.log("PASS monotonic progress, temporary zeros, explicit seek, rates and epoch boundaries")
