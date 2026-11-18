import QtQuick

Item {
    id: root
    required property real fraction
    required property var palette
    required property color secondary
    required property var bands
    property real thickness: 3
    property bool playing: false
    property bool glassEnabled: true
    property bool mirrored: true
    property real glowStrength: 1
    property real sensitivity: 1
    property string style: "wave"
    property real clock: 0
    property int fadeDuration: 450

    Rectangle {
        width: parent.width
        height: root.thickness
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: Qt.alpha(root.palette.ink, 0.18)
    }

    Item {
        id: played
        width: root.fraction * root.width
        height: root.height
        visible: width > 0
        clip: true

        Rectangle {
            width: parent.width
            height: root.thickness
            anchors.verticalCenter: parent.verticalCenter
            radius: height / 2
            color: Qt.alpha(root.palette.accent, 0.86 - 0.52 * spectrum.level)
        }

        Rectangle {
            anchors.fill: spectrum
            visible: root.glassEnabled && !spectrum.useRibbon && opacity > 0.001
            opacity: Math.min(0.46, Math.sqrt(spectrum.peak) * root.glowStrength * 0.42)
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(root.secondary, 0) }
                GradientStop { position: .45; color: root.palette.accent }
                GradientStop { position: .60; color: Qt.alpha(root.secondary, .65) }
                GradientStop { position: 1; color: Qt.alpha(root.secondary, 0) }
            }
        }

        SpectrumShape {
            id: spectrum
            objectName: "progressSpectrum"
            anchors.fill: parent
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            visible: width >= 6
            drawBaseline: false
            channel: -1
            allowShader: root.glassEnabled
            bands: root.bands
            playing: root.playing
            style: root.style
            sensitivity: root.sensitivity
            palette: root.palette
            secondary: root.secondary
            mirrored: root.mirrored
            clock: root.clock
            glowStrength: root.glowStrength
            fadeDuration: root.fadeDuration
        }
    }

    Rectangle {
        x: played.width - width / 2
        width: 3
        height: Math.max(6, root.thickness + 2)
        anchors.verticalCenter: parent.verticalCenter
        radius: width / 2
        color: Qt.tint(root.palette.accent, Qt.alpha(root.palette.ink, .24))
    }
}
