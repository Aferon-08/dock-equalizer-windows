import QtQuick
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

Matrix4x4 {
    id: motion
    required property Item part
    required property bool tucking
    required property point destination
    property point pivot: Qt.point(part.width / 2, part.height / 2)
    property point restingCenter: Qt.point(part.x + pivot.x, part.y + pivot.y)
    property size tuckedScale: Qt.size(0.20, 0.38)
    property real arc: 0
    property real tilt: 0
    property int tuckDelay: 0
    property int tuckDuration: 620
    property int tuckEasing: Easing.InOutCubic
    property int returnDelay: 130
    property int returnDuration: 620
    property real spring: 1.1
    property real entrance: 1
    property rect entranceBounds: Qt.rect(0, 0, 1, 1)
    property size entranceSurface: Qt.size(1, 1)
    property point entranceSlot: Qt.point(0, 0.44)
    property size entranceScale: Qt.size(0.35, 0.28)
    property real entranceDelay: 0
    property real entranceEnd: 1
    property real unfold: 1

    property real progress: 0
    property bool ready: false
    readonly property real alpha: 1 - Motion.smooth((progress - 0.68) / 0.30)
    readonly property real entrancePhase: Geometry.phase(entrance, entranceDelay, entranceEnd)
    readonly property real entranceOpacity: Motion.smooth(entrancePhase / 0.43) * Motion.smooth(unfold / 0.65)
    readonly property real entranceTravel: Geometry.arrival(entrancePhase, 0.23)
    readonly property size edgeScale: {
        if (entrance === 1)
            return Qt.size(1, 1)
        const fitX = Math.min(1, entranceBounds.width / entranceSurface.width)
        const fitY = Math.min(1, entranceBounds.height / entranceSurface.height)
        return Qt.size(Geometry.mix(Math.min(fitX, entranceScale.width), fitX, entranceTravel),
            Geometry.mix(Math.min(fitY, entranceScale.height), fitY, entranceTravel))
    }
    readonly property point edgeOffset: {
        if (entrance === 1)
            return Qt.point(0, 0)
        const packedX = entranceBounds.x + entranceBounds.width * (0.5 + entranceSlot.x)
        const packedY = entranceBounds.y + entranceBounds.height * entranceSlot.y
            - 17 * (1 - Motion.smooth(entrancePhase / 0.37))
        // Unfold into the moving surface, even while the rest layout is wider than the drop.
        const targetX = entranceBounds.x + entranceBounds.width * restingCenter.x / entranceSurface.width
        const targetY = entranceBounds.y + entranceBounds.height * restingCenter.y / entranceSurface.height
        return Qt.point(Geometry.mix(packedX, targetX, entranceTravel) - restingCenter.x,
            Geometry.mix(packedY, targetY, entranceTravel) - restingCenter.y)
    }

    onTuckingChanged: {
        if (!ready)
            return
        const current = progress
        const target = tucking ? 1 : 0
        flight.stop()
        if (current === target)
            return
        delay.duration = tucking ? tuckDelay : returnDelay
        movement.duration = tucking ? tuckDuration : returnDuration
        movement.easing.type = tucking ? tuckEasing : Easing.OutBack
        movement.from = current
        movement.to = target
        flight.start()
    }
    Component.onCompleted: {
        progress = tucking ? 1 : 0
        ready = true
    }
    property SequentialAnimation flightAnimation: SequentialAnimation {
        id: flight
        PauseAnimation { id: delay }
        NumberAnimation {
            id: movement
            target: motion
            property: "progress"
            easing.overshoot: motion.spring
        }
    }

    matrix: {
        // Negative progress on return carries the travelling part past its rest point.
        const arch = Math.sin(Math.PI * progress)
        const angle = arch * tilt * Math.PI / 180
        const release = Geometry.arrival(unfold, 0.24)
        const sx = Geometry.mix(1, tuckedScale.width, progress) * edgeScale.width * Geometry.mix(0.82, 1, release)
        const sy = Geometry.mix(1, tuckedScale.height, progress) * edgeScale.height * Geometry.mix(0.79, 1, release)
        const a = Math.cos(angle) * sx
        const b = -Math.sin(angle) * sy
        const c = Math.sin(angle) * sx
        const d = Math.cos(angle) * sy
        const x = (destination.x - restingCenter.x) * progress + pivot.x - a * pivot.x - b * pivot.y
            + edgeOffset.x
        const y = (destination.y - restingCenter.y) * progress + arc * arch + pivot.y - c * pivot.x - d * pivot.y
            + edgeOffset.y - 9 * (1 - release)
        return Qt.matrix4x4(a, b, 0, x, c, d, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
    }
}
