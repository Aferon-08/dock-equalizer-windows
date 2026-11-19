import QtQuick

QtObject {
    id: root
    required property bool playing
    required property bool holdOpen
    required property bool fullscreen
    property int hideDelay: 600

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
        motion.duration = Math.max(1, Math.round(450 * Math.abs(target - current)))
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
            delay.restart()
        }
    }

    property Timer delay: Timer {
        interval: root.hideDelay
        onTriggered: root.animateTo(1)
    }
    property NumberAnimation motion: NumberAnimation {
        target: root
        property: "hideProgress"
    }
    onWantedChanged: update()
    onFullscreenChanged: update()
    Component.onCompleted: {
        ready = true
        update()
    }
}
