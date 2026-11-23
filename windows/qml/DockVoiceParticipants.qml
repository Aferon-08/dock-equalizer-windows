pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

Item {
    id: board

    required property var model
    required property var people
    required property string connectionStatus
    required property bool expanded
    required property var motionCurve
    required property bool springMotion
    required property color ink
    required property color mutedInk

    readonly property int count: people.length
    property real portraitMix: count < 4 ? 1 : 0
    property real pairTravel: count === 2 ? 1 : 0

    Component.onCompleted: portraitLayer.sync(people)
    onPeopleChanged: portraitLayer.sync(people)
    Behavior on portraitMix {
        DockTransition { duration: 350; curve: board.motionCurve; standardEasing: Easing.InOutCubic }
    }
    Behavior on pairTravel {
        DockTransition { duration: 360; curve: board.motionCurve; standardEasing: Easing.InOutCubic }
    }

    component ParticipantName: Text {
        color: board.ink
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        textFormat: Text.PlainText
        Layout.fillWidth: true
    }

    component ParticipantCaption: Text {
        color: board.mutedInk
        font.pixelSize: 12
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }

    component ParticipantAvatar: Item {
        id: avatarTile
        required property var avatar
        required property string name
        required property bool speaking

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#293044"
            antialiasing: true
        }

        Text {
            anchors.centerIn: parent
            visible: !avatarImage.loaded
            text: {
                const words = avatarTile.name.trim().split(/\s+/)
                const first = Array.from(words[0] ?? "")[0] ?? ""
                const last = words.length > 1 ? Array.from(words[words.length - 1])[0] ?? "" : ""
                return (first + last).toUpperCase()
            }
            color: board.ink
            font.pixelSize: Math.round(avatarTile.width * 0.39)
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
            Accessible.ignored: true
        }

        DiscordParticipantAvatar {
            id: avatarImage
            objectName: "discordParticipantAvatar"
            anchors.fill: parent
            anchors.margins: 2
            source: avatarTile.avatar
        }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: avatarTile.speaking ? 2 : 1
            border.color: avatarTile.speaking ? "#a4e7cc" : "#70968ab7"
            antialiasing: true
            Behavior on border.color {
                DockTransition { duration: 160; curve: board.motionCurve }
            }
        }
    }

    Component {
        id: portraitDelegate

        Item {
            id: portrait
            required property var participant
            required property int slot
            required property int slotCount
            property bool present: false
            property real appearance: present ? 1 : 0
            property real horizontalPosition: portraitLayer.slotPosition(slot, slotCount)

            objectName: "discordPortrait_" + participant.participantId
            width: Math.min(112, portraitLayer.width * 0.236)
            height: 65
            x: portraitLayer.width * horizontalPosition - width / 2
            y: 18
            opacity: Motion.smooth(Geometry.phase(appearance, 0.08, 0.98))
            scale: Geometry.mix(0.87, 1, appearance)
            visible: opacity > 0.001
            Accessible.role: Accessible.StaticText
            Accessible.name: participant.name
            Accessible.description: participant.status
            Accessible.ignored: !present || !portraitLayer.visible
            ToolTip.visible: portraitHover.hovered && portraitName.truncated
            ToolTip.delay: 450
            ToolTip.text: participant.name

            Behavior on horizontalPosition {
                DockTransition {
                    duration: 350
                    curve: board.motionCurve
                    standardEasing: Easing.InOutCubic
                    spring: board.springMotion ? 0.14 : 0
                }
            }
            Behavior on appearance {
                SequentialAnimation {
                    PauseAnimation { duration: portrait.present ? 28 * portrait.slot : 0 }
                    DockTransition {
                        duration: portrait.present ? 260 : 185
                        curve: board.motionCurve
                        standardEasing: Easing.OutCubic
                    }
                }
            }
            onAppearanceChanged: {
                if (!present && appearance <= 0)
                    portraitLayer.removePortrait(participant.participantId, portrait)
            }

            transform: Translate {
                x: (portrait.slot === 0 ? -7 : 7) * (1 - portrait.appearance)
                y: 3 * (1 - portrait.appearance)
            }

            ParticipantAvatar {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 44
                height: width
                avatar: portrait.participant.avatar
                name: portrait.participant.name
                speaking: portrait.participant.speaking
            }

            ParticipantName {
                id: portraitName
                y: 48
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 14
                text: portrait.participant.name
                Accessible.ignored: true
            }

            HoverHandler { id: portraitHover }
        }
    }

    Rectangle {
        anchors.fill: parent
        opacity: roster.opacity
        radius: 15
        color: "#20101919"
        border.color: "#32b8dacd"
    }

    ParticipantCaption {
        x: 10
        y: 4
        width: parent.width - 20
        horizontalAlignment: Text.AlignRight
        text: "Участники · " + board.count
    }

    Item {
        id: portraitLayer
        anchors.fill: parent
        opacity: Motion.smooth(Geometry.phase(board.portraitMix, 0.08, 0.78))
        visible: opacity > 0.001
        readonly property var portraits: new Map()

        function slotPosition(slot, count) {
            if (count === 1)
                return 0.5
            if (count === 2)
                return slot === 0 ? 0.27 : 0.73
            return 0.26 + 0.24 * slot
        }

        function sync(people) {
            const kept = new Set()
            const slots = Math.min(3, people.length)
            for (let slot = 0; slot < slots; ++slot) {
                const person = people[slot]
                const key = person.participantId
                let portrait = portraits.get(key)
                if (!portrait) {
                    portrait = portraitDelegate.createObject(portraitLayer,
                        {participant: person, slot: slot, slotCount: slots})
                    portraits.set(key, portrait)
                } else {
                    portrait.participant = person
                    portrait.slot = slot
                    portrait.slotCount = slots
                }
                portrait.present = true
                kept.add(key)
            }
            for (const [key, portrait] of portraits) {
                if (kept.has(key))
                    continue
                if (portrait.appearance <= 0)
                    removePortrait(key, portrait)
                else
                    portrait.present = false
            }
        }

        function removePortrait(key, portrait) {
            portraits.delete(key)
            portrait.destroy()
        }

        Item {
            id: pair
            objectName: "discordPairStatus"
            x: portraitLayer.width * 0.27 + 34
            y: 39
            width: Math.max(0, portraitLayer.width * 0.46 - 68)
            height: 29
            readonly property string statusText: {
                switch (board.connectionStatus) {
                case "connected": return "Соединён"
                case "connecting": return "Подключение…"
                case "disconnected": return "Не подключён"
                default: return "Статус недоступен"
                }
            }
            property real centerGap: board.connectionStatus === "disconnected" || board.connectionStatus === "connecting" ? 26 : 0
            property real connectingMix: board.connectionStatus === "connecting" ? 1 : 0
            property color lineColor: board.connectionStatus === "connected" ? "#a4e7cc"
                : board.connectionStatus === "disconnected" ? "#f0a0a8" : "#a4bdb5"
            property real pulse: 0

            opacity: Motion.smooth(Geometry.phase(board.pairTravel, 0.41, 0.97))
            visible: width > 0 && opacity > 0.001
            Behavior on centerGap {
                DockTransition { duration: 300; curve: board.motionCurve; standardEasing: Easing.InOutCubic }
            }
            Behavior on connectingMix {
                DockTransition { duration: 270; curve: board.motionCurve; standardEasing: Easing.InOutCubic }
            }
            Behavior on lineColor {
                DockTransition { duration: 300; curve: board.motionCurve }
            }
            NumberAnimation on pulse {
                from: 0
                to: 1
                duration: 1050
                loops: Animation.Infinite
                running: pair.visible && board.expanded && board.connectionStatus === "connecting"
            }

            Item {
                id: line
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * Motion.smooth(Geometry.phase(board.pairTravel, 0.51, 1))
                height: 2
                readonly property real segment: Math.max(0, (width - pair.centerGap) / 2)

                Rectangle {
                    width: line.segment
                    height: 2
                    radius: pair.centerGap > 0 ? 1 : 0
                    color: pair.lineColor
                    opacity: 1 - pair.connectingMix
                }
                Rectangle {
                    x: line.width - width
                    width: line.segment
                    height: 2
                    radius: pair.centerGap > 0 ? 1 : 0
                    color: pair.lineColor
                    opacity: 1 - pair.connectingMix
                }

                Shape {
                    anchors.fill: parent
                    opacity: pair.connectingMix
                    visible: opacity > 0.001
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: "#f3ce81"
                        strokeWidth: 2
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2, 2.5]
                        startY: 1
                        PathLine { x: line.segment; y: 1 }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: "#f3ce81"
                        strokeWidth: 2
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2, 2.5]
                        startX: line.width - line.segment
                        startY: 1
                        PathLine { x: line.width; y: 1 }
                    }
                }

                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        x: line.width / 2 + (index - 1) * 7 - width / 2
                        y: (line.height - height) / 2
                        width: 4
                        height: width
                        radius: width / 2
                        color: "#f3ce81"
                        opacity: pair.connectingMix
                            * (0.27 + 0.73 * Math.pow(0.5 + 0.5 * Math.cos(2 * Math.PI * (pair.pulse - index / 3)), 2))
                        visible: line.width >= 24 && opacity > 0.001
                    }
                }
            }

            ParticipantCaption {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: parent.width
                text: pair.statusText
                horizontalAlignment: Text.AlignHCenter
                color: Qt.tint(pair.lineColor, Qt.alpha("#f3ce81", pair.connectingMix))
                font.pixelSize: 11
            }
        }
    }

    GridView {
        id: roster
        objectName: "discordParticipantList"
        x: 10
        y: 22
        width: parent.width - 20
        height: parent.height - y - 7
        visible: opacity > 0.001
        opacity: 1 - Motion.smooth(Geometry.phase(board.portraitMix, 0.27, 0.91))
        clip: true
        cellWidth: Math.floor(width / 2)
        cellHeight: 33
        boundsBehavior: Flickable.StopAtBounds
        model: board.model
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: RowLayout {
            id: person
            required property string participantId
            required property string name
            required property var avatar
            required property bool speaking
            required property string status

            objectName: "discordParticipant_" + participantId
            width: roster.cellWidth - 12
            height: 27
            spacing: 6
            Accessible.role: Accessible.StaticText
            Accessible.name: name
            Accessible.description: status
            ToolTip.visible: nameHover.hovered && personName.truncated
            ToolTip.delay: 450
            ToolTip.text: name

            ParticipantAvatar {
                Layout.preferredWidth: 27
                Layout.preferredHeight: 27
                avatar: person.avatar
                name: person.name
                speaking: person.speaking
            }
            ParticipantName {
                id: personName
                text: person.name
                font.pixelSize: 13
                Accessible.ignored: true
            }
            ParticipantCaption {
                text: person.status
                Layout.fillWidth: false
                font.pixelSize: 11
                color: person.speaking ? "#a4e7cc" : board.mutedInk
                Accessible.ignored: true
            }
            HoverHandler { id: nameHover }
        }
    }
}
