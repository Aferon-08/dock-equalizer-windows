import QtQuick

Item {
    id: root
    required property var settings
    required property var palette
    required property color secondary
    property var bands: []
    property real fraction: 0
    property real phase: 0
    property bool playing: false
    property bool indeterminate: false
    property bool seekable: false
    property bool circular: false
    signal seek(real fraction)

    readonly property bool plassglass: settings.progressStyle === "plassglass"
    readonly property real trackLeft: Math.min(4, width / 2)
    readonly property real trackWidth: Math.max(0, width - 2 * trackLeft)
    readonly property real ratio: isFinite(fraction) ? Math.max(0, Math.min(1, fraction)) : 0
    readonly property real thickness: circular ? 2.4 : (settings.progressThickness ?? 3)
    readonly property string rendererName: styleLoader.item?.objectName ?? ""
    readonly property real spectrumPeak: plassglass && !indeterminate ? (styleLoader.item?.peak ?? 0) : 0

    Loader {
        id: styleLoader
        anchors.fill: parent
        active: root.visible && root.opacity > 0.001 && root.trackWidth > 0
        sourceComponent: !root.plassglass ? materialRenderer
            : root.indeterminate && !root.circular ? unknownRenderer : plassglassRenderer
    }

    Component {
        id: materialRenderer
        WavyProgress {
            objectName: "materialProgressRenderer"
            circular: root.circular
            amplitude: root.circular ? 2.1 : (root.settings.progressAmplitude ?? 3.5)
            wavelength: root.circular ? 24 : (root.settings.progressWavelength ?? 30)
            thickness: root.thickness
            fraction: root.ratio
            playing: root.playing
            phase: root.phase
            indeterminate: root.indeterminate && !root.circular
            motionCurve: root.settings.motionCurve ?? []
            ink: root.palette.ink
            accent: root.palette.accent
        }
    }

    Component {
        id: plassglassRenderer
        Item {
            objectName: "plassglassProgressRenderer"
            readonly property real peak: spectrum.peak
            PlassglassProgress {
                id: spectrum
                x: root.circular ? 0 : root.trackLeft
                width: root.circular ? root.width : root.trackWidth
                height: root.height
                circular: root.circular
                fraction: root.ratio
                thickness: root.thickness
                palette: root.palette
                secondary: root.secondary
                playing: root.playing
                bands: root.bands
                style: root.settings.style ?? "wave"
                sensitivity: root.settings.sensitivity ?? 1
                leftBandsReversed: root.settings.leftSpectrumReversed !== false
                glassEnabled: root.settings.dockGlass !== false
                glowStrength: root.settings.glassLight ?? 1
                mirrored: root.settings.mirrorLeft !== false
                clock: root.phase * 1.8
                fadeDuration: root.settings.spectrumFade ?? 450
                motionCurve: root.settings.motionCurve ?? []
            }
        }
    }

    Component {
        id: unknownRenderer
        Item {
            Rectangle {
                x: root.trackLeft
                width: root.trackWidth
                height: root.thickness
                anchors.verticalCenter: parent.verticalCenter
                radius: height / 2
                color: Qt.alpha(root.palette.ink, 0.16)
                Rectangle {
                    width: parent.width * 0.18
                    height: parent.height
                    radius: height / 2
                    x: (parent.width - width) * (0.5 + 0.5 * Math.sin(root.phase * 2))
                    color: Qt.alpha(root.palette.ink, 0.36)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.seekable && !root.circular && !root.indeterminate && root.trackWidth > 0
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.seek(Math.max(0, Math.min(1, (mouse.x - root.trackLeft) / root.trackWidth)))
    }
}
