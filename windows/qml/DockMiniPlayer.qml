import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Item {
    id: mini
    required property var player
    required property url artwork
    required property bool playing
    required property bool roundArtwork
    required property color accent
    required property real progress

    signal togglePlayback()

    width: 66
    height: width

    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: width / 2
        color: "transparent"
        border.color: "#699ccabc"
        antialiasing: true
    }

    Canvas {
        id: ring
        anchors.fill: parent
        anchors.margins: 3
        Connections {
            target: mini
            function onProgressChanged() {
                if (mini.visible)
                    ring.requestPaint()
            }
            function onAccentChanged() { ring.requestPaint() }
            function onVisibleChanged() { if (mini.visible) ring.requestPaint() }
        }
        onPaint: {
            const brush = getContext("2d")
            brush.clearRect(0, 0, width, height)
            const fraction = Math.max(0, Math.min(1, mini.progress))
            if (fraction <= 0 || !isFinite(fraction))
                return
            brush.beginPath()
            brush.lineWidth = 2.4
            brush.lineCap = "round"
            brush.strokeStyle = mini.accent
            brush.arc(width / 2, height / 2, width / 2 - 2, -Math.PI / 2,
                (-0.5 + 2 * fraction) * Math.PI, false)
            brush.stroke()
        }
    }

    Rectangle {
        id: cover
        anchors.centerIn: parent
        width: mini.roundArtwork ? 46 : 38
        height: width
        radius: width / 2
        color: "#a22c4f43"
        layer.enabled: mini.roundArtwork
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: roundMask
        }
        Rectangle {
            id: roundMask
            anchors.fill: parent
            radius: width / 2
            color: "white"
            visible: false
            layer.enabled: true
        }
        Image {
            id: image
            anchors.fill: parent
            source: mini.artwork
            sourceSize.width: 112
            sourceSize.height: 112
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Text {
            anchors.centerIn: parent
            visible: image.status !== Image.Ready
            text: "♪"
            color: "#eff9f4"
            font.pixelSize: 23
        }
    }

    Button {
        id: playback
        anchors.fill: parent
        anchors.margins: 5
        enabled: !!mini.player?.canTogglePlaying
        Accessible.name: mini.playing ? "Приостановить музыку" : "Возобновить музыку"
        background: Rectangle {
            radius: width / 2
            color: playback.down ? "#bb122c23" : playback.hovered ? "#99122c23" : "transparent"
        }
        contentItem: Text {
            text: mini.playing ? "Ⅱ" : "▶"
            color: "#f1f9f5"
            font.pixelSize: 19
            opacity: playback.hovered || playback.visualFocus ? 1 : 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        onClicked: mini.togglePlayback()
    }
}
