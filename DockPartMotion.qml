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

    property real progress: 0
    property bool ready: false
    readonly property real alpha: 1 - Motion.smooth((progress - 0.68) / 0.30)

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
        const sx = Geometry.mix(1, tuckedScale.width, progress)
        const sy = Geometry.mix(1, tuckedScale.height, progress)
        const a = Math.cos(angle) * sx
        const b = -Math.sin(angle) * sy
        const c = Math.sin(angle) * sx
        const d = Math.cos(angle) * sy
        const x = (destination.x - restingCenter.x) * progress + pivot.x - a * pivot.x - b * pivot.y
        const y = (destination.y - restingCenter.y) * progress + arc * arch + pivot.y - c * pivot.x - d * pivot.y
        return Qt.matrix4x4(a, b, 0, x, c, d, 0, y, 0, 0, 1, 0, 0, 0, 0, 1)
    }
}
