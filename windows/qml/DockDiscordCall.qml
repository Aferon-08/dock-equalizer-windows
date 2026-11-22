pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

Item {
    id: call
    required property DiscordCallPreview preview
    required property var media
    required property var notification
    required property rect housing
    required property real opening
    required property real topInset
    required property bool expansionAllowed
    required property real musicProgress

    readonly property real sideWidth: 196
    readonly property real sideHeight: 50
    readonly property real expandedWidth: 504
    readonly property real expandedHeight: 224
    readonly property bool mainVisible: preview.active && (preview.ringing || !notification.presenting)
    readonly property bool interactive: mainVisible && opening > 0.78 && entry > 0.62
    readonly property bool expanded: preview.connected && preview.expanded && expansionAllowed
    readonly property bool showMusic: preview.connected && !expanded && !!media.player
    readonly property string mode: !mainVisible ? "" : preview.ringing ? "incoming" : expanded ? "expanded" : "compact"
    readonly property color lavender: "#c6baff"
    readonly property color mutedInk: "#b5c8c1"
    readonly property color ink: "#eff8f5"

    property real panelWidth: mode === "incoming" ? 476 : expanded ? expandedWidth : showMusic ? 548 : 336
    property real panelHeight: mode === "expanded" ? expandedHeight : 72
    Behavior on panelWidth { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
    Behavior on panelHeight { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 0.6 } }
    readonly property rect layoutBounds: Qt.rect((width - panelWidth) / 2, topInset, panelWidth, panelHeight)
    readonly property real sideEntry: preview.connected && notification.presenting
        ? Geometry.phase(notification.reveal, 0.17, 0.66) : 0
    readonly property rect sideBounds: {
        if (sideEntry <= 0)
            return Qt.rect(0, 0, 0, 0)
        const travel = Geometry.arrival(sideEntry, 0.16)
        const span = sideWidth * Geometry.mix(0.48, 1, travel)
        const height = sideHeight * Geometry.mix(0.44, 1, travel)
        const centerY = notification.bodyBounds.y + 34 - 14 * (1 - travel)
        return Qt.rect(notification.bodyBounds.x - notification.miniGap - span + 12 * (1 - travel),
            centerY - height / 2, span, height)
    }

    property real entry: 1
    onModeChanged: {
        entryMotion.stop()
        if (mode !== "") {
            entry = 0
            entryMotion.start()
        }
    }
    NumberAnimation { id: entryMotion; target: call; property: "entry"; to: 1; duration: 720 }

    component VoiceIcon: Shape {
        id: symbol
        required property string name
        property color ink: call.ink
        width: 24
        height: 24
        scale: 0.75

        ShapePath {
            fillColor: "transparent"
            strokeColor: symbol.ink
            strokeWidth: 1.8
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: {
                    switch (symbol.name) {
                    case "mic":
                    case "mic-off":
                        return "M9 5a3 3 0 0 1 6 0v7a3 3 0 0 1-6 0z M5 10v2a7 7 0 0 0 14 0v-2 M12 19v3 M9 22h6"
                            + (symbol.name === "mic-off" ? " M3 3l18 18" : "")
                    case "headphones":
                    case "deaf":
                        return "M3 14v-2a9 9 0 0 1 18 0v2 M3 14h3a2 2 0 0 1 2 2v4H5a2 2 0 0 1-2-2z M21 14h-3a2 2 0 0 0-2 2v4h3a2 2 0 0 0 2-2z"
                            + (symbol.name === "deaf" ? " M3 3l18 18" : "")
                    case "phone":
                        return "M6 3h3l2 5-2 2a12 12 0 0 0 5 5l2-2 5 2v3a2 2 0 0 1-2 2C10 20 4 14 4 5a2 2 0 0 1 2-2z"
                    case "hang":
                        return "M3 14a2 2 0 0 1 0-3 15 15 0 0 1 18 0 2 2 0 0 1 0 3l-1 2-5-2v-3a11 11 0 0 0-6 0v3l-5 2z"
                    case "pause": return "M9 6v12 M15 6v12"
                    case "play": return "M9 5l10 7-10 7z"
                    case "music": return "M10 17V6l9-2v10 M10 17a3 2 0 1 1-6 0 3 2 0 1 1 6 0z M19 14a3 2 0 1 1-6 0 3 2 0 1 1 6 0z"
                    case "collapse": return "M7 14l5-5 5 5"
                    default: return "M7 10l5 5 5-5"
                    }
                }
            }
        }
    }

    component Title: Text {
        color: call.ink
        font.pixelSize: 15
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        textFormat: Text.PlainText
        Layout.fillWidth: true
    }

    component Caption: Text {
        color: call.mutedInk
        font.pixelSize: 12
        elide: Text.ElideRight
        textFormat: Text.PlainText
        Layout.fillWidth: true
    }

    component IconTile: Rectangle {
        id: tile
        required property string symbol
        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        Layout.alignment: Qt.AlignVCenter
        radius: 11
        color: "#32b5a2ff"
        border.color: "#54c6baff"
        VoiceIcon { anchors.centerIn: parent; name: tile.symbol; ink: call.lavender }
    }

    component Action: Button {
        id: button
        required property string symbol
        required property string actionName
        property color tint: "#b4d9cc"

        implicitWidth: text !== "" ? contentItem.implicitWidth + 20 : implicitHeight
        implicitHeight: 36
        padding: 0
        hoverEnabled: true
        Accessible.name: actionName
        ToolTip.visible: hovered && text === ""
        ToolTip.delay: 550
        ToolTip.text: actionName

        contentItem: Item {
            implicitWidth: key.implicitWidth
            Row {
                id: key
                anchors.centerIn: parent
                spacing: 3
                VoiceIcon { name: button.symbol; opacity: button.enabled ? 1 : 0.65 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: button.text !== ""
                    text: button.text
                    color: call.ink
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }
        background: Rectangle {
            radius: 11
            color: Qt.alpha(button.tint, button.down ? 0.35 : button.hovered ? 0.29 : 0.17)
            border.color: Qt.alpha(button.tint, button.hovered || button.visualFocus ? 0.66 : 0.31)
            antialiasing: true
            Behavior on color { ColorAnimation { duration: 135 } }
        }
        HoverHandler { enabled: button.enabled; cursorShape: Qt.PointingHandCursor }
    }

    component MicAction: Action {
        symbol: call.preview.microphoneOff ? "mic-off" : "mic"
        actionName: call.preview.deafened ? "Микрофон выключен вместе со звуком"
            : call.preview.muted ? "Включить микрофон" : "Выключить микрофон"
        enabled: !call.preview.deafened
        tint: call.preview.microphoneOff ? "#e3b0b8" : "#b4d9cc"
        onClicked: call.preview.toggleMute()
    }

    component HangUpAction: Action {
        symbol: "hang"
        actionName: "Завершить звонок"
        tint: "#ff7f8a"
        onClicked: call.preview.hangUp()
    }

    component EnteringPart: Item {
        id: part
        property real delay: 0.15
        property real fromX: 0
        property real fromY: -24
        readonly property real travel: Geometry.arrival(Geometry.phase(Math.min(call.opening, call.entry), delay, 1), 0.25)

        opacity: Motion.smooth(Geometry.phase(Math.min(call.opening, call.entry), delay, delay + 0.35))
        transform: [
            Scale {
                origin.x: part.width / 2
                origin.y: part.height / 2
                xScale: Geometry.mix(0.71, 1, part.travel)
                yScale: Geometry.mix(0.54, 1, part.travel)
            },
            Translate { x: part.fromX * (1 - part.travel); y: part.fromY * (1 - part.travel) }
        ]
    }

    Item {
        id: deck
        x: call.housing.x
        y: call.housing.y
        width: call.housing.width
        height: call.housing.height
        clip: true
        visible: call.mainVisible
        enabled: call.interactive

        Item {
            id: content
            anchors.centerIn: parent
            width: call.panelWidth
            height: call.panelHeight

            EnteringPart {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                visible: call.mode === "incoming"

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 9

                    IconTile { symbol: "phone" }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Title { text: call.preview.caller + " звонит"; font.pixelSize: 17 }
                        Caption { text: "Discord · Тестовый звонок"; color: call.lavender }
                    }
                    Action {
                        objectName: "acceptDiscordPreview"
                        text: "Принять"
                        actionName: "Принять звонок"
                        symbol: "phone"
                        tint: "#8ae4bb"
                        transform: Translate { x: 13 * (1 - Geometry.arrival(Geometry.phase(call.entry, 0.34, 1), 0.2)) }
                        onClicked: call.preview.accept()
                    }
                    Action {
                        objectName: "declineDiscordPreview"
                        text: "Отклонить"
                        actionName: "Отклонить звонок"
                        symbol: "hang"
                        tint: "#ff7f8a"
                        transform: Translate { x: 18 * (1 - Geometry.arrival(Geometry.phase(call.entry, 0.46, 1), 0.2)) }
                        onClicked: call.preview.decline()
                    }
                }
            }

            Item {
                anchors.fill: parent
                anchors.margins: 18
                visible: call.preview.connected && call.mainVisible

                EnteringPart {
                    id: header
                    width: parent.width
                    height: 36
                    y: call.expanded ? 0 : (parent.height - height) / 2
                    fromX: -20

                    RowLayout {
                        anchors.fill: parent
                        spacing: 8

                        IconTile { symbol: "headphones" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Title { text: call.preview.room; font.pixelSize: call.expanded ? 18 : 15 }
                            Caption {
                                text: call.expanded ? "Discord · Тестовый войс" : call.preview.durationText
                                color: call.lavender
                            }
                        }
                        Title {
                            visible: call.expanded
                            Layout.fillWidth: false
                            text: call.preview.durationText
                            color: call.lavender
                        }
                        Action {
                            objectName: "toggleDiscordPreviewLayout"
                            symbol: call.expanded ? "collapse" : "expand"
                            actionName: call.expanded ? "Свернуть панель звонка" : "Раскрыть панель звонка"
                            visible: call.expansionAllowed
                            onClicked: call.preview.toggleExpanded()
                        }
                        MicAction { objectName: "muteDiscordCompact"; visible: !call.expanded }
                        HangUpAction { objectName: "hangUpDiscordCompact"; visible: !call.expanded }
                        Rectangle {
                            visible: call.showMusic
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: 1
                            Layout.leftMargin: 5
                            Layout.rightMargin: 4
                            color: "#4cb8dacd"
                        }
                        IconTile {
                            visible: call.showMusic
                            symbol: "music"
                            color: "#26ddbc9e"
                            border.color: "#47ddbc9e"
                            clip: true
                            Image {
                                anchors.fill: parent
                                anchors.margins: 3
                                source: call.showMusic ? call.media.artUrl : ""
                                sourceSize: Qt.size(72, 72)
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                            }
                        }
                        ColumnLayout {
                            visible: call.showMusic
                            Layout.fillWidth: true
                            spacing: 6
                            Title { text: call.media.title ?? ""; font.pixelSize: 13 }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 2
                                radius: 1
                                color: "#4bb6d6c9"
                                Rectangle {
                                    width: parent.width * Motion.clamp(call.musicProgress, 0, 1)
                                    height: parent.height
                                    radius: parent.radius
                                    color: "#a4e7cc"
                                }
                            }
                        }
                        Action {
                            objectName: "playDiscordCompactMusic"
                            visible: call.showMusic
                            enabled: !!call.media.player?.canTogglePlaying
                            symbol: call.media.playing ? "pause" : "play"
                            actionName: call.media.playing ? "Приостановить музыку" : "Возобновить музыку"
                            onClicked: call.media.togglePlaying()
                        }
                    }
                }

                EnteringPart {
                    id: participantPanel
                    y: 46
                    width: parent.width
                    height: 96
                    visible: call.mode === "expanded"
                    delay: 0.31
                    fromY: -15
                    Rectangle {
                        anchors.fill: parent
                        radius: 15
                        color: "#20101919"
                        border.color: "#32b8dacd"
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 5
                        Caption { text: "Участники · " + call.preview.participants.length }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 4
                            Repeater {
                                model: call.preview.participants
                                RowLayout {
                                    id: person
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        radius: 11
                                        color: "#3a9384bd"
                                        border.color: person.modelData.speaking ? "#90dcb9" : "#449b8cbe"
                                        Text {
                                            anchors.centerIn: parent
                                            text: person.modelData.name[0]
                                            color: call.ink
                                            font.pixelSize: 11
                                            Accessible.ignored: true
                                        }
                                    }
                                    Title { text: person.modelData.name; font.pixelSize: 12 }
                                    Caption {
                                        text: person.modelData.status
                                        Layout.fillWidth: false
                                        color: person.modelData.speaking ? "#a4e7cc" : call.mutedInk
                                    }
                                }
                            }
                        }
                    }
                }

                EnteringPart {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 36
                    visible: call.mode === "expanded"
                    delay: 0.46
                    fromX: 18
                    fromY: -12

                    RowLayout {
                        anchors.fill: parent
                        spacing: 8
                        MicAction {
                            objectName: "muteDiscordExpanded"
                            text: call.preview.microphoneOff ? "Микрофон выкл." : "Микрофон"
                        }
                        Action {
                            objectName: "deafenDiscordPreview"
                            text: call.preview.deafened ? "Включить звук" : "Отключить звук и микрофон"
                            actionName: text
                            symbol: call.preview.deafened ? "deaf" : "headphones"
                            tint: call.preview.deafened ? "#e3b0b8" : "#b4d9cc"
                            onClicked: call.preview.toggleDeafen()
                        }
                        Item { Layout.fillWidth: true }
                        HangUpAction { objectName: "hangUpDiscordExpanded"; text: "Выйти" }
                    }
                }
            }
        }
    }

    Item {
        id: sideCapsule
        objectName: "discordSideCapsule"
        x: call.sideBounds.x
        y: call.sideBounds.y
        width: call.sideBounds.width
        height: call.sideBounds.height
        opacity: Motion.smooth(Geometry.phase(call.sideEntry, 0.28, 0.88))
        visible: width > 0 && opacity > 0
        enabled: visible && call.sideEntry > 0.88
        clip: true

        RowLayout {
            width: call.sideWidth - 21
            anchors.centerIn: parent
            spacing: 8
            IconTile { symbol: "headphones"; Layout.preferredWidth: 29; Layout.preferredHeight: 29; radius: 10 }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Title { text: call.preview.room; font.pixelSize: 13 }
                Caption { text: call.preview.durationText; color: call.lavender }
            }
            MicAction { objectName: "muteDiscordSide"; implicitHeight: 32 }
        }
    }
}
