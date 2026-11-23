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
    property Component backdropComponent: null
    signal dismissed(int eventId)

    readonly property bool eventActive: routed && allowed && !!event
    readonly property bool presenting: presentedEvent !== null
    readonly property bool withdrawing: exit.running
    readonly property bool topCenter: presentedPlacement === "top-center"
    readonly property bool bottomRight: presentedPlacement === "bottom-right"
    readonly property bool fromTaskbar: presentedPlacement === "bottom-center"
        && !presentedFullscreen && desktop.bottomTaskbarVisible
    readonly property rect targetArea: fullscreen ? desktop.screenArea : desktop.notificationWorkArea
    readonly property real margin: Math.max(0, Math.min(16, placementArea.width / 4, placementArea.height / 4))
    readonly property real availableWidth: Math.max(1, Math.min(bottomRight ? 480 : 620, placementArea.width - 2 * margin))
    readonly property real availableHeight: Math.max(1, placementArea.height - 2 * margin)
    readonly property real cardWidth: content.preferredWidth
    readonly property real cardHeight: content.preferredHeight
    readonly property color accent: presentedEvent?.accent ?? "#a4e7cc"
    readonly property var material: Material.read(appearance)
    readonly property var motionCurve: appearance.motionCurve
    readonly property bool springMotion: appearance.springMotion
    readonly property bool glass: material.enabled && surface.GraphicsInfo.api !== GraphicsInfo.Software
        && glassSurface.status !== ShaderEffect.Error

    property bool motionReady: false
    property var presentedEvent: null
    property string presentedPlacement: "top-center"
    property bool presentedFullscreen: false
    property rect placementArea: Qt.rect(0, 0, 0, 0)
    property real reveal: 0

    readonly property rect body: {
        // Use the dock's drop motion in coordinates where the attachment edge is at y=0.
        const home = bottomRight
            ? Qt.rect(height - margin - cardHeight, margin, cardHeight, cardWidth)
            : Qt.rect((width - cardWidth) / 2, margin, cardWidth, cardHeight)
        const drop = Geometry.playerFromEdge(home, 1 - reveal, 0, 0, springMotion)
        if (topCenter)
            return drop
        if (bottomRight)
            return Qt.rect(width - drop.y - drop.height, drop.x, drop.height, drop.width)
        return Qt.rect(drop.x, height - drop.y - drop.height, drop.width, drop.height)
    }
    readonly property real bodyRadius: Math.min(body.width / 2, body.height / 2,
        Geometry.mix(14, bottomRight ? 18 : 32, Motion.smooth(Geometry.phase(reveal, 0.35, 0.9))))
    readonly property real bodyOpacity: Motion.smooth(Geometry.phase(reveal, 0.04, 0.29))

    transientParent: null
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
        | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    color: "transparent"
    width: Math.min(placementArea.width, Math.ceil(cardWidth + 2 * margin))
    height: Math.min(placementArea.height, Math.ceil(cardHeight + 2 * margin))
    x: placementArea.x + Math.round(bottomRight ? placementArea.width - width : (placementArea.width - width) / 2)
    y: placementArea.y + (topCenter ? 0 : placementArea.height - height)
    // Keep the native window and the old event alive during the entire retreat.
    visible: width > 0 && height > 0 && presenting

    function updateRegion() {
        const visibleBody = visible && bodyOpacity > 0.001
        desktop.setNotificationRegion(overlay, visibleBody ? body : Qt.rect(0, 0, 0, 0),
            visibleBody ? bodyRadius : 0)
    }

    function textLayout() {
        return content.textLayout()
    }

    function openFromCurrentPosition() {
        exit.stop()
        enter.from = reveal
        enter.duration = Math.max(60, Math.round(980 * (1 - reveal)))
        enter.start()
    }

    function updatePresentation() {
        if (!motionReady)
            return
        const nextEvent = eventActive ? event : null
        if (presenting) {
            if (nextEvent && presentedEvent.eventId === nextEvent.eventId
                    && presentedPlacement === placement && presentedFullscreen === fullscreen) {
                presentedEvent = nextEvent
                if (withdrawing)
                    openFromCurrentPosition()
            } else if (!withdrawing) {
                enter.stop()
                exit.from = reveal
                exit.duration = Math.max(120, Math.round(650 * reveal))
                exit.start()
            }
        } else if (nextEvent && targetArea.width > 0 && targetArea.height > 0) {
            presentedPlacement = placement
            presentedFullscreen = fullscreen
            placementArea = targetArea
            reveal = 0
            presentedEvent = nextEvent
            openFromCurrentPosition()
        }
    }

    onEventActiveChanged: Qt.callLater(updatePresentation)
    onEventChanged: Qt.callLater(updatePresentation)
    onPlacementChanged: Qt.callLater(updatePresentation)
    onFullscreenChanged: Qt.callLater(updatePresentation)
    onTargetAreaChanged: {
        if (presenting && !withdrawing && targetArea.width > 0 && targetArea.height > 0
                && presentedPlacement === placement && presentedFullscreen === fullscreen)
            placementArea = targetArea
        Qt.callLater(updatePresentation)
    }
    onVisibleChanged: updateRegion()
    onBodyChanged: Qt.callLater(updateRegion)
    onBodyRadiusChanged: Qt.callLater(updateRegion)
    onBodyOpacityChanged: Qt.callLater(updateRegion)
    Component.onCompleted: {
        motionReady = true
        updateRegion()
        updatePresentation()
    }

    DockTransition {
        id: enter
        target: overlay
        property: "reveal"
        to: 1
        curve: overlay.motionCurve
        standardEasing: Easing.InOutSine
    }
    DockTransition {
        id: exit
        target: overlay
        property: "reveal"
        to: 0
        curve: overlay.motionCurve
        standardEasing: Easing.InOutSine
        onFinished: {
            overlay.presentedEvent = null
            overlay.updatePresentation()
        }
    }

    Item {
        id: surface
        anchors.fill: parent

        Item {
            id: backdropScene
            anchors.fill: parent
            Loader {
                id: backdrop
                anchors.fill: parent
                active: overlay.visible && overlay.glass && overlay.appearance.desktopGlass
                    && surface.GraphicsInfo.api === GraphicsInfo.Direct3D11 && !!overlay.backdropComponent
                sourceComponent: overlay.backdropComponent
                onLoaded: item.active = true
            }
        }
        ShaderEffectSource {
            id: glassBackdrop
            sourceItem: backdropScene
            hideSource: true
            live: backdrop.active
            visible: false
        }

        ShaderEffect {
            id: glassSurface
            anchors.fill: parent
            visible: overlay.glass
            opacity: overlay.bodyOpacity
            readonly property vector2d resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
            readonly property vector4d bodyRect: Qt.vector4d(overlay.body.x, overlay.body.y,
                overlay.body.width, overlay.body.height)
            readonly property vector2d inward: overlay.topCenter ? Qt.vector2d(0, 1)
                : overlay.bottomRight ? Qt.vector2d(-1, 0) : Qt.vector2d(0, -1)
            readonly property vector4d shape: Qt.vector4d(overlay.bodyRadius,
                1 - Motion.smooth(Geometry.phase(overlay.reveal, 0.32, 0.76)),
                overlay.material.refraction, overlay.material.blur)
            readonly property vector4d finish: Qt.vector4d(overlay.material.opacity, overlay.material.darkening,
                overlay.material.light, backdrop.item?.hasFrame ? 1 : 0)
            readonly property color accentColor: overlay.accent
            readonly property var scene: glassBackdrop
            fragmentShader: Qt.resolvedUrl("notification-glass.frag.qsb")
        }

        Rectangle {
            x: overlay.body.x
            y: overlay.body.y
            width: overlay.body.width
            height: overlay.body.height
            radius: overlay.bodyRadius
            opacity: overlay.bodyOpacity
            antialiasing: true
            visible: !overlay.glass
            border.color: Qt.alpha(overlay.accent, overlay.material.enabled ? 0.48 : 0.28)
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: overlay.material.enabled
                        ? Qt.alpha(Qt.tint("#243432", Qt.alpha(overlay.accent, 0.15 * overlay.material.light)),
                            0.70 + 0.24 * overlay.material.opacity)
                        : "#182724"
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha("#101b18", overlay.material.enabled ? 0.82 + 0.15 * overlay.material.opacity : 1)
                }
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: Math.max(0, parent.radius - 2)
                visible: overlay.material.enabled && width >= 4 && height >= 4
                color: "transparent"
                border.color: Qt.alpha("#d0eee2", Math.min(0.20, 0.10 * overlay.material.light))
                antialiasing: true
            }
        }

        Item {
            x: overlay.body.x
            y: overlay.body.y
            width: overlay.body.width
            height: overlay.body.height
            clip: true

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
                entrance: Geometry.phase(overlay.reveal, 0.44, 1)
                expansion: compactPopup ? 0 : 1
                detailProgress: expansion
                dismissible: overlay.eventActive && !overlay.withdrawing && overlay.reveal > 0.9
                motionCurve: overlay.motionCurve
                springMotion: overlay.springMotion
                onDismissed: eventId => overlay.dismissed(eventId)
            }
        }
    }
}
