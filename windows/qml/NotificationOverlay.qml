import QtQuick
import "DockGeometry.js" as Geometry
import "DockMaterial.js" as Material
import "MarkerMotion.js" as Motion

Window {
    id: overlay
    objectName: "soundbarNotificationWindow"
    required property var desktop
    required property var appearance
    required property string placement
    required property bool routed
    required property bool fullscreen
    required property bool allowed
    required property var event
    required property var wifi
    required property var battery
    signal dismissed(int eventId)

    readonly property bool eventActive: routed && allowed && !!event
    readonly property bool topCenter: placement === "top-center"
    readonly property bool bottomRight: placement === "bottom-right"
    readonly property bool fromTaskbar: !topCenter && !bottomRight && !fullscreen && desktop.bottomTaskbarVisible
    readonly property rect placementArea: fullscreen ? desktop.screenArea : desktop.notificationWorkArea
    readonly property real margin: Math.max(0, Math.min(16, placementArea.width / 4, placementArea.height / 4))
    readonly property real availableWidth: Math.max(1, Math.min(bottomRight ? 480 : 620, placementArea.width - 2 * margin))
    readonly property real availableHeight: Math.max(1, placementArea.height - 2 * margin)
    readonly property real cardWidth: content.preferredWidth
    readonly property real cardHeight: content.preferredHeight
    readonly property color accent: presentedEvent?.accent ?? "#a4e7cc"
    readonly property var material: Material.read(appearance)
    readonly property var motionCurve: appearance.motionCurve
    readonly property bool springMotion: appearance.springMotion

    property bool motionReady: false
    property var presentedEvent: null
    property real reveal: 0

    // The visible contour also defines the native input region as the card opens and closes.
    readonly property real recoil: Geometry.recoil(Geometry.phase(reveal, 0.76, 1), springMotion)
    readonly property rect body: {
        const horizontal = Motion.smooth(Geometry.phase(reveal, fromTaskbar ? 0.13 : 0.04, 0.88))
        const vertical = Motion.smooth(Geometry.phase(reveal, 0.02, bottomRight ? 0.94 : 0.86))
        const bodyWidth = Geometry.mix(Math.min(14, cardWidth), cardWidth, horizontal) + Math.min(6, margin) * recoil
        const bodyHeight = Geometry.mix(Math.min(12, cardHeight), cardHeight, vertical) + Math.min(4, margin) * recoil
        const centerY = margin + cardHeight / 2 - bodyHeight / 2
        let left = (width - bodyWidth) / 2
        let top = centerY
        if (bottomRight) {
            left = width - margin - bodyWidth
            top = height - margin - bodyHeight
        } else if (fromTaskbar) {
            top = Geometry.mix(height - bodyHeight, centerY,
                Motion.smooth(Geometry.phase(reveal, 0.16, 0.78)))
        }
        return Qt.rect(left, top, bodyWidth, bodyHeight)
    }
    readonly property real bodyRadius: Math.min(body.width / 2, body.height / 2,
        Geometry.mix(7, bottomRight ? 18 : 32, Motion.smooth(Geometry.phase(reveal, 0.13, 0.86))))
    readonly property real bodyOpacity: Motion.smooth(Geometry.phase(reveal, 0.02, 0.44))

    transientParent: null
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
        | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    color: "transparent"
    width: Math.min(placementArea.width, Math.ceil(cardWidth + 2 * margin))
    height: Math.min(placementArea.height, Math.ceil(cardHeight + 2 * margin))
    x: placementArea.x + Math.round(bottomRight ? placementArea.width - width : (placementArea.width - width) / 2)
    y: placementArea.y + (topCenter ? 0 : placementArea.height - height)
    visible: width > 0 && height > 0 && routed && allowed && (!!event || (!!presentedEvent && reveal > 0))

    function updateRegion() {
        const visibleBody = visible && bodyOpacity > 0.001
        desktop.setNotificationRegion(overlay, visibleBody ? body : Qt.rect(0, 0, 0, 0),
            visibleBody ? bodyRadius : 0)
    }

    function textLayout() {
        return content.textLayout()
    }

    function animate(reset) {
        if (!motionReady)
            return
        enter.stop()
        exit.stop()
        if (eventActive) {
            presentedEvent = event
            if (reset)
                reveal = 0
            enter.from = reveal
            enter.start()
        } else if (routed && allowed && reveal > 0) {
            exit.from = reveal
            exit.start()
        } else {
            reveal = 0
            presentedEvent = null
        }
    }

    onEventActiveChanged: animate(false)
    onRoutedChanged: if (!routed) animate(false)
    onAllowedChanged: if (!allowed) animate(false)
    onPlacementChanged: if (eventActive) animate(true)
    onEventChanged: if (eventActive) presentedEvent = event
    onVisibleChanged: updateRegion()
    onBodyChanged: Qt.callLater(updateRegion)
    onBodyRadiusChanged: Qt.callLater(updateRegion)
    onBodyOpacityChanged: Qt.callLater(updateRegion)
    Component.onCompleted: {
        motionReady = true
        updateRegion()
        if (eventActive)
            animate(false)
    }

    DockTransition {
        id: enter
        target: overlay
        property: "reveal"
        to: 1
        duration: 880
        curve: overlay.motionCurve
        standardEasing: Easing.InOutCubic
    }
    DockTransition {
        id: exit
        target: overlay
        property: "reveal"
        to: 0
        duration: 530
        curve: overlay.motionCurve
        standardEasing: Easing.InOutCubic
        onFinished: if (!overlay.eventActive) overlay.presentedEvent = null
    }

    Rectangle {
        x: overlay.body.x
        y: overlay.body.y
        width: overlay.body.width
        height: overlay.body.height
        radius: overlay.bodyRadius
        opacity: overlay.bodyOpacity
        antialiasing: true
        clip: true
        border.color: Qt.alpha(overlay.accent, overlay.bottomRight ? 0.29 : 0.40)
        border.width: 1
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(Qt.tint("#182724", Qt.alpha(overlay.accent, 0.06 * overlay.material.light)),
                    overlay.material.enabled ? 0.82 + 0.16 * overlay.material.opacity : 1)
            }
            GradientStop {
                position: 1
                color: Qt.alpha("#101b18", overlay.material.enabled ? 0.91 + 0.08 * overlay.material.opacity : 1)
            }
        }

        DockNotificationContent {
            id: content
            x: overlay.bottomRight ? parent.width - width : (parent.width - width) / 2
            y: overlay.bottomRight ? parent.height - height : (parent.height - height) / 2
            width: overlay.cardWidth
            height: overlay.cardHeight
            event: overlay.presentedEvent
            wifi: overlay.wifi
            battery: overlay.battery
            accent: overlay.accent
            availableWidth: overlay.availableWidth
            minimumWidth: overlay.bottomRight ? 296 : 330
            availableHeight: overlay.availableHeight
            toastLayout: overlay.bottomRight
            compactPopup: !toastLayout && (kind === "app" || kind === "regular" || availableHeight < 138)
            entrance: Geometry.phase(overlay.reveal, 0.35, 1)
            expansion: compactPopup ? 0 : 1
            detailProgress: expansion
            dismissible: overlay.eventActive
            motionCurve: overlay.motionCurve
            springMotion: overlay.springMotion
            onDismissed: eventId => overlay.dismissed(eventId)
        }
    }
}
