pragma ComponentBehavior: Bound
import QtQuick
import "DockGeometry.js" as Geometry
import "DockMaterial.js" as Material
import "MarkerMotion.js" as Motion

Item {
    id: queueLayer
    required property NotificationQueue queue
    required property var appearance
    required property rect frame
    required property rect badge
    required property rect counter
    required property bool hasFrame
    required property bool expanded
    required property bool available
    required property real viewportHeight
    property rect leftObstacle: Qt.rect(0, 0, 0, 0)
    property var backdropTexture: null
    property rect backdropBounds: Qt.rect(0, 0, 0, 0)
    property bool backdropHasFrame: false

    readonly property int diameter: 43
    readonly property int gap: 8
    readonly property int margin: 8
    readonly property bool springMotion: appearance.springMotion
    readonly property var material: Material.read(appearance)
    readonly property var transition: queue.handoff
    readonly property real progress: queue.progress
    readonly property bool presenting: available && (queue.recalls.length > 0 || pucks.length > 0 || !!transition)
    readonly property real requiredHeight: Math.max(
        queue.recalls.length > 0 ? slotRect(queue.recalls.length - 1).y + diameter + margin : 0,
        ...pucks.map(item => item.y + item.height + margin))
    property rect lastFrame: Qt.rect(0, 0, 0, 0)
    property rect lastBadge: Qt.rect(0, 0, 0, 0)
    property rect sourceBadge: Qt.rect(0, 0, 0, 0)
    property rect sourceCounter: Qt.rect(0, 0, 0, 0)
    property rect sourceRecall: Qt.rect(0, 0, 0, 0)
    property var pucks: []

    readonly property var regions: {
        if (!presenting)
            return []
        const result = []
        for (const item of pucks.concat([outgoing, incoming])) {
            if (item.visible && item.opacity > 0.04 && item.width > 0 && item.height > 0)
                result.push({box: item.shapeBounds, radius: item.cornerRadius * item.scale})
        }
        return result
    }

    visible: presenting

    onFrameChanged: rememberBounds()
    onBadgeChanged: rememberBounds()
    onHasFrameChanged: rememberBounds()
    onTransitionChanged: {
        if (!transition)
            return
        sourceBadge = badge
        sourceCounter = counter.width > 0 ? counter
            : Qt.rect(frame.x + frame.width - 76, badge.y + 5, 40, 28)
        const recall = pucks.find(item => item.event.eventId === transition.incoming?.eventId)
        sourceRecall = recall ? recall.shapeBounds
            : transition.recallIndex >= 0 ? slotRect(transition.recallIndex) : Qt.rect(0, 0, 0, 0)
    }
    Connections {
        target: queueLayer.queue
        function onRecallsChanged() { queueLayer.syncPucks() }
    }
    Component.onCompleted: {
        rememberBounds()
        syncPucks()
    }

    function rememberBounds() {
        if (hasFrame && frame.width > 0 && badge.width > 0) {
            lastFrame = frame
            lastBadge = badge
        }
    }

    function slotRect(index) {
        const home = (hasFrame || lastFrame.width <= 0) && frame.width > 0 ? frame : lastFrame
        const icon = (hasFrame || lastBadge.width <= 0) && badge.width > 0 ? badge : lastBadge
        const bodyLeft = home.width > 0 ? home.x : width / 2
        const head = Math.max(margin, icon.y + (icon.height - diameter) / 2)
        const count = Math.max(index + 1, queue.recalls.length)
        const length = count * diameter + (count - 1) * gap
        const right = bodyLeft - gap
        let left = expanded ? right - diameter : right - length
        let top = head
        const footprintWidth = expanded ? diameter : length
        const footprintHeight = expanded ? length : diameter
        const obstacle = leftObstacle
        if (obstacle.width > 0 && left < obstacle.x + obstacle.width && left + footprintWidth > obstacle.x
                && top < obstacle.y + obstacle.height && top + footprintHeight > obstacle.y)
            top = obstacle.y + obstacle.height + gap
        if (left < margin) {
            left = Math.min(Math.max(margin, bodyLeft), Math.max(margin, width - footprintWidth - margin))
            top = Math.max(top, home.y + home.height + gap)
        }
        top = Math.min(top, Math.max(margin, viewportHeight - footprintHeight - margin))
        return Qt.rect(expanded ? left : left + length - diameter - index * (diameter + gap),
            expanded ? top + index * (diameter + gap) : top, diameter, diameter)
    }

    function syncPucks() {
        const items = pucks.slice()
        queue.recalls.forEach((entry, index) => {
            let item = items.find(candidate => candidate.event.eventId === entry.event.eventId)
            if (!item) {
                item = puck.createObject(queueLayer, {event: entry.event, slot: index})
                if (!item)
                    return
                items.push(item)
            }
            item.slot = index
            item.present = true
        })
        for (const item of items) {
            if (!queue.recalls.some(entry => entry.event.eventId === item.event.eventId)) {
                if (queue.closeProgress >= 0.99
                        || (transition?.incoming?.eventId === item.event.eventId && transition.recallIndex >= 0))
                    item.visible = false
                item.present = false
            }
        }
        pucks = items
    }

    function forget(item) {
        pucks = pucks.filter(existing => existing !== item)
        item.destroy()
    }

    function glide(from, to, amount, stretch) {
        const settle = Geometry.recoil(Geometry.phase(amount, 0.72, 1), springMotion)
        const box = Geometry.mixRect(from, to, Motion.travel(amount) + 0.035 * settle)
        const arc = Math.pow(Math.sin(Math.PI * amount), 2)
        const pull = arc * stretch - 0.10 * settle
        return Qt.rect(box.x - box.width * pull / 2, box.y + box.height * pull / 3 - Math.min(box.y, 12) * arc,
            box.width * (1 + pull), box.height * (1 - pull * 0.65))
    }

    component Token: Item {
        id: token
        property var event: null
        property real cornerRadius: 13
        property real iconOpacity: 1
        property real labelOpacity: 0
        property string label: ""
        property real glassMix: 1
        readonly property color accent: event?.accent ?? "#a4e7cc"
        readonly property rect shapeBounds: Qt.rect(x + width * (1 - scale) / 2, y + height * (1 - scale) / 2,
            width * scale, height * scale)
        readonly property var material: queueLayer.material
        readonly property real lensAmount: material.enabled && GraphicsInfo.api !== GraphicsInfo.Software
            && glass.status !== ShaderEffect.Error ? glassMix : 0

        Rectangle {
            anchors.fill: parent
            radius: token.cornerRadius
            antialiasing: true
            opacity: 1 - token.lensAmount
            visible: opacity > 0.001
            border.color: Qt.alpha(token.accent, token.material.enabled ? 0.37 : 0.27)
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Qt.tint("#263936", Qt.alpha(token.accent, 0.13 * token.material.light)),
                        Geometry.mix(0.52, token.material.enabled ? 0.76 + 0.20 * token.material.opacity : 1, token.glassMix))
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha("#101b18", Geometry.mix(0.48,
                        token.material.enabled ? 0.85 + 0.13 * token.material.opacity : 1, token.glassMix))
                }
            }
        }
        ShaderEffect {
            id: glass
            anchors.fill: parent
            visible: opacity > 0.001
            opacity: token.lensAmount
            readonly property vector2d resolution: Qt.vector2d(Math.max(1, width), Math.max(1, height))
            readonly property vector4d bodyRect: Qt.vector4d(0, 0, width, height)
            readonly property vector2d inward: Qt.vector2d(0, 1)
            readonly property vector4d shape: Qt.vector4d(token.cornerRadius, 0,
                token.material.refraction, token.material.blur)
            readonly property vector4d finish: Qt.vector4d(token.material.opacity, token.material.darkening,
                token.material.light, queueLayer.backdropHasFrame ? 1 : 0)
            readonly property vector4d sceneUv: {
                const source = queueLayer.backdropBounds
                const box = token.shapeBounds
                const w = Math.max(1, source.width)
                const h = Math.max(1, source.height)
                return Qt.vector4d((box.x - source.x) / w, (box.y - source.y) / h, box.width / w, box.height / h)
            }
            readonly property color accentColor: token.accent
            readonly property var scene: queueLayer.backdropTexture
            fragmentShader: Qt.resolvedUrl("notification-glass.frag.qsb")
        }
        DockNotificationIcon {
            anchors.centerIn: parent
            tint: token.accent
            kind: token.event?.kind ?? "regular"
            charge: token.event?.charge ?? -1
            opacity: token.iconOpacity
        }
        Text {
            anchors.centerIn: parent
            text: token.label
            color: token.accent
            opacity: token.labelOpacity
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
    }

    Component {
        id: puck
        Token {
            id: recall
            required property int slot
            property bool present: false
            property point displacement: Qt.point(0, 0)
            readonly property rect home: queueLayer.slotRect(slot)
            readonly property bool leavingCard: queueLayer.transition?.archiveId === event?.eventId
                && queueLayer.progress < 0.43
            readonly property real exitDelay: 0.1 * Math.max(0, queueLayer.queue.recalls.length - 1 - slot)
            readonly property real retirement: Motion.smooth(Geometry.phase(queueLayer.queue.closeProgress,
                exitDelay, exitDelay + 0.78))
            property real shown: present && !leavingCard ? 1 : 0
            property real homeX: home.x
            property real homeY: home.y
            x: homeX + displacement.x + 13 * retirement
            y: homeY + displacement.y - 4 * retirement
            width: queueLayer.diameter
            height: width
            cornerRadius: width / 2
            opacity: shown * (1 - retirement)
            scale: Geometry.mix(0.70, 1, opacity)
            z: drag.pressed ? 2 : 0
            Accessible.role: Accessible.Button
            Accessible.name: event?.title ?? "Вернуть уведомление"
            Accessible.onPressAction: if (drag.enabled) queueLayer.queue.restore(event.eventId)

            Behavior on homeX {
                DockTransition { duration: 310; curve: queueLayer.appearance.motionCurve; standardEasing: Easing.InOutCubic }
            }
            Behavior on homeY {
                DockTransition { duration: 310; curve: queueLayer.appearance.motionCurve; standardEasing: Easing.InOutCubic }
            }
            Behavior on shown { DockTransition { duration: 160; curve: queueLayer.appearance.motionCurve } }
            Behavior on displacement {
                enabled: !drag.pressed
                DockTransition { duration: 180; curve: queueLayer.appearance.motionCurve; standardEasing: Easing.OutCubic }
            }
            onPresentChanged: {
                if (!present)
                    removal.start()
                else
                    removal.stop()
            }
            Timer {
                id: removal
                interval: 225
                onTriggered: queueLayer.forget(recall)
            }

            MouseArea {
                id: drag
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                enabled: recall.present && !recall.leavingCard && !queueLayer.queue.closing && recall.opacity > 0.65
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                property point start: Qt.point(0, 0)
                function delta(mouse) {
                    const at = mapToGlobal(mouse.x, mouse.y)
                    return Qt.point(at.x - start.x, at.y - start.y)
                }
                onPressed: mouse => { start = mapToGlobal(mouse.x, mouse.y) }
                onPositionChanged: mouse => {
                    if (pressed)
                        recall.displacement = delta(mouse)
                }
                onReleased: mouse => {
                    const move = delta(mouse)
                    const distance = Math.hypot(move.x, move.y)
                    if (distance >= 27)
                        queueLayer.queue.removeRecall(recall.event.eventId)
                    else {
                        recall.displacement = Qt.point(0, 0)
                        if (distance <= 7)
                            queueLayer.queue.restore(recall.event.eventId)
                    }
                }
                onCanceled: recall.displacement = Qt.point(0, 0)
            }
        }
    }

    Token {
        id: outgoing
        event: queueLayer.transition?.outgoing ?? null
        readonly property bool archive: (queueLayer.transition?.archiveId ?? 0) > 0
        readonly property real travel: Geometry.phase(queueLayer.progress, 0.15, 0.43)
        readonly property rect box: archive ? queueLayer.glide(queueLayer.sourceBadge, queueLayer.slotRect(0), travel, 0.18)
            : queueLayer.sourceBadge
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        z: 3
        cornerRadius: Geometry.mix(12, Math.min(width, height) / 2, travel)
        glassMix: archive ? Motion.smooth(travel / 0.72) : 0
        opacity: !event || !queueLayer.transition ? 0 : (1 - queueLayer.queue.iconAmount)
            * (1 - Motion.smooth(Geometry.phase(queueLayer.progress, archive ? 0.43 : 0.20, archive ? 0.55 : 0.38)))
        visible: opacity > 0.001
    }

    Token {
        id: incoming
        event: queueLayer.transition?.incoming ?? null
        readonly property bool fromRecall: (queueLayer.transition?.recallIndex ?? -1) >= 0
        readonly property real morph: fromRecall ? 1 : Motion.smooth(Geometry.phase(queueLayer.progress, 0.34, 0.54))
        readonly property real travel: Geometry.phase(queueLayer.progress, fromRecall ? 0.17 : 0.49, 0.86)
        readonly property real tileSize: Math.max(1, queueLayer.badge.width)
        readonly property rect atCounter: Qt.rect(queueLayer.sourceCounter.x + (queueLayer.sourceCounter.width - tileSize) / 2,
            queueLayer.sourceCounter.y + (queueLayer.sourceCounter.height - tileSize) / 2, tileSize, tileSize)
        readonly property rect box: queueLayer.glide(fromRecall ? queueLayer.sourceRecall
            : Geometry.mixRect(queueLayer.sourceCounter, atCounter, morph), queueLayer.badge, travel, 0.26)
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        z: 4
        cornerRadius: fromRecall ? Geometry.mix(queueLayer.diameter / 2, 13, travel) : Geometry.mix(14, 12, morph)
        glassMix: fromRecall ? 1 - Motion.smooth(Geometry.phase(travel, 0.6, 1))
            : 0.65 * morph * (1 - Motion.smooth(Geometry.phase(travel, 0.55, 1)))
        label: "+" + (queueLayer.transition?.counter ?? 0)
        labelOpacity: fromRecall || (queueLayer.transition?.counter ?? 0) === 0 ? 0 : 1 - morph
        iconOpacity: fromRecall ? 1 : Motion.smooth(Geometry.phase(queueLayer.progress, 0.40, 0.54))
        opacity: !event || !queueLayer.transition ? 0 : (fromRecall ? 1 : Motion.smooth(Geometry.phase(queueLayer.progress, 0.30, 0.40)))
            * (1 - Motion.smooth(Geometry.phase(queueLayer.progress, 0.85, 0.98)))
        visible: opacity > 0.001
    }
}
