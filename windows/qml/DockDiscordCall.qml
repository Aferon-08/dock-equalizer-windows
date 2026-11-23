pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

Item {
    id: call
    required property DiscordCall session
    required property var media
    required property var notification
    required property var motionCurve
    required property bool springMotion
    required property rect housing
    required property real opening
    required property real topInset
    required property bool expansionAllowed
    required property real availableHeight
    required property real musicProgress
    property bool presentationAvailable: true
    property var captureOverride: null

    readonly property real sideWidth: 196
    readonly property real sideHeight: 50
    readonly property real expandedWidth: Math.min(504, Math.max(0, width - 48))
    readonly property real expandedChromeHeight: 128
    readonly property real minimumExpandedHeight: expandedChromeHeight + 86
    readonly property real expandedHeight: baseExpandedHeight + previewSpace * previewProgress
    readonly property color lavender: "#c6baff"
    readonly property color mutedInk: "#b5c8c1"
    readonly property color ink: "#eff8f5"

    // Keep the last layout through the exit. The call can end immediately
    // while the parts fold into the housing or leave room for the player.
    property int presentedPhase: DiscordCallPreview.Idle
    property var presentedParticipants: []
    property string pairStatus: "unknown"
    readonly property int presentedParticipantCount: presentedParticipants.length
    readonly property var previewCapture: captureOverride ?? videoPreview

    function refreshRoster() {
        if (session.connected) {
            presentedParticipants = session.participants
            pairStatus = session.voiceStatus
        }
    }

    Component.onCompleted: {
        presentedPhase = session.phase
        refreshRoster()
    }
    Connections {
        target: call.session
        function onPhaseChanged() {
            if (call.session.active)
                call.presentedPhase = call.session.phase
            call.refreshRoster()
        }
        function onParticipantsChanged() { call.refreshRoster() }
        function onVoiceStatusChanged() { call.refreshRoster() }
        function onChannelKeyChanged() { call.previewCapture.closePreview() }
    }

    readonly property bool conversation: presentedPhase === DiscordCallPreview.Connected
    readonly property bool presenting: session.active || lifetime > 0
    readonly property bool retiring: presenting && !session.active
    readonly property bool ringOnTop: presenting && !session.usesLive && (!conversation || joinProgress < 0.36)
    readonly property bool expanded: conversation && expansionAllowed
    readonly property bool showMusic: conversation && !expanded && !!media.player
    readonly property real exposed: Math.min(lifetime, opening)
    readonly property bool interactive: session.active && exposed > 0.79 && !notification.active && split < 0.03

    property real lifetime: session.active ? 1 : 0
    property real joinProgress: conversation ? 1 : 0
    property real expandProgress: expanded ? 1 : 0
    property real musicMix: media.player ? 1 : 0
    readonly property real portraitMix: rosterBoard.portraitMix
    readonly property real participantPairTravel: rosterBoard.pairTravel
    property real participantAreaHeight: Math.min(Math.max(86, availableHeight - expandedChromeHeight),
        presentedParticipantCount >= 4 ? 96 : presentedParticipantCount === 2 ? 90 : 86)
    readonly property real baseExpandedHeight: expandedChromeHeight + participantAreaHeight
    readonly property real previewWidth: Math.min(expandedWidth * 0.58,
        Math.max(0, availableHeight - baseExpandedHeight - 10) * 16 / 9)
    readonly property real previewHeight: previewWidth * 9 / 16
    readonly property real previewSpace: previewHeight + 10
    readonly property bool previewFits: previewWidth >= 156
    readonly property bool previewOpen: previewCapture.opened && previewFits
    readonly property bool captureActive: presentationAvailable && session.connected && expanded
        && exposed > 0.79 && split < 0.03 && previewFits
    property real previewProgress: previewOpen ? 1 : 0
    Behavior on lifetime { DockTransition { duration: call.session.active ? 880 : 680; curve: call.motionCurve } }
    Behavior on joinProgress { DockTransition { duration: 780; curve: call.motionCurve } }
    Behavior on expandProgress { DockTransition { duration: call.expanded ? 880 : 670; curve: call.motionCurve } }
    Behavior on musicMix { DockTransition { duration: 400; curve: call.motionCurve; standardEasing: Easing.InOutCubic } }
    Behavior on participantAreaHeight {
        DockTransition { duration: 350; curve: call.motionCurve; standardEasing: Easing.InOutCubic }
    }
    Behavior on previewProgress {
        DockTransition { duration: 350; curve: call.motionCurve; standardEasing: Easing.InOutCubic }
    }

    readonly property real housingMix: Motion.travel(Geometry.phase(lifetime, 0.05, 0.94))
    readonly property real lyricsCover: Motion.smooth(Geometry.phase(lifetime, 0.10, 0.74))
    readonly property real spread: Geometry.arrival(Geometry.phase(expandProgress, 0.03, 1), springMotion ? 0.14 : 0)
    readonly property real compactWidth: Geometry.mix(336, 548, musicMix)
    readonly property real panelWidth: Geometry.mix(
        Geometry.mix(476, compactWidth, Motion.travel(joinProgress)), expandedWidth, spread)
    readonly property real panelHeight: Geometry.mix(72, expandedHeight, spread)
    readonly property rect layoutBounds: Qt.rect((width - panelWidth) / 2, topInset, panelWidth, panelHeight)

    readonly property real split: notification.usesCallLayout && !notification.suspended ? notification.splitProgress : 0
    readonly property real sideBlend: split > 0 ? notification.splitBlend : 0
    readonly property rect sideBounds: {
        const growth = Motion.smooth(Geometry.phase(split, 0.09, 0.65))
        if (growth <= 0)
            return Qt.rect(0, 0, 0, 0)
        const body = notification.bodyBounds
        const travel = Motion.travel(Geometry.phase(split, 0.15, 0.94))
        const stretch = notification.splitStretch
        const recoil = notification.releaseRecoil
        const span = sideWidth * growth * (1 + 0.12 * stretch + 0.035 * recoil)
        const height = sideHeight * growth * (1 - 0.18 * stretch)
        const edge = body.x + Geometry.mix(body.width * 0.52, -notification.miniGap, travel) - 10 * recoil
        const centerY = body.y + 35 + 8 * stretch - 5 * recoil
        return Qt.rect(edge - span,
            centerY - height / 2, span, height)
    }
    readonly property rect sideNeck: notification.connectingNeck(sideBounds, sideBlend, true)

    readonly property rect frame: split > 0 ? notification.bodyBounds : housing
    readonly property real inset: Math.min(18, frame.width * 0.18)
    readonly property real deckLeft: frame.x + inset
    readonly property real deckRight: frame.x + frame.width - inset
    readonly property real headerTop: frame.y + Math.min(18, frame.height * 0.25)
    readonly property real compactContent: 1 - Geometry.phase(expandProgress, 0.12, 0.53)
    readonly property real titleChange: session.usesLive ? 1 : Motion.smooth(Geometry.phase(joinProgress, 0.18, 0.62))
    readonly property real identityTravel: Motion.travel(Geometry.phase(split, 0.22, 0.74))
    readonly property real headerExpanded: Motion.smooth(expandProgress) * (1 - identityTravel)
    readonly property real dockContent: 1 - Geometry.phase(split, 0.06, 0.61)
    readonly property real musicWidth: 214
    readonly property real compactKeysRight: deckRight - musicMix * musicWidth
    readonly property real artworkSize: 36
    readonly property real musicLeft: deckRight - musicWidth + 11
    readonly property real musicDividerWidth: 1
    readonly property real musicDividerMargin: 4
    readonly property real musicSpacing: 8
    readonly property point artworkCenter: Qt.point(musicLeft + musicDividerWidth + musicDividerMargin
        + musicSpacing + artworkSize / 2, headerTop + artworkSize / 2)
    readonly property real artworkAmount: Math.min(musicMix, Geometry.phase(joinProgress, 0.42, 1),
        Geometry.phase(exposed, 0.50, 0.98))
    readonly property real musicSeparation: Math.max(Geometry.phase(expandProgress, 0.06, 0.99), split)
        * Geometry.phase(joinProgress, 0.36, 0.86) * Geometry.phase(lifetime, 0.12, 0.86) * musicMix
    readonly property real inlineMusicAmount: Math.min(artworkAmount,
        1 - Geometry.phase(musicSeparation, 0.04, 0.58))
    readonly property point releasePoint: Qt.point(
        Geometry.mix(deckLeft + frame.width * 0.27, sideBounds.x + sideBounds.width * 0.66, identityTravel),
        Geometry.mix(headerTop + 23, sideBounds.y + sideBounds.height * 0.52, identityTravel))

    visible: presenting

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
                    case "screen": return "M4 5h16v11H4z M12 16v4 M8 20h8"
                    case "close": return "M6 6l12 12 M18 6L6 18"
                    default: return ""
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
        property string nextSymbol: ""
        property real symbolMix: 0
        Layout.preferredWidth: 36
        Layout.preferredHeight: 36
        Layout.alignment: Qt.AlignVCenter
        radius: 11
        color: "#32b5a2ff"
        border.color: "#54c6baff"
        VoiceIcon {
            anchors.centerIn: parent
            name: tile.symbol
            ink: call.lavender
            opacity: 1 - tile.symbolMix
        }
        VoiceIcon {
            anchors.centerIn: parent
            name: tile.nextSymbol
            ink: call.lavender
            visible: opacity > 0
            opacity: tile.symbolMix
        }
    }

    component Action: Button {
        id: button
        required property string symbol
        required property string actionName
        property color tint: "#b4d9cc"
        property string helpText: actionName

        implicitWidth: text !== "" ? contentItem.implicitWidth + 20 : implicitHeight
        implicitHeight: 36
        padding: 0
        hoverEnabled: true
        Accessible.name: actionName
        ToolTip.visible: hovered && (text === "" || helpText !== actionName)
        ToolTip.delay: 550
        ToolTip.text: helpText

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
            Behavior on color { DockTransition { duration: 135; curve: call.motionCurve } }
        }
        HoverHandler { enabled: button.enabled; cursorShape: Qt.PointingHandCursor }
    }

    component MicAction: Action {
        symbol: call.session.microphoneOff ? "mic-off" : "mic"
        actionName: call.session.deafened ? "Микрофон выключен вместе со звуком"
            : call.session.muted ? "Включить микрофон" : "Выключить микрофон"
        enabled: call.session.canChangeVoice && !call.session.deafened
        tint: call.session.microphoneOff ? "#e3b0b8" : "#b4d9cc"
        onClicked: call.session.toggleMute()
    }

    component HangUpAction: Action {
        symbol: "hang"
        actionName: "Завершить звонок"
        enabled: call.session.canHangUp
        tint: "#ff7f8a"
        onClicked: call.session.hangUp()
    }

    component Foldout: Item {
        id: part
        required property point source
        required property rect targetBounds
        required property real amount
        property real spring: 0.23
        readonly property real travel: Geometry.arrival(amount, call.springMotion ? spring : 0)

        x: Geometry.mix(source.x - width / 2, targetBounds.x, Math.min(1.04, travel))
        y: Geometry.mix(source.y - height / 2, targetBounds.y, travel)
        width: Math.max(1, targetBounds.width)
        height: targetBounds.height
        opacity: Motion.smooth(Geometry.phase(amount, 0.02, 0.41))
        visible: opacity > 0.001
        enabled: opacity > 0.99
        transform: Scale {
            origin.x: part.width / 2
            origin.y: part.height / 2
            xScale: Geometry.mix(0.30, 1, Math.min(1, part.travel))
            yScale: Geometry.mix(0.16, 1, Math.min(1.05, part.travel))
        }
    }

    readonly property real participantTravel: participants.travel
    readonly property real controlTravel: callControls.travel
    readonly property rect identityBounds: Qt.rect(identity.x, identity.y, identity.width, identity.height)
    readonly property rect participantBounds: Qt.rect(participants.x,
        contentClip.y + participants.y, participants.width, participants.height)
    readonly property rect controlBounds: Qt.rect(callControls.x,
        controlClip.y + callControls.y, callControls.width, callControls.height)
    readonly property rect previewTileBounds: Qt.rect(previewTile.x, contentClip.y + previewTile.y,
        previewTile.width, previewTile.height)

    Foldout {
        id: ringControls
        source: Qt.point(call.deckRight - 19, call.headerTop + 17)
        targetBounds: Qt.rect(call.deckRight - ringKeys.implicitWidth, call.headerTop, ringKeys.implicitWidth, 36)
        amount: call.session.usesLive ? 0 : Math.min(Geometry.phase(call.exposed, 0.32, 1),
            1 - Geometry.phase(call.joinProgress, 0.02, 0.43))
        enabled: call.interactive && call.session.ringing && amount > 0.8

        RowLayout {
            id: ringKeys
            anchors.fill: parent
            spacing: 8

            Action {
                objectName: "acceptDiscordPreview"
                text: "Принять"
                actionName: "Принять звонок"
                symbol: "phone"
                tint: "#8ae4bb"
                transform: Translate { x: -9 * (1 - ringControls.travel) }
                onClicked: call.session.accept()
            }
            Action {
                objectName: "declineDiscordPreview"
                text: "Отклонить"
                actionName: "Отклонить звонок"
                symbol: "hang"
                tint: "#ff7f8a"
                transform: Translate { y: -11 * (1 - ringControls.travel) }
                onClicked: call.session.decline()
            }
        }
    }

    Item {
        id: identity
        objectName: "discordCallIdentity"
        z: 2
        readonly property real badgeSize: Geometry.mix(36, 30, call.identityTravel)
        readonly property real keyReserve: Geometry.mix(ringKeys.implicitWidth + 12,
            Geometry.mix(82 + call.musicMix * call.musicWidth,
                64 + (call.previewOpen ? 0 : showPreview.implicitWidth + 8), Motion.smooth(call.expandProgress)),
            call.titleChange)
        readonly property real homeWidth: Math.max(44, call.deckRight - call.deckLeft - keyReserve)
        readonly property real arrival: Geometry.phase(call.exposed, 0.29, 0.78)
        x: Geometry.mix(call.deckLeft, call.sideBounds.x + 10, call.identityTravel)
        y: Geometry.mix(call.headerTop, call.sideBounds.y + (call.sideBounds.height - height) / 2, call.identityTravel)
        width: Geometry.mix(homeWidth, Math.max(44, call.sideBounds.width - 54), call.identityTravel)
        height: Geometry.mix(36, 34, call.identityTravel)
        opacity: Motion.smooth(Geometry.phase(call.exposed, 0.23, 0.63))
        visible: opacity > 0.001
        transform: Scale {
            origin.x: 0
            origin.y: identity.height / 2
            readonly property real travel: Geometry.arrival(identity.arrival, call.springMotion ? 0.16 : 0)
            xScale: Geometry.mix(0.55, 1, travel)
            yScale: Geometry.mix(0.38, 1, travel)
        }

        RowLayout {
            anchors.fill: parent
            spacing: 8

            IconTile {
                symbol: "phone"
                nextSymbol: "headphones"
                symbolMix: call.titleChange
                Layout.preferredWidth: identity.badgeSize
                Layout.preferredHeight: identity.badgeSize
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 35

                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 21
                    clip: true

                    Title {
                        width: parent.width
                        y: -parent.height * call.titleChange
                        opacity: 1 - call.titleChange
                        visible: opacity > 0
                        text: call.session.caller + " звонит"
                        font.pixelSize: 17
                    }
                    Title {
                        width: parent.width
                        y: parent.height * (1 - call.titleChange)
                        opacity: call.titleChange
                        visible: opacity > 0
                        text: call.session.room
                        font.pixelSize: Math.round(Geometry.mix(15 + 3 * call.headerExpanded, 13, call.identityTravel))
                    }
                }
                Caption {
                    y: 21
                    width: parent.width
                    text: call.session.deafened ? "Discord · Звук выключен" : call.session.context
                    color: call.lavender
                    opacity: call.titleChange * call.headerExpanded
                    visible: opacity > 0.01
                }
                Caption {
                    y: 21 - 9 * call.titleChange
                    width: parent.width
                    text: call.session.context
                    color: call.lavender
                    opacity: 1 - call.titleChange
                    visible: opacity > 0.01
                }
            }
        }
    }

    Title {
        id: elapsedClock
        z: 2
        x: Geometry.mix(identity.x + identity.badgeSize + 8, call.deckRight - width, call.headerExpanded)
        y: Geometry.mix(identity.y + 20, call.headerTop + 8, call.headerExpanded)
        text: call.session.durationText
        color: call.lavender
        font.pixelSize: Math.round(12 + 3 * call.headerExpanded)
        opacity: identity.opacity * call.titleChange
        visible: opacity > 0.01
    }

    Foldout {
        id: compactControls
        source: Qt.point(call.compactKeysRight - 21, call.headerTop + 16)
        targetBounds: Qt.rect(call.compactKeysRight - 80, call.headerTop, 80, 36)
        amount: Math.min(call.compactContent, call.dockContent, Geometry.phase(call.joinProgress, 0.33, 1),
            Geometry.phase(call.exposed, 0.56, 1))
        enabled: call.interactive && call.session.connected && amount > 0.88

        RowLayout {
            anchors.fill: parent
            spacing: 8
            MicAction { objectName: "muteDiscordCompact" }
            HangUpAction { objectName: "hangUpDiscordCompact" }
        }
    }

    Foldout {
        id: compactMusic
        source: call.artworkCenter
        targetBounds: Qt.rect(call.musicLeft, call.headerTop, call.deckRight - call.musicLeft, call.artworkSize)
        amount: call.inlineMusicAmount
        enabled: call.interactive && call.session.connected && amount > 0.88

        RowLayout {
            anchors.fill: parent
            spacing: call.musicSpacing

            Rectangle {
                Layout.preferredHeight: 28
                Layout.preferredWidth: call.musicDividerWidth
                Layout.rightMargin: call.musicDividerMargin
                color: "#4cb8dacd"
            }
            // The cover travels in DockMiniPlayer and occupies this space when docked.
            Item {
                Layout.preferredWidth: call.artworkSize
                Layout.preferredHeight: call.artworkSize
            }
            ColumnLayout {
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
                enabled: !!call.media.player?.canTogglePlaying
                symbol: call.media.playing ? "pause" : "play"
                actionName: call.media.playing ? "Приостановить музыку" : "Возобновить музыку"
                onClicked: call.media.togglePlaying()
            }
        }
    }

    Action {
        id: showPreview
        objectName: "showDiscordPreview"
        x: elapsedClock.x - width - 10
        y: call.headerTop + 3
        implicitHeight: 30
        text: call.previewCapture.opened ? "Закрыть превью" : "Показать превью"
        actionName: text
        helpText: !call.previewCapture.available ? "Захват экрана недоступен"
            : !call.previewFits ? "Недостаточно места для превью" : actionName
        symbol: call.previewCapture.opened ? "close" : "screen"
        opacity: call.headerExpanded * identity.opacity * (1 - call.previewProgress)
        visible: opacity > 0.01 && !call.previewOpen
        enabled: call.interactive && call.session.connected && opacity > 0.9
            && (call.previewCapture.opened || (call.previewCapture.available && call.previewFits))
        onClicked: {
            if (call.previewCapture.opened)
                call.previewCapture.closePreview()
            else
                call.previewCapture.chooseSource()
        }
    }

    Rectangle {
        x: call.deckLeft
        y: call.headerTop + 43
        width: call.deckRight - call.deckLeft
        height: 1
        color: "#42b8dacd"
        opacity: call.headerExpanded * identity.opacity
        visible: opacity > 0.01
    }

    Item {
        id: contentClip
        width: parent.width
        y: call.headerTop + 46
        height: Math.max(0, call.frame.y + call.frame.height - y - 5)
        clip: true

        Item {
            id: previewViewport
            width: parent.width
            height: call.previewSpace * call.previewProgress
            visible: call.previewProgress > 0.001
            clip: true

            Rectangle {
                id: previewTile
                objectName: "discordPreviewTile"
                x: (parent.width - width) / 2
                y: (parent.height - height) / 2 - 3 * call.previewProgress
                width: call.previewWidth
                height: call.previewHeight
                scale: Geometry.mix(0.55, 1, call.previewProgress)
                opacity: Motion.smooth(Geometry.phase(call.previewProgress, 0.05, 0.72))
                    * call.headerExpanded * identity.opacity * call.dockContent
                radius: 10
                color: "#151d21"
                border.color: "#688ca69f"
                antialiasing: true

                Item {
                    id: videoArea
                    x: 3
                    y: 3
                    width: Math.max(0, parent.width - 6)
                    height: Math.max(0, parent.height - previewFooter.height - 4)
                    clip: true

                    VoicePreview {
                        id: videoPreview
                        anchors.fill: parent
                        active: !call.captureOverride && call.captureActive
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.max(0, parent.width - 12)
                        visible: !call.previewCapture.hasFrame
                        spacing: 3

                        Caption {
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            text: call.previewCapture.status
                            font.pixelSize: 11
                        }
                        Action {
                            objectName: "retryDiscordPreview"
                            Layout.alignment: Qt.AlignHCenter
                            visible: call.previewCapture.retryable === true
                            enabled: call.captureActive && call.interactive && !call.previewCapture.selecting
                            implicitHeight: 27
                            text: "Выбрать источник"
                            symbol: "screen"
                            actionName: text
                            onClicked: call.previewCapture.chooseSource()
                        }
                    }
                }

                RowLayout {
                    id: previewFooter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 8
                    anchors.rightMargin: 4
                    anchors.bottomMargin: 3
                    height: 26
                    spacing: 3
                    VoiceIcon { name: "screen"; ink: call.mutedInk }
                    Title { text: "Моя демонстрация"; font.pixelSize: 12 }
                    Action {
                        objectName: "closeDiscordPreview"
                        implicitHeight: 24
                        actionName: "Закрыть локальное превью"
                        symbol: "close"
                        enabled: call.interactive && call.captureActive
                        onClicked: call.previewCapture.closePreview()
                    }
                }
            }
        }

        Foldout {
            id: participants
            objectName: "discordParticipants"
            source: Qt.point(call.releasePoint.x, call.releasePoint.y - parent.y)
            targetBounds: Qt.rect(call.deckLeft, previewViewport.height,
                call.deckRight - call.deckLeft, call.participantAreaHeight)
            amount: Math.min(Geometry.phase(call.expandProgress, 0.19, 0.92), call.dockContent,
                Geometry.phase(call.exposed, 0.44, 0.96))
            spring: 0.20

            DockVoiceParticipants {
                id: rosterBoard
                anchors.fill: parent
                model: call.session.participantModel
                people: call.presentedParticipants
                connectionStatus: call.pairStatus
                expanded: call.expanded
                motionCurve: call.motionCurve
                springMotion: call.springMotion
                ink: call.ink
                mutedInk: call.mutedInk
            }
        }
    }

    Item {
        id: controlClip
        width: parent.width
        y: call.headerTop + 49 + call.participantAreaHeight + previewViewport.height
        height: Math.max(0, Math.min(48, call.frame.y + call.frame.height - y - 5))
        clip: true

        Foldout {
            id: callControls
            objectName: "discordExpandedControls"
            source: Qt.point(Geometry.mix(call.deckRight - 38, call.releasePoint.x, call.identityTravel),
                -12)
            targetBounds: Qt.rect(call.deckLeft, 7, call.deckRight - call.deckLeft, 36)
            amount: Math.min(Geometry.phase(call.expandProgress, 0.39, 1),
                1 - Geometry.phase(call.split, 0.02, 0.48), Geometry.phase(call.exposed, 0.58, 1))
            enabled: call.interactive && call.session.connected && amount > 0.9

            RowLayout {
                anchors.fill: parent
                spacing: 8
                MicAction {
                    objectName: "muteDiscordExpanded"
                    text: call.session.microphoneOff ? "Микрофон выкл." : "Микрофон"
                }
                Action {
                    objectName: "deafenDiscordPreview"
                    enabled: call.session.canChangeVoice
                    text: call.session.deafened ? "Включить звук" : "Отключить звук и микрофон"
                    actionName: text
                    symbol: call.session.deafened ? "deaf" : "headphones"
                    tint: call.session.deafened ? "#e3b0b8" : "#b4d9cc"
                    onClicked: call.session.toggleDeafen()
                }
                Item { Layout.fillWidth: true }
                HangUpAction { objectName: "hangUpDiscordExpanded"; text: "Выйти" }
            }
        }
    }

    Foldout {
        objectName: "discordSideCapsule"
        source: Qt.point(call.sideBounds.x + call.sideBounds.width * 0.67,
            call.sideBounds.y + call.sideBounds.height / 2)
        targetBounds: Qt.rect(call.sideBounds.x + call.sideBounds.width - 42,
            call.sideBounds.y + (call.sideBounds.height - 32) / 2, 32, 32)
        amount: Math.min(call.exposed, Geometry.phase(call.split, 0.55, 0.96))
        enabled: call.session.connected && call.split > 0.92

        MicAction { objectName: "muteDiscordSide"; anchors.fill: parent; implicitHeight: 32 }
    }
}
