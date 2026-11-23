pragma ComponentBehavior: Bound
import QtQuick
import "DockGeometry.js" as Geometry
import "DockMaterial.js" as Material
import "MarkerMotion.js" as Motion

Item {
    id: layer
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
        for (const item of pucks) {
            if (item.visible && item.opacity > 0.05)
                result.push({box: Qt.rect(item.x, item.y, item.width, item.height), radius: diameter / 2})
        }
        for (const item of [outgoing, incoming]) {
            if (item.opacity > 0.04 && item.width > 0 && item.height > 0)
                result.push({box: Qt.rect(item.x, item.y, item.width, item.height), radius: item.cornerRadius})
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
        sourceRecall = recall ? Qt.rect(recall.x, recall.y, recall.width, recall.height)
            : transition.recallIndex >= 0 ? slotRect(transition.recallIndex) : Qt.rect(0, 0, 0, 0)
    }
    Connections {
        target: layer.queue
        function onRecallsChanged() { layer.syncPucks() }
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
                item = puck.createObject(layer, {event: entry.event, slot: index})
                if (!item)
                    return
                items.push(item)
            }
            item.slot = index
            item.present = true
        })
        for (const item of items) {
            if (!queue.recalls.some(entry => entry.event.eventId === item.event.eventId)) {
                if (transition?.incoming?.eventId === item.event.eventId && transition.recallIndex >= 0)
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
        const box = Geometry.mixRect(from, to, Motion.travel(amount) + 0.044 * settle)
        const pull = Math.sin(Math.PI * amount) * stretch
        return Qt.rect(box.x - box.width * pull / 2, box.y + box.height * pull / 3 - 9 * Math.sin(Math.PI * amount),
            box.width * (1 + pull), box.height * (1 - pull * 0.65))
    }

    component Token: Item {
        id: token
        property var event: null
        property real cornerRadius: 13
        property real iconOpacity: 1
        property real labelOpacity: 0
        property string label: ""
        readonly property color accent: event?.accent ?? "#a4e7cc"
        readonly property var finish: layer.material ?? Material.read(null)

        Rectangle {
            anchors.fill: parent
            radius: token.cornerRadius
            antialiasing: true
            border.color: Qt.alpha(token.accent, token.finish.enabled ? 0.48 : 0.27)
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Qt.tint("#263936", Qt.alpha(token.accent, 0.13 * token.finish.light)),
                        token.finish.enabled ? 0.76 + 0.20 * token.finish.opacity : 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha("#101b18", token.finish.enabled ? 0.85 + 0.13 * token.finish.opacity : 1)
                }
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                visible: width > 0 && height > 0 && token.finish.light > 0
                radius: Math.max(0, token.cornerRadius - 2)
                antialiasing: true
                color: "transparent"
                border.color: Qt.alpha("#e1f5ed", Math.min(0.19, 0.11 * token.finish.light))
            }
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
            readonly property rect home: layer.slotRect(slot)
            readonly property bool leavingCard: layer.transition?.archiveId === event?.eventId
                && layer.progress < 0.43
            property real homeX: home.x
            property real homeY: home.y
            x: homeX + displacement.x
            y: homeY + displacement.y
            width: layer.diameter
            height: width
            cornerRadius: width / 2
            opacity: present && !leavingCard ? 1 : 0
            scale: Geometry.mix(0.78, 1, opacity)
            z: drag.pressed ? 2 : 0
            Accessible.role: Accessible.Button
            Accessible.name: event?.title ?? "Вернуть уведомление"
            Accessible.onPressAction: if (present) layer.queue.restore(event.eventId)

            Behavior on homeX { DockTransition { duration: 310; curve: layer.appearance.motionCurve } }
            Behavior on homeY { DockTransition { duration: 310; curve: layer.appearance.motionCurve } }
            Behavior on opacity { DockTransition { duration: 190; curve: layer.appearance.motionCurve } }
            Behavior on displacement {
                enabled: !drag.pressed
                DockTransition { duration: 180; curve: layer.appearance.motionCurve; standardEasing: Easing.OutCubic }
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
                onTriggered: layer.forget(recall)
            }

            MouseArea {
                id: drag
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                enabled: recall.present && !recall.leavingCard && recall.opacity > 0.65
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
                        layer.queue.removeRecall(recall.event.eventId)
                    else {
                        recall.displacement = Qt.point(0, 0)
                        if (distance <= 7)
                            layer.queue.restore(recall.event.eventId)
                    }
                }
                onCanceled: recall.displacement = Qt.point(0, 0)
            }
        }
    }

    Token {
        id: outgoing
        event: layer.transition?.outgoing ?? null
        readonly property bool archive: (layer.transition?.archiveId ?? 0) > 0
        readonly property real travel: Geometry.phase(layer.progress, 0.20, 0.43)
        readonly property rect box: archive ? layer.glide(layer.sourceBadge, layer.slotRect(0), travel, 0.18)
            : layer.sourceBadge
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        z: 3
        cornerRadius: Geometry.mix(12, Math.min(width, height) / 2, travel)
        opacity: !event || !layer.transition ? 0 : archive
            ? 1 - Motion.smooth(Geometry.phase(layer.progress, 0.40, 0.47))
            : 1 - Motion.smooth(Geometry.phase(layer.progress, 0.19, 0.39))
        visible: opacity > 0.001
    }

    Token {
        id: incoming
        event: layer.transition?.incoming ?? null
        readonly property bool fromRecall: (layer.transition?.recallIndex ?? -1) >= 0
        readonly property real morph: fromRecall ? 1 : Motion.smooth(Geometry.phase(layer.progress, 0.43, 0.61))
        readonly property real travel: Geometry.phase(layer.progress, fromRecall ? 0.43 : 0.57, 0.86)
        readonly property real tileSize: Math.max(1, layer.badge.width)
        readonly property rect atCounter: Qt.rect(layer.sourceCounter.x + (layer.sourceCounter.width - tileSize) / 2,
            layer.sourceCounter.y + (layer.sourceCounter.height - tileSize) / 2, tileSize, tileSize)
        readonly property rect box: layer.glide(fromRecall ? layer.sourceRecall
            : Geometry.mixRect(layer.sourceCounter, atCounter, morph), layer.badge, travel, 0.26)
        x: box.x
        y: box.y
        width: box.width
        height: box.height
        z: 4
        cornerRadius: fromRecall ? Geometry.mix(layer.diameter / 2, 13, travel) : Geometry.mix(14, 12, morph)
        label: "+" + (layer.transition?.counter ?? 0)
        labelOpacity: fromRecall || (layer.transition?.counter ?? 0) === 0 ? 0 : 1 - morph
        iconOpacity: fromRecall ? 1 : Motion.smooth(Geometry.phase(layer.progress, 0.50, 0.63))
        opacity: !event || !layer.transition || (fromRecall && layer.progress < 0.43) ? 0
            : 1 - Motion.smooth(Geometry.phase(layer.progress, 0.92, 1))
        visible: opacity > 0.001
    }
}
