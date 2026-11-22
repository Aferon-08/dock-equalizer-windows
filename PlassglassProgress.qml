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
    property bool leftBandsReversed: true
    property bool circular: false
    property real glowStrength: 1
    property real sensitivity: 1
    property string style: "wave"
    property real clock: 0
    property int fadeDuration: 450
    property var motionCurve: []
    readonly property real peak: circular ? arcSpectrum.peak : spectrum.peak

    Rectangle {
        visible: !root.circular
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
        visible: !root.circular && width > 0
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
            leftBandsReversed: root.leftBandsReversed
            allowShader: root.glassEnabled
            bands: root.bands
            playing: root.playing
            style: root.style
            sensitivity: root.sensitivity
            quietBoost: 0.25
            palette: root.palette
            secondary: root.secondary
            mirrored: root.mirrored
            clock: root.clock
            glowStrength: root.glowStrength
            fadeDuration: root.fadeDuration
            motionCurve: root.motionCurve
        }
    }

    Rectangle {
        visible: !root.circular
        x: played.width - width / 2
        width: 3
        height: Math.max(6, root.thickness + 2)
        anchors.verticalCenter: parent.verticalCenter
        radius: width / 2
        color: Qt.tint(root.palette.accent, Qt.alpha(root.palette.ink, .24))
    }

    Item {
        id: ring
        anchors.fill: parent
        visible: root.circular
        readonly property real radius: Math.max(0, Math.min(width, height) / 2 - 5)

        Canvas {
            id: ringTrack
            anchors.fill: parent
            function refresh() { if (visible && available) requestPaint() }
            onVisibleChanged: refresh()
            onAvailableChanged: refresh()
            onWidthChanged: refresh()
            onHeightChanged: refresh()
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (ring.radius <= 0)
                    return
                const start = -Math.PI / 2
                const finish = start + 2 * Math.PI * root.fraction
                ctx.lineCap = "round"
                ctx.lineWidth = root.thickness
                ctx.strokeStyle = Qt.alpha(root.palette.ink, 0.18)
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, ring.radius, start, start + 2 * Math.PI, false)
                ctx.stroke()
                if (root.fraction <= 0)
                    return
                ctx.strokeStyle = Qt.alpha(root.palette.accent, 0.86 - 0.52 * arcSpectrum.level)
                ctx.beginPath()
                ctx.arc(width / 2, height / 2, ring.radius, start, finish, false)
                ctx.stroke()
            }
            Connections {
                target: root
                function onFractionChanged() { ringTrack.refresh() }
                function onPaletteChanged() { ringTrack.refresh() }
                function onThicknessChanged() { ringTrack.refresh() }
            }
            Connections {
                target: arcSpectrum
                function onLevelChanged() { ringTrack.refresh() }
            }
        }

        SpectrumShape {
            id: arcSpectrum
            anchors.fill: parent
            visible: ring.radius > 0 && root.fraction * 2 * Math.PI * ring.radius >= 6
            circleRadius: ring.radius
            circleFraction: root.fraction
            drawBaseline: false
            channel: -1
            leftBandsReversed: root.leftBandsReversed
            allowShader: root.glassEnabled
            bands: root.bands
            playing: root.playing
            style: root.style
            sensitivity: root.sensitivity
            quietBoost: 0.25
            palette: root.palette
            secondary: root.secondary
            mirrored: root.mirrored
            clock: root.clock
            glowStrength: root.glowStrength
            fadeDuration: root.fadeDuration
            motionCurve: root.motionCurve
        }

        Item {
            anchors.fill: parent
            visible: ring.radius > 0
            rotation: root.fraction * 360
            Rectangle {
                width: 2.4
                height: 5.5
                radius: width / 2
                anchors.horizontalCenter: parent.horizontalCenter
                y: ring.height / 2 - ring.radius - height / 2
                color: Qt.tint(root.palette.accent, Qt.alpha(root.palette.ink, .24))
                antialiasing: true
            }
        }
    }
}
