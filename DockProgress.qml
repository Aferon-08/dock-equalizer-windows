pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var settings
    required property var palette
    required property color secondary
    property var bands: []
    property bool glassEnabled: true
    property real glowStrength: 1
    property real fraction: 0
    property real phase: 0
    property bool playing: false
    property bool indeterminate: false
    property bool seekable: false
    signal seek(real fraction)

    readonly property real trackLeft: Math.min(4, width / 2)
    readonly property real trackWidth: Math.max(0, width - 2 * trackLeft)
    readonly property real ratio: Number.isFinite(fraction) ? Math.max(0, Math.min(1, fraction)) : 0
    readonly property real positionX: trackLeft + ratio * trackWidth
    readonly property real weight: settings.progressThickness ?? 3
    readonly property bool plassglass: settings.progressStyle === "plassglass"

    Loader {
        anchors.fill: parent
        active: root.visible && root.opacity > 0.001 && !root.indeterminate && root.trackWidth > 0
        sourceComponent: root.plassglass ? plassglassRenderer : materialRenderer
    }
    Component {
        id: materialRenderer
        WavyProgress {
            objectName: "materialProgressRenderer"
            startX: root.trackLeft
            endX: root.trackLeft + root.trackWidth
            positionX: root.positionX
            amplitude: root.settings.progressAmplitude ?? 3.5
            wavelength: root.settings.progressWavelength ?? 30
            thickness: root.weight
            playing: root.playing
            phase: root.phase
            ink: root.palette.ink
            accent: root.palette.accent
        }
    }
    Component {
        id: plassglassRenderer
        Item {
            PlassglassProgress {
                objectName: "plassglassProgressRenderer"
                x: root.trackLeft
                width: root.trackWidth
                height: root.height
                fraction: root.ratio
                thickness: root.weight
                palette: root.palette
                secondary: root.secondary
                playing: root.playing
                bands: root.bands
                style: root.settings.style ?? "wave"
                sensitivity: root.settings.sensitivity ?? 1
                glassEnabled: root.glassEnabled
                glowStrength: root.glowStrength
                mirrored: root.settings.mirrorLeft !== false
                clock: root.phase * 1.8
                fadeDuration: root.settings.spectrumFade ?? 450
            }
        }
    }

    Rectangle {
        x: root.trackLeft
        width: root.trackWidth
        height: root.weight
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        visible: root.indeterminate
        color: Qt.alpha(root.palette.ink, 0.16)
        Rectangle {
            width: parent.width * 0.18
            height: parent.height
            radius: height / 2
            x: (parent.width - width) * (0.5 + 0.5 * Math.sin(root.phase * 2))
            color: Qt.alpha(root.palette.ink, 0.36)
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.seekable && !root.indeterminate && root.trackWidth > 0
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.seek(Math.max(0, Math.min(1, (mouse.x - root.trackLeft) / root.trackWidth)))
    }
}
