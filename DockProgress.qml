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
    property real duration: 0
    property real phase: 0
    property bool playing: false
    property bool indeterminate: false
    property bool seekable: false
    property string trackIdentity: ""
    property string fontFamily: ""
    signal seek(real fraction)

    readonly property real trackLeft: Math.min(4, width / 2)
    readonly property real trackWidth: Math.max(0, width - 2 * trackLeft)
    readonly property real playbackRatio: Number.isFinite(fraction) ? clampRatio(fraction) : 0
    readonly property real ratio: scrubbing ? draftRatio : playbackRatio
    readonly property real positionX: trackLeft + ratio * trackWidth
    readonly property real weight: settings.progressThickness ?? 3
    readonly property bool plassglass: settings.progressStyle === "plassglass"
    readonly property bool inputReady: visible && enabled && seekable && !indeterminate && duration > 0 && trackWidth > 0
    readonly property bool wantsKeyboard: inputReady && (hoverZone.hovered || scrubbing) && !keyboardDismissed
    readonly property bool previewing: inputReady && !keyboardDismissed && (scrubbing || hoverZone.hovered)
    readonly property real previewRatio: scrubbing ? draftRatio : ratioAt(hoverZone.point.position.x)
    readonly property real previewSeconds: previewRatio * duration
    property bool scrubbing: false
    property real draftRatio: 0
    property bool keyboardDismissed: false

    activeFocusOnTab: inputReady
    Accessible.role: Accessible.Slider
    Accessible.name: qsTr("Позиция воспроизведения")
    Accessible.description: qsTr("Стрелки — перемотка на 5 секунд. Home и End — начало и конец.")
    Accessible.ignored: !inputReady

    function clampRatio(value) { return Math.max(0, Math.min(1, value)) }
    function ratioAt(x) { return trackWidth > 0 ? clampRatio((x - trackLeft) / trackWidth) : 0 }
    function timeText(seconds) {
        const value = Math.max(0, Math.floor(seconds || 0))
        return Math.floor(value / 60) + ":" + String(value % 60).padStart(2, "0")
    }

    // Preview moves only the progress indicator. Lyrics and playback keep their clock.
    onDurationChanged: scrubbing = false
    onTrackIdentityChanged: scrubbing = false
    onInputReadyChanged: if (!inputReady) {
        scrubbing = false
        focus = false
    }
    Keys.onPressed: event => {
        if (!inputReady) return
        if (event.key === Qt.Key_Escape) {
            if (!scrubbing && !activeFocus) return
            scrubbing = false
            keyboardDismissed = true
            focus = false
            event.accepted = true
            return
        }
        if (scrubbing || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) return
        switch (event.key) {
        case Qt.Key_Left: seek(clampRatio(playbackRatio - 5 / duration)); break
        case Qt.Key_Right: seek(clampRatio(playbackRatio + 5 / duration)); break
        case Qt.Key_Home: seek(0); break
        case Qt.Key_End: seek(1); break
        default: return
        }
        event.accepted = true
    }

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

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: "transparent"
        border.color: Qt.alpha(root.palette.accent, .7)
        visible: root.activeFocus && root.inputReady && !root.scrubbing
    }

    Rectangle {
        id: preview
        objectName: "progressTimePreview"
        visible: root.previewing
        width: Math.min(root.width, previewLabel.implicitWidth + 16)
        height: 21
        x: Math.max(0, Math.min(root.width - width,
            root.trackLeft + root.previewRatio * root.trackWidth - width / 2))
        y: -height
        radius: 7
        color: root.palette.module ?? (Qt.darker(root.palette.accent, 3))
        border.color: Qt.alpha(root.palette.accent, .5)
        Text {
            id: previewLabel
            anchors.centerIn: parent
            text: root.timeText(root.previewSeconds)
            color: root.palette.ink
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }

    HoverHandler {
        id: hoverZone
        enabled: root.inputReady
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (!hovered) {
            root.keyboardDismissed = false
            if (!root.scrubbing) root.focus = false
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.inputReady
        preventStealing: true
        onPressed: mouse => {
            root.keyboardDismissed = false
            root.forceActiveFocus(Qt.MouseFocusReason)
            root.draftRatio = root.ratioAt(mouse.x)
            root.scrubbing = true
        }
        onPositionChanged: mouse => {
            if (root.scrubbing) root.draftRatio = root.ratioAt(mouse.x)
        }
        onReleased: mouse => {
            if (!root.scrubbing) return
            const target = root.ratioAt(mouse.x)
            root.scrubbing = false
            if (root.inputReady) root.seek(target)
            if (!hoverZone.hovered) root.focus = false
        }
        onCanceled: root.scrubbing = false
    }
}
