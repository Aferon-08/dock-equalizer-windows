import QtQuick

Item {
    id: root
    required property var host
    required property int channel
    property bool housingVisible: true
    property var palette: host.dock.palette
    readonly property bool ribbonAvailable: spectrum.useRibbon
    readonly property real level: spectrum.level
    property real ribbonClock: 0

    FrameAnimation {
        running: spectrum.visible && spectrum.useRibbon && spectrum.peak > 0.002
        onTriggered: root.ribbonClock += Math.min(frameTime, 0.05)
    }

    // Keep the housing still; only the small canvas inside is redrawn for audio.
    Rectangle {
        visible: root.housingVisible
        x: 0
        y: root.host.dock.capsule ? 1 : 3
        width: parent.width
        height: parent.height - 3
        radius: height / 2
        color: root.palette.shadow
    }
    Rectangle {
        id: housing
        width: parent.width
        height: parent.height - 3
        radius: height / 2
        color: root.housingVisible ? root.palette.fill : "transparent"
        border.color: root.palette.rim
        border.width: root.housingVisible ? root.palette.border : 0
        antialiasing: true

        Rectangle {
            visible: root.housingVisible
            anchors.fill: parent
            anchors.margins: root.palette.border + 2
            radius: height / 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(root.palette.ink.r, root.palette.ink.g, root.palette.ink.b, 0.16)
        }

        SpectrumShape {
            id: spectrum
            anchors.fill: parent
            anchors.margins: root.palette.border + 4
            visible: root.opacity > 0.001
            bands: root.host.service?.bands || []
            playing: root.host.working && root.host.service?.playing === true
            style: root.host.settings.style ?? "wave"
            sensitivity: root.host.settings.sensitivity ?? 1
            palette: root.palette
            secondary: root.host.theme.accentMint || root.palette.ink
            clock: root.ribbonClock
            channel: root.channel
            mirrored: root.channel === 0 && root.host.settings.mirrorLeft !== false
            fadeDuration: Math.min(root.host.settings.spectrumFade ?? 450,
                Math.max(120, (root.host.settings.collapseDelay || 600) - 100))
        }
    }
}
