import QtQuick
import QtQuick.Controls
import QtQml.Models
import "BeatTracker.js" as BeatTracker

Window {
    id: window
    objectName: "soundbarMainWindow"
    required property var desktop
    required property var mediaSessions
    required property var systemAudio
    flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
        | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint
    title: "Sekai Soundbar"
    color: "transparent"
    readonly property rect workArea: desktop.workArea
    width: Math.min(1088, workArea.width)
    height: Math.min(workArea.height, Math.ceil(stage.height * stage.scale))
    x: workArea.x + Math.floor((workArea.width - width) / 2)
    y: workArea.y
    visible: workArea.width > 0 && !desktop.fullscreenActive
    onVisibleChanged: {
        if (!visible && panelMenu.opened)
            panelMenu.close()
    }
    onClosing: Qt.quit()

    palette.window: "#172829"
    palette.windowText: "#e8f4ee"
    palette.text: "#e8f4ee"
    palette.buttonText: "#e8f4ee"
    palette.button: "#28433a"
    palette.base: "#172829"
    palette.highlight: "#96dcc0"
    palette.highlightedText: "#101b18"

    property bool demoPlaying: true
    property bool lyricsExpanded: false
    property real elapsed: 0
    readonly property bool smokeMode: Qt.application.arguments.indexOf("--smoke-test") >= 0
    readonly property bool demoMode: smokeMode || Qt.application.arguments.indexOf("--demo-preview") >= 0
    readonly property var media: demoMode ? demoMedia : mediaSessions
    property int smokePhase: 0
    property real smokeStarted: 0
    property bool smokeCapturePending: false

    readonly property rect bodyRegion: {
        const padding = 26
        return scaledRect(pill.x + wings.lyricsView.swipeX - padding,
            pill.y + wings.lyricsView.swipeY - padding, pill.width + 2 * padding,
            pill.capHeight + 2 * padding)
    }
    readonly property rect leftRegion: capsuleRegion(-1)
    readonly property rect rightRegion: capsuleRegion(1)
    readonly property real regionRadius: (wings.radius + 26) * stage.scale
    onBodyRegionChanged: Qt.callLater(updatePanelRegion)
    onLeftRegionChanged: Qt.callLater(updatePanelRegion)
    onRightRegionChanged: Qt.callLater(updatePanelRegion)
    onRegionRadiusChanged: Qt.callLater(updatePanelRegion)
    onHeightChanged: Qt.callLater(updatePanelRegion)

    function scaledRect(x, y, width, height) {
        const scale = stage.scale
        return Qt.rect(x * scale, y * scale, width * scale, height * scale)
    }

    function capsuleRegion(side) {
        if (wings.phase < 0.01)
            return Qt.rect(0, 0, 0, 0)
        const padding = 8
        const centerX = stage.width / 2 + wings.lyricsView.swipeX
            + side * (wings.bodyWidth / 2 + wings.outward)
        const centerY = pill.y + pill.capHeight / 2 + wings.lyricsView.swipeY
        return scaledRect(centerX - wings.dropletLength / 2 - padding,
            centerY - wings.thickness / 2 - padding, wings.dropletLength + 2 * padding,
            wings.thickness + 2 * padding)
    }

    function updatePanelRegion() {
        desktop.setPanelRegion(window, bodyRegion, regionRadius, leftRegion, rightRegion)
    }

    function spectrumAt(stamp) {
        return Array.from({length: 64}, function(_, i) {
            return Math.round(70 + 180 * Math.pow((1 + Math.sin(i * 0.41 + stamp * 5.8)) * 0.5, 3))
        })
    }

    function restartDemo() {
        demoPlayer.position = 2.2
        elapsed = 0
        demoPlaying = true
        visualizerService.demoBands = spectrumAt(0)
    }

    function failSmoke(message) {
        smokeTimer.stop()
        console.error("FAIL standalone soundbar: " + message)
        Qt.exit(1)
    }

    function captureSmoke(label, completed) {
        smokeCapturePending = true
        const accepted = stage.grabToImage(function(result) {
            smokeCapturePending = false
            if (!result || !String(result.url).length) {
                failSmoke(label + " scene capture failed")
                return
            }
            console.log("PASS standalone " + label + " scene, width=" + pill.width.toFixed(1)
                        + ", height=" + pill.height.toFixed(1))
            completed()
        })
        if (!accepted) {
            smokeCapturePending = false
            failSmoke(label + " scene capture could not start")
        }
    }

    QtObject {
        id: demoPlayer
        property bool lengthSupported: true
        property real length: 120
        property bool positionSupported: true
        property bool canSeek: true
        property bool canGoPrevious: true
        property bool canGoNext: true
        property bool canTogglePlaying: true
        property bool volumeSupported: true
        property bool canControl: true
        property real volume: 0.8
        property real position: 2.2
        property string trackKey: "sample"
        property real previousVolume: 0.8
        function positionNow() { return position }
        function seek(seconds) { position = seconds }
        function toggleMute() {
            if (volume > 0) {
                previousVolume = volume
                volume = 0
            } else {
                volume = previousVolume
            }
        }
    }

    QtObject {
        id: demoMedia
        property var player: demoPlayer
        readonly property bool playing: window.demoPlaying
        readonly property string title: "A little light"
        readonly property string artist: "Sekai Soundbar"
        property string artUrl: ""
        function togglePlaying() { window.demoPlaying = !window.demoPlaying }
        function next() { window.restartDemo() }
        function previous() { window.restartDemo() }
        function changeVolume(direction) {
            demoPlayer.volume = Math.max(0, Math.min(1, demoPlayer.volume + direction * 0.05))
        }
    }

    QtObject {
        id: demoLyrics
        property string status: "ready"
        readonly property var lastArgs: [demoMedia.artist, demoMedia.title]
        property int syncTotal: 0
        property string cacheScript: ""
        property string trackId: "demo"
        property var lines: [
            {t: 0, text: "A little light begins to glow", marks: [{cs: 0, t: 0}, {cs: 2, t: 0.4}, {cs: 9, t: 1.2}, {cs: 15, t: 2.1}, {cs: 22, t: 2.8}, {cs: 25, t: 3.2}]},
            {t: 4, text: "It follows every word we know", marks: [{cs: 0, t: 4}, {cs: 3, t: 4.5}, {cs: 11, t: 5.3}, {cs: 17, t: 6.1}, {cs: 22, t: 6.8}, {cs: 25, t: 7.4}]},
            {t: 8, text: "Across the glass and into blue", marks: [{cs: 0, t: 8}, {cs: 7, t: 8.6}, {cs: 11, t: 9.1}, {cs: 17, t: 9.8}, {cs: 21, t: 10.5}, {cs: 26, t: 11.1}]},
            {t: 12, text: "A tiny world that moves with you", marks: [{cs: 0, t: 12}, {cs: 2, t: 12.4}, {cs: 7, t: 13}, {cs: 13, t: 13.5}, {cs: 18, t: 14}, {cs: 24, t: 14.7}, {cs: 29, t: 15.2}]},
            {t: 17, text: "Let every little spark shine through"}
        ]
    }

    QtObject {
        id: visualizerService
        readonly property bool playing: window.demoMode ? window.demoPlaying : window.systemAudio.audible
        readonly property var bands: window.demoMode ? demoBands : window.systemAudio.bands
        property var demoBands: window.demoMode ? window.spectrumAt(0) : []
        property var beatState: BeatTracker.reset()
        readonly property real beatPulse: window.demoMode
            ? (playing ? Math.max(0, Math.sin(window.elapsed * 7)) : 0)
            : (beatState.pulse || 0)
        readonly property real beatBpm: window.demoMode ? 118 : beatState.bpm
        readonly property real beatConfidence: window.demoMode ? 0.9 : beatState.confidence
        property bool profileFrames: false
        property var wordtimes: null
        property var durationCache: ({})
        function resetRhythm() { beatState = BeatTracker.reset() }
    }

    QtObject {
        id: demoHost
        property bool working: true
        property var service: visualizerService
        property QtObject theme: QtObject {
            property string fontFamily: "Segoe UI"
            property string iconFont: ""
            property color accentMint: "#96dcc0"
        }
        property QtObject settings: QtObject {
            property bool enabled: true
            property real width: 200
            property real height: 38
            property real gap: 12
            property real sensitivity: 1.25
            property string style: "wave"
            property bool dockGlass: true
            property real glassOpacity: 0.78
            property real glassRefraction: 1
            property real glassBlur: 3.8
            property real glassDarkening: 0.23
            property real glassLight: 1
            property int collapseDelay: 600
            property bool lyrics: true
            property bool expandLyrics: true
            property real lyricsWidth: 560
            property bool autoSpotify: false
            property bool multivoice: true
            property int openDuration: 900
            property int closeDuration: 620
            property real spring: 1.6
            property int fusionDuration: 850
            property int outlineDuration: 1050
            property int lightFade: 450
            property bool mirrorLeft: true
            property int spectrumFade: 450
            property real compactWidth: 480
            property real voiceWidth: 80
            property real voiceHeight: 28
            property real lyricFontSize: 17
            property int lyricFade: 240
            property int expandDuration: 850
            property real playerSpring: 1.2
            property int followDelay: 190
            property int trailDelay: 230
            property int mistDelay: 300
            property real orbitRadius: 23
            property real progressAmplitude: 3.5
            property real progressWavelength: 30
            property real progressThickness: 3
        }
        property QtObject dock: QtObject {
            property var item: pill
            property bool vertical: false
            property bool capsule: true
            property string look: "capsule"
            readonly property real radius: Math.min(pill.width, pill.height - 4) / 2
            property real shadow: 4
            property bool asleep: false
            property var mediaSource: window.media
            property var lyrics: window.demoMode ? demoLyrics : null
            property bool hovered: false
            property bool editing: false
            readonly property bool desktopEmpty: window.lyricsExpanded
            property string screenName: "soundbar"
            property real baseCapHeight: 69
            property real baseWidth: 432
            readonly property real stageWidth: stage.width
            property QtObject palette: QtObject {
                property color fill: "#101b18"
                property color rim: "#284a3d"
                property color shadow: "#060d0a"
                property color ink: "#e8f4ee"
                property color accent: "#96dcc0"
                property real border: 3
                property real ringWidth: 3
                property color ring: "#101b18"
            }
        }
    }

    Item {
        id: stage
        width: Math.max(600, window.width)
        height: pill.y + pill.height + 32 + Math.max(0, wings.lyricsView.swipeY)
        scale: window.width / width
        transformOrigin: Item.TopLeft

        MouseArea {
            x: pill.x + wings.lyricsView.swipeX
            y: pill.y + wings.lyricsView.swipeY
            width: pill.width
            height: pill.capHeight
            enabled: !!window.media.player
            cursorShape: Qt.PointingHandCursor
            onClicked: window.lyricsExpanded = !window.lyricsExpanded
        }

        DockWings {
            id: wings
            objectName: "standaloneDockWings"
            anchors.fill: parent
            host: demoHost
        }
        Item {
            id: pill
            objectName: "standaloneDockBody"
            width: demoHost.dock.baseWidth + wings.lyricsWidthExtra
            height: 73 + wings.lyricsHeightExtra
            x: (parent.width - width) / 2
            y: 8
            readonly property real capWidth: width
            readonly property real capHeight: height - 4
            property bool bare: wings.ownsHousing
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: wings.iconsOffset / 2
                scale: wings.iconsScale
                opacity: wings.iconsOpacity
                text: window.media.player ? "Sekai Soundbar"
                    : visualizerService.playing ? "Системный звук" : window.mediaSessions.statusText
                color: "#e8f4ee"
                font.family: demoHost.theme.fontFamily
                font.pixelSize: 15
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => panelMenu.popup(mouse.x, mouse.y)
    }
    Menu {
        id: panelMenu
        popupType: Popup.Window
        MenuItem {
            text: window.lyricsExpanded ? "Свернуть лирику" : "Развернуть лирику"
            enabled: !!window.media.player
            onTriggered: window.lyricsExpanded = !window.lyricsExpanded
        }
        MenuItem {
            text: window.media.playing ? "Пауза" : "Воспроизвести"
            enabled: !!window.media.player && window.media.player.canTogglePlaying
            onTriggered: window.media.togglePlaying()
        }
        Menu {
            id: sourcesMenu
            title: "Источник"
            enabled: !window.demoMode && window.mediaSessions.sessions.length > 0
            MenuItem {
                text: "Автоматически"
                checkable: true
                checked: window.mediaSessions.preference === ""
                onTriggered: window.mediaSessions.selectSession("")
            }
            Instantiator {
                model: window.mediaSessions.sessions
                delegate: MenuItem {
                    required property var modelData
                    text: modelData.label
                    checkable: true
                    checked: window.mediaSessions.preference === modelData.id
                    onTriggered: window.mediaSessions.selectSession(modelData.id)
                }
                onObjectAdded: (index, item) => sourcesMenu.insertItem(index + 1, item)
                onObjectRemoved: (index, item) => sourcesMenu.removeItem(item)
            }
        }
        MenuItem {
            visible: !window.demoMode && window.mediaSessions.commandError !== ""
            height: visible ? implicitHeight : 0
            enabled: false
            text: window.mediaSessions.commandError
        }
        MenuSeparator {}
        MenuItem {
            text: "Выход"
            onTriggered: Qt.quit()
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: window.demoMode && window.demoPlaying && !window.smokeMode
        onTriggered: {
            window.elapsed += 0.05
            demoPlayer.position += 0.05
            if (demoPlayer.position >= 22) demoPlayer.position = 0
            visualizerService.demoBands = window.spectrumAt(window.elapsed)
        }
    }

    Timer {
        interval: 33
        repeat: true
        running: !window.demoMode && window.systemAudio.audible
        onTriggered: visualizerService.beatState = BeatTracker.update(
            visualizerService.beatState, visualizerService.bands, Date.now())
        onRunningChanged: if (!running) visualizerService.resetRhythm()
    }

    Timer {
        id: smokeTimer
        interval: 100
        repeat: true
        onTriggered: {
            const wait = Date.now() - window.smokeStarted
            if (wait > 8000) {
                window.failSmoke("layout did not settle in phase " + window.smokePhase)
                return
            }
            if (window.smokeCapturePending) return
            if (window.smokePhase === 0 && wait >= 1400) {
                if (window.y !== window.workArea.y || window.color.a !== 0
                        || Math.abs(window.x + window.width / 2
                            - window.workArea.x - window.workArea.width / 2) > 1
                        || !(window.flags & Qt.FramelessWindowHint)
                        || !(window.flags & Qt.WindowStaysOnTopHint)) {
                    window.failSmoke("panel is not frameless, transparent and centered on the top edge")
                    return
                }
                if (!wings.visible || !wings.ownsHousing || !isFinite(pill.width)
                        || Math.abs(pill.width - Math.min(demoHost.settings.compactWidth,
                            wings.lyricsView.maxBody)) > 0.5
                        || wings.suppressMediaKey || wings.reveal < 0.95
                        || !JSON.parse(wings.lyricsView.diagnostics()).trackHeaderVisible
                        || visualizerService.bands.length !== 64) return
                window.captureSmoke("compact", function() {
                    demoLyrics.status = "ready"
                    window.lyricsExpanded = true
                    window.smokePhase = 1
                    window.smokeStarted = Date.now()
                })
            } else if (window.smokePhase === 1 && wait >= 1800) {
                const lyrics = JSON.parse(wings.lyricsView.diagnostics())
                if (!wings.suppressMediaKey || wings.lyricsHeightExtra <= 100
                        || Math.abs(pill.width - Math.min(demoHost.settings.lyricsWidth,
                            wings.lyricsView.maxBody)) > 0.5
                        || !lyrics.wide || !lyrics.visible
                        || !demoLyrics.lines.some(line => line.text === lyrics.text)) return
                window.captureSmoke("expanded lyrics", function() {
                    smokeTimer.stop()
                    console.log("PASS standalone soundbar smoke test")
                    Qt.exit(0)
                })
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(updatePanelRegion)
        if (smokeMode) {
            restartDemo()
            demoLyrics.status = "none"
            smokeStarted = Date.now()
            smokeTimer.start()
        }
    }
}
