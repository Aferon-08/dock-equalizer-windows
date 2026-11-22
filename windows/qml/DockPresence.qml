import QtQuick

QtObject {
    id: root
    required property bool playing
    required property bool paused
    required property bool dismissed
    required property bool holdOpen
    required property bool fullscreen
    required property var motionCurve
    property int idleDelay: 600
    property int pauseDelay: 60000

    property real hideProgress: 1
    readonly property bool wanted: playing || holdOpen
    readonly property bool showing: !fullscreen && (wanted || hideProgress < 1)
    readonly property bool interactive: showing && hideProgress === 0
    property bool ready: false

    function animateTo(target) {
        const current = hideProgress
        motion.stop()
        if (current === target)
            return
        motion.from = current
        motion.to = target
        motion.duration = Math.max(1, Math.round((target === 0 ? 1080 : 450) * Math.abs(target - current)))
        motion.start()
    }

    function update() {
        if (!ready)
            return
        delay.stop()
        if (fullscreen) {
            motion.stop()
            hideProgress = 1
        } else if (wanted) {
            animateTo(0)
        } else if (hideProgress < 1 && !(motion.running && motion.to === 1)) {
            if (dismissed)
                animateTo(1)
            else
                delay.restart()
        }
    }

    property Timer delay: Timer {
        interval: root.paused ? root.pauseDelay : root.idleDelay
        onTriggered: root.animateTo(1)
    }
    property DockTransition motion: DockTransition {
        target: root
        property: "hideProgress"
        curve: root.motionCurve
    }
    onWantedChanged: update()
    onPausedChanged: update()
    onDismissedChanged: update()
    onFullscreenChanged: update()
    Component.onCompleted: {
        ready = true
        update()
    }
}
