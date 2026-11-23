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
    required property NotificationQueue queue
    required property var event
    required property var wifi
    required property var battery
    property Component backdropComponent: null
    signal dismissed(int eventId)

    readonly property bool eventActive: routed && allowed && !!event
    readonly property bool presenting: presentedEvent !== null
    readonly property bool withdrawing: exit.running || (presenting && !!queue.handoff && !queue.current)
    readonly property bool topCenter: presentedPlacement === "top-center"
    readonly property bool bottomRight: presentedPlacement === "bottom-right"
    readonly property bool fromTaskbar: presentedPlacement === "bottom-center"
        && !presentedFullscreen && desktop.bottomTaskbarVisible
    readonly property rect targetArea: fullscreen ? desktop.screenArea : desktop.notificationWorkArea
    readonly property real margin: Math.max(0, Math.min(16, placementArea.width / 4, placementArea.height / 4))
    readonly property real availableWidth: Math.max(1, Math.min(bottomRight ? 480 : 620,
        placementArea.width - 2 * margin, Math.max(330, placementArea.width - 2 * margin - (bottomRight ? 156 : 312))))
    readonly property real availableHeight: Math.max(1, placementArea.height - 2 * margin)
    readonly property real cardWidth: content.preferredWidth
    readonly property real cardHeight: content.preferredHeight
    readonly property color accent: presentedEvent?.accent ?? "#a4e7cc"
    readonly property var material: Material.read(appearance)
    readonly property var motionCurve: appearance.motionCurve
    readonly property bool springMotion: appearance.springMotion
    readonly property bool glass: material.enabled && surface.GraphicsInfo.api !== GraphicsInfo.Software
        && glassSurface.status !== ShaderEffect.Error
    readonly property bool queueHandoff: !!queue.handoff && !exit.running
        && presentedPlacement === placement && presentedFullscreen === fullscreen
    readonly property real queueAmount: queueHandoff ? queue.cardAmount
        : queue.foldedEventId === presentedEvent?.eventId ? 0 : 1
    readonly property real cardViewportWidth: Math.min(placementArea.width, Math.ceil(cardWidth + 2 * margin))
    readonly property real leftOffset: Math.round(bottomRight ? placementArea.width - cardViewportWidth
        : (placementArea.width - cardViewportWidth) / 2)
    readonly property real historyGutter: Math.min(leftOffset, 180)
    readonly property real contentX: layoutBody.x + (bottomRight ? layoutBody.width - cardWidth : (layoutBody.width - cardWidth) / 2)
    readonly property real contentY: layoutBody.y + (bottomRight ? layoutBody.height - cardHeight : (layoutBody.height - cardHeight) / 2)
    readonly property rect badgeBounds: inLayout(content.badgeRect)
    readonly property rect counterBounds: inLayout(content.counterRect)

    property bool motionReady: false
    property var presentedEvent: null
    property var sizeEvent: null
    property string presentedPlacement: "top-center"
    property bool presentedFullscreen: false
    property rect placementArea: Qt.rect(0, 0, 0, 0)
    property real reveal: 0

    readonly property rect layoutBody: {
        // Use the dock's drop motion in coordinates where the attachment edge is at y=0.
        const home = bottomRight
            ? Qt.rect(height - margin - cardHeight, margin, cardHeight, cardWidth)
            : Qt.rect((cardViewportWidth - cardWidth) / 2, margin, cardWidth, cardHeight)
        const drop = Geometry.playerFromEdge(home, presenting ? 1 - reveal : 0, 0, 0, springMotion)
        if (topCenter)
            return Qt.rect(historyGutter + drop.x, drop.y, drop.width, drop.height)
        if (bottomRight)
            return Qt.rect(width - drop.y - drop.height, drop.x, drop.height, drop.width)
        return Qt.rect(historyGutter + drop.x, height - drop.y - drop.height, drop.width, drop.height)
    }
    readonly property rect body: queueAmount > 0.001
        ? Geometry.mixRect(badgeBounds, layoutBody, queueAmount)
        : Qt.rect(badgeBounds.x, badgeBounds.y, 0, 0)
    readonly property real bodyRadius: Math.min(body.width / 2, body.height / 2,
        Geometry.mix(14, bottomRight ? 18 : 32, Motion.smooth(Geometry.phase(reveal, 0.35, 0.9)) * queueAmount))
    readonly property real bodyOpacity: presenting && body.width > 0 ? Motion.smooth(Geometry.phase(reveal, 0.04, 0.29)) : 0

    transientParent: null
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
        | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    color: "transparent"
    width: cardViewportWidth + historyGutter
    height: Math.min(placementArea.height, Math.ceil(cardHeight + 2 * margin))
    x: placementArea.x + leftOffset - historyGutter
    y: placementArea.y + (topCenter ? 0 : placementArea.height - height)
    // Keep the native window and the old event alive during the entire retreat.
    visible: width > 0 && height > 0 && (presenting || overlayQueue.presenting)

    function inLayout(rect) {
        return Qt.rect(contentX + rect.x, contentY + rect.y, rect.width, rect.height)
    }

    function updateRegion() {
        const visibleBody = visible && bodyOpacity > 0.001
        desktop.setNotificationRegion(overlay, visibleBody ? body : Qt.rect(0, 0, 0, 0),
            visibleBody ? bodyRadius : 0, overlayQueue.regions)
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
            if (!nextEvent && queue.foldedEventId === presentedEvent.eventId) {
                enter.stop()
                exit.stop()
                presentedEvent = null
                reveal = 0
            } else if (nextEvent && (presentedEvent.eventId === nextEvent.eventId || queueHandoff)
                    && presentedPlacement === placement && presentedFullscreen === fullscreen) {
                presentedEvent = nextEvent
                sizeEvent = nextEvent
                if (exit.running)
                    openFromCurrentPosition()
            } else if (!exit.running) {
                enter.stop()
                exit.from = reveal
                exit.duration = Math.max(120, Math.round(650 * reveal))
                exit.start()
            }
        } else if ((nextEvent || (routed && allowed && queue.recalls.length > 0))
                && targetArea.width > 0 && targetArea.height > 0) {
            presentedPlacement = placement
            presentedFullscreen = fullscreen
            placementArea = targetArea
            if (nextEvent) {
                reveal = queueHandoff ? 1 : 0
                presentedEvent = nextEvent
                sizeEvent = nextEvent
                if (!queueHandoff)
                    openFromCurrentPosition()
            }
        }
    }

    onEventActiveChanged: Qt.callLater(updatePresentation)
    onEventChanged: Qt.callLater(updatePresentation)
    onPlacementChanged: Qt.callLater(updatePresentation)
    onRoutedChanged: Qt.callLater(updatePresentation)
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
    Connections {
        target: overlay.queue
        function onRecallsChanged() { Qt.callLater(overlay.updatePresentation) }
    }
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
                active: overlay.presenting && overlay.visible && overlay.glass && overlay.appearance.desktopGlass
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
            visible: overlay.glass && overlay.bodyOpacity > 0.001
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
            visible: !overlay.glass && overlay.bodyOpacity > 0.001
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
            visible: overlay.bodyOpacity > 0.001

            DockNotificationContent {
                id: content
                x: overlay.contentX - parent.x
                y: overlay.contentY - parent.y
                width: overlay.cardWidth
                height: overlay.cardHeight
                event: overlay.presentedEvent ?? overlay.sizeEvent
                wifi: overlay.wifi
                battery: overlay.battery
                accent: overlay.accent
                availableWidth: overlay.availableWidth
                minimumWidth: overlay.bottomRight ? 296 : 330
                availableHeight: overlay.availableHeight
                toastLayout: overlay.bottomRight
                compactPopup: !toastLayout && (kind === "app" || kind === "regular" || availableHeight < 138)
                entrance: Math.min(Geometry.phase(overlay.reveal, 0.44, 1),
                    overlay.queueHandoff && overlay.queue.progress >= 0.43
                        ? Geometry.mix(0.30, 1, overlay.queueAmount) : 1)
                opacity: Motion.smooth(Geometry.phase(overlay.queueAmount, 0.06, 0.65))
                transform: Scale {
                    origin.x: content.badgeRect.x + content.badgeSize / 2
                    origin.y: content.badgeRect.y + content.badgeSize / 2
                    xScale: Geometry.mix(0.04, 1, overlay.queueAmount)
                    yScale: xScale
                }
                queuedCount: overlay.queue.displayedCount
                badgeVisibility: overlay.queueHandoff ? overlay.queue.iconAmount : 1
                counterVisibility: badgeVisibility
                expansion: compactPopup ? 0 : 1
                detailProgress: expansion
                dismissible: overlay.eventActive && !overlay.withdrawing && !overlay.queue.handoff && overlay.reveal > 0.9
                motionCurve: overlay.motionCurve
                springMotion: overlay.springMotion
                onDismissed: eventId => overlay.dismissed(eventId)
            }
        }

        NotificationQueueLayer {
            id: overlayQueue
            objectName: "separateNotificationQueue"
            anchors.fill: parent
            queue: overlay.queue
            appearance: overlay.appearance
            available: overlay.routed && overlay.allowed
            hasFrame: overlay.presenting && overlay.reveal > 0.88 && !exit.running
            frame: overlay.layoutBody
            badge: overlay.badgeBounds
            counter: overlay.counterBounds
            expanded: content.expansion > 0.6
            viewportHeight: height
            onRegionsChanged: Qt.callLater(overlay.updateRegion)
        }
    }
}
