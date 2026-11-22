.pragma library
.import "MarkerMotion.js" as Motion

function mix(from, to, amount) {
    return from + (to - from) * amount
}

function mixRect(from, to, amount) {
    return Qt.rect(mix(from.x, to.x, amount), mix(from.y, to.y, amount),
        mix(from.width, to.width, amount), mix(from.height, to.height, amount))
}

function taper(progress) {
    return Motion.smooth((progress - 0.42) / 0.26)
}

function recoil(progress, springMotion = true) {
    if (!springMotion)
        return 0
    const phase = Motion.clamp(progress, 0, 1)
    return Math.sin(2.85 * Math.PI * phase) * Math.pow(1 - phase, 1.8)
}

function phase(progress, start, end) {
    return Motion.clamp((progress - start) / (end - start), 0, 1)
}

function arrival(progress, spring) {
    return Motion.travel(progress / 0.79) + spring * recoil(phase(progress, 0.67, 1))
}

function settleHousing(rect, progress, springMotion) {
    const bounce = recoil(phase(progress, 0.86, 1), springMotion)
    return Qt.rect(rect.x - 8 * bounce, rect.y + 5 * bounce,
        rect.width + 16 * bounce, rect.height + 4 * bounce)
}

function playerFromEdge(rect, hidden, offsetX, offsetY, springMotion) {
    const drop = pullToEdge(rect, hidden, offsetX, offsetY)
    const opening = 1 - hidden
    const contact = Motion.smooth(phase(opening, 0.26, 0.42))
        * (1 - Motion.smooth(phase(opening, 0.66, 0.92)))
    const roof = mix(drop.y, Math.min(-6, drop.y), contact)
    return settleHousing(Qt.rect(drop.x, roof, drop.width, drop.height + drop.y - roof), opening, springMotion)
}

function pullToEdge(rect, progress, offsetX, offsetY) {
    const shrink = Motion.smooth((progress - 0.08) / 0.53)
    const pull = Motion.smooth((progress - 0.49) / 0.51)
    const width = mix(rect.width, 22, shrink)
    const height = mix(rect.height, 25, shrink) + 8 * taper(progress)
    const centerX = rect.x + rect.width / 2 + offsetX * (1 - shrink)
    const centerY = mix(rect.y + rect.height / 2 + offsetY, 18, shrink) - 55 * pull
    return Qt.rect(centerX - width / 2, centerY - height / 2, width, height)
}
