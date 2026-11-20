import QtQuick
import QtQuick.Controls
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

Item {
    id: notice
    required property var event
    required property var renderer
    required property var media
    required property bool allowed
    required property bool clearForDetails
    required property bool attached
    required property real topInset

    signal dismissed()

    readonly property bool active: allowed && !!event
    readonly property bool presenting: active || reveal > 0 || splitProgress > 0
    readonly property bool widePlayer: attached && renderer.lyricsView.wide
    readonly property bool splittingPlayer: active && clearForDetails && widePlayer
    readonly property bool movingPlayer: splittingPlayer || (!active && splitProgress > 0)
    readonly property real compactHeight: 76
    readonly property real detailsHeight: 176
    readonly property real soloWidth: Math.min(450, width - 48)
    readonly property real miniDiameter: 66
    readonly property real miniGap: 16
    readonly property rect expandedEnvelope: {
        const view = renderer.lyricsView
        const footprintWidth = widePlayer ? view.expandedBodySize.width
            : attached ? Math.min(renderer.host.settings.compactWidth, view.maxBody) : soloWidth
        return Qt.rect((width - footprintWidth) / 2, topInset, footprintWidth, detailsHeight)
    }

    property var lastEvent: null
    property real reveal: active ? 1 : 0
    property real detailProgress: presenting && clearForDetails ? 1 : 0
    property real splitProgress: splittingPlayer ? 1 : 0
    property real attachment: attached ? 1 : 0
    property real nudge: 0
    Behavior on reveal { NumberAnimation { duration: 560; easing.type: Easing.InOutCubic } }
    Behavior on detailProgress { NumberAnimation { duration: 460; easing.type: Easing.InOutCubic } }
    Behavior on splitProgress { NumberAnimation { duration: 820; easing.type: Easing.InOutCubic } }
    Behavior on attachment { NumberAnimation { duration: 360; easing.type: Easing.InOutCubic } }

    onEventChanged: {
        if (!event)
            return
        lastEvent = event
        if (active && attached && !widePlayer)
            attention.restart()
    }
    SequentialAnimation {
        id: attention
        NumberAnimation { target: notice; property: "nudge"; to: 4; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: notice; property: "nudge"; to: -2.5; duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { target: notice; property: "nudge"; to: 1.2; duration: 95; easing.type: Easing.InOutSine }
        NumberAnimation { target: notice; property: "nudge"; to: 0; duration: 115; easing.type: Easing.OutCubic }
    }

    readonly property real coverAmount: Math.max(Motion.smooth((reveal - 0.06) / 0.52),
        Motion.smooth(splitProgress / 0.42))
    readonly property real detailAmount: Motion.smooth(detailProgress)
    readonly property real bodyTaper: Geometry.mix(Geometry.taper(1 - reveal), renderer.playerTaper, attachment)
    readonly property real bodyRadius: Geometry.mix(
        Geometry.mix(compactHeight / 2, 36, detailAmount),
        Geometry.mix(renderer.radius, Geometry.mix(compactHeight / 2, 36, detailAmount), coverAmount),
        attachment)
    readonly property rect bodyBounds: {
        const height = Geometry.mix(compactHeight, detailsHeight, detailAmount)
        const solo = Geometry.pullToEdge(Qt.rect((width - soloWidth) / 2, topInset, soloWidth, height),
            1 - reveal, 0, 0)
        const body = renderer.playerHousing
        const widthTaken = (miniDiameter + miniGap) * Motion.smooth((splitProgress - 0.12) / 0.8)
        const playerBounds = Qt.rect(body.x + nudge * coverAmount, body.y, body.width - widthTaken,
            Geometry.mix(body.height, height, coverAmount))
        return Geometry.mixRect(solo, playerBounds, attachment)
    }
    readonly property rect miniBounds: {
        if (splitProgress <= 0.001)
            return Qt.rect(0, 0, 0, 0)
        const path = Motion.travel((splitProgress - 0.08) / 0.92)
        const body = renderer.playerHousing
        const cover = renderer.lyricsView.coverBounds
        const diameter = Geometry.mix(cover.width + 14, miniDiameter, path)
            * Motion.smooth(splitProgress / 0.13)
        const centerX = Geometry.mix(cover.x + cover.width / 2, body.x + body.width - miniDiameter / 2, path)
        const centerY = Geometry.mix(cover.y + cover.height / 2, body.y + 47, path)
            + 16 * Math.pow(Math.sin(Math.PI * path), 2)
        return Qt.rect(centerX - diameter / 2, centerY - diameter / 2, diameter, diameter)
    }
    readonly property real miniBlend: 40 * Motion.smooth(splitProgress / 0.18)
        * (1 - Motion.smooth((splitProgress - 0.7) / 0.3))
    readonly property real playerOpacity: movingPlayer
        ? 1 - Motion.smooth((splitProgress - 0.05) / 0.33) : 1 - coverAmount
    readonly property real playerScale: 1 - 0.42 * Motion.smooth(splitProgress / 0.4)
    readonly property point playerOffset: {
        if (splitProgress <= 0.001)
            return Qt.point(0, 0)
        const cover = renderer.lyricsView.coverBounds
        return Qt.point(miniBounds.x + miniBounds.width / 2 - cover.x - cover.width / 2,
            miniBounds.y + miniBounds.height / 2 - cover.y - cover.height / 2)
    }
    readonly property real textOpacity: movingPlayer
        ? Motion.smooth((splitProgress - 0.38) / 0.52) : Motion.smooth((reveal - 0.39) / 0.51)

    visible: presenting

    Item {
        id: words
        x: notice.bodyBounds.x
        y: notice.bodyBounds.y
        width: notice.bodyBounds.width
        height: notice.bodyBounds.height
        opacity: notice.textOpacity
        visible: opacity > 0.001
        clip: true

        readonly property real inset: width >= 330 ? 24 : 16
        readonly property real headerY: Math.max(0, Geometry.mix((height - 38) / 2, 19, notice.detailAmount))
        readonly property color ink: "#f1f9f5"
        readonly property color secondary: "#c3d8cf"
        readonly property color accent: "#a4e7cc"

        Rectangle {
            id: badge
            x: words.inset
            y: words.headerY
            width: 38
            height: width
            radius: 13
            color: "#442f7c65"
            border.color: "#727ac5a8"
            antialiasing: true
            Text {
                anchors.centerIn: parent
                text: "✓"
                color: words.accent
                font.pixelSize: 19
                font.weight: Font.DemiBold
            }
        }

        Column {
            x: badge.x + badge.width + 12
            y: words.headerY
            width: Math.max(1, closeButton.x - x - 8)
            spacing: 3

            Text {
                width: parent.width
                text: notice.lastEvent?.title ?? ""
                textFormat: Text.PlainText
                font.pixelSize: words.width >= 330 ? 17 : 15
                font.weight: Font.DemiBold
                color: words.ink
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: notice.lastEvent?.summary ?? ""
                textFormat: Text.PlainText
                font.pixelSize: 13
                color: words.accent
                elide: Text.ElideRight
            }
        }

        Button {
            id: closeButton
            x: words.width - words.inset - width
            y: words.headerY + 4
            width: 30
            height: width
            enabled: notice.active && words.opacity > 0.75
            Accessible.name: "Закрыть уведомление"
            background: Rectangle {
                radius: width / 2
                color: closeButton.down ? "#5571a692" : closeButton.hovered ? "#3371a692" : "transparent"
            }
            contentItem: Text {
                text: "×"
                color: closeButton.hovered ? words.ink : words.secondary
                font.pixelSize: 21
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: notice.dismissed()
        }

        Item {
            id: detail
            x: words.inset
            y: words.headerY + badge.height + 18
            width: Math.max(1, words.width - 2 * x)
            height: Math.max(0, words.height - y - 19)
            opacity: Motion.smooth((notice.detailAmount - 0.42) / 0.52)
            visible: opacity > 0.001 && height >= 24

            Rectangle {
                height: 1
                width: parent.width
                color: "#486db49b"
            }
            Text {
                width: parent.width
                y: Math.max(11, (footer.y - height) / 2)
                text: notice.lastEvent?.detail ?? ""
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: words.ink
                font.pixelSize: 14
            }
            Text {
                id: footer
                y: parent.height - height
                width: parent.width
                text: notice.lastEvent ? notice.lastEvent.source + "  ·  "
                    + Qt.formatTime(notice.lastEvent.sentAt, "HH:mm") : ""
                color: words.secondary
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }
    }

    DockMiniPlayer {
        id: mini
        x: notice.miniBounds.x + (notice.miniBounds.width - width) / 2
        y: notice.miniBounds.y + (notice.miniBounds.height - height) / 2
        scale: notice.miniBounds.width / width
        opacity: Motion.smooth((notice.splitProgress - 0.04) / 0.27)
        visible: opacity > 0.001
        player: notice.media.player
        artwork: notice.media.artUrl
        playing: notice.media.playing
        roundArtwork: notice.renderer.shaderAvailable
        accent: notice.renderer.colors.accent
        progress: notice.renderer.lyricsView.duration > 0
            ? notice.renderer.lyricsView.position / notice.renderer.lyricsView.duration : 0
        onTogglePlayback: notice.media.togglePlaying()
    }
}
