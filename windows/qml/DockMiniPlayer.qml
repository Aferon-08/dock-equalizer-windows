import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import "DockGeometry.js" as Geometry

Item {
    id: mini
    objectName: "dockMiniPlayer"
    required property var player
    required property url artwork
    required property real artworkOpacity
    required property real progressOpacity
    required property bool playing
    required property bool roundArtwork
    required property var host
    required property real progress
    required property real progressPhase
    readonly property real coverSize: 42
    property real artworkRoundness: 1
    readonly property string progressRenderer: ringProgress.rendererName
    readonly property real progressSpectrum: ringProgress.spectrumPeak

    signal togglePlayback()

    width: 66
    height: width
    transformOrigin: Item.Center

    DockProgress {
        id: ringProgress
        anchors.fill: parent
        opacity: mini.progressOpacity
        circular: true
        settings: mini.host.settings
        palette: mini.host.dock.palette
        secondary: mini.host.theme.accentMint || palette.ink
        bands: mini.host.working ? (mini.host.service?.bands ?? []) : []
        fraction: mini.progress
        playing: mini.playing
        phase: mini.progressPhase
    }

    Rectangle {
        id: cover
        anchors.centerIn: parent
        width: mini.coverSize
        height: width
        radius: Geometry.mix(9, width / 2, mini.artworkRoundness)
        opacity: mini.artworkOpacity
        color: "#a22c4f43"
        antialiasing: true
        layer.enabled: mini.roundArtwork
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: roundMask
        }
        Rectangle {
            id: roundMask
            anchors.fill: parent
            radius: cover.radius
            color: "white"
            visible: false
            layer.enabled: true
        }
        Image {
            id: image
            anchors.centerIn: parent
            width: mini.roundArtwork ? parent.width
                : Math.floor(Geometry.mix(parent.width, parent.width / Math.SQRT2, mini.artworkRoundness))
            height: width
            source: mini.artwork
            sourceSize.width: 112
            sourceSize.height: 112
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        Canvas {
            anchors.centerIn: parent
            width: 22
            height: width
            visible: image.status !== Image.Ready
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = "#eff9f4"
                ctx.strokeStyle = "#eff9f4"
                ctx.lineCap = "round"
                ctx.lineWidth = 1.9
                ctx.beginPath()
                ctx.arc(7.8, 15.9, 3.1, 0, 2 * Math.PI, false)
                ctx.fill()
                ctx.beginPath()
                ctx.moveTo(10, 16)
                ctx.lineTo(10, 4)
                ctx.quadraticCurveTo(11.6, 6.3, 16.5, 8.5)
                ctx.stroke()
            }
        }
    }

    Button {
        id: playback
        anchors.fill: parent
        anchors.margins: 4
        hoverEnabled: true
        enabled: !!mini.player?.canTogglePlaying
        Accessible.name: mini.playing ? "Приостановить музыку" : "Возобновить музыку"
        background: null
        contentItem: Item {
            opacity: playback.enabled && (playback.hovered || playback.visualFocus) ? 1 : 0
            Behavior on opacity {
                DockTransition { duration: 140; curve: mini.host.settings.motionCurve; standardEasing: Easing.OutCubic }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 36
                height: width
                radius: width / 2
                color: playback.down ? "#e1132921" : "#d11b382e"
                border.color: "#5dbdd8cf"
                antialiasing: true

                Row {
                    visible: mini.playing
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: 2
                        Rectangle {
                            width: 3.5
                            height: 13
                            radius: 1.3
                            color: "#f1f9f5"
                        }
                    }
                }

                Canvas {
                    visible: !mini.playing
                    anchors.centerIn: parent
                    width: 20
                    height: width
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.fillStyle = "#f1f9f5"
                        ctx.beginPath()
                        ctx.moveTo(7, 3.4)
                        ctx.lineTo(17, 10)
                        ctx.lineTo(7, 16.6)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
            }
        }
        HoverHandler {
            enabled: playback.enabled
            cursorShape: Qt.PointingHandCursor
        }
        onClicked: mini.togglePlayback()
    }
}
