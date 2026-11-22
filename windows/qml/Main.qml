import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs as Dialogs
import QtQml.Models
import "BeatTracker.js" as BeatTracker

Window {
    id: window
    objectName: "soundbarMainWindow"
    required property var desktop
    required property var mediaSessions
    required property var systemAudio
    required property var lyricsImport
    required property var lyricsSearch
    required property var lyricsAlignment
    required property var appearance
    required property var appState
    flags: Qt.Tool | Qt.FramelessWindowHint
        | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint
    title: "Sekai Soundbar"
    color: "transparent"
    readonly property rect workArea: desktop.workArea
    width: Math.min(1088, workArea.width)
    height: Math.min(workArea.height, Math.ceil(stage.height * stage.scale))
    x: workArea.x + Math.floor((workArea.width - width) / 2)
    y: workArea.y
    visible: workArea.width > 0 && !desktop.fullscreenActive && (presence.showing || wings.noticeVisible)
    onVisibleChanged: {
        if (visible) {
            Qt.callLater(updateExpandedRegion)
        } else {
            if (menuLoader && menuLoader.item && menuLoader.item.visible)
                menuLoader.item.dismiss()
        }
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
    property bool smokeNoSession: false
    property bool lyricsExpanded: !smokeMode
    readonly property bool expandedDock: lyricsExpanded && expandedSpaceReady
    readonly property bool expansionClear: !desktop.fullscreenActive
        && !(smokeMode ? smokeObstructed : desktop.expandedObstructed)
    property bool expandedSpaceReady: false
    onExpansionClearChanged: if (!expansionClear) expandedSpaceReady = false
    readonly property bool notificationClear: !desktop.fullscreenActive
        && workArea.height >= (pill.y + noticeLayer.detailsHeight) * stage.scale
        && !(smokeMode ? smokeObstructed : desktop.notificationObstructed)
    property bool notificationSpaceReady: false
    onNotificationClearChanged: if (!notificationClear) notificationSpaceReady = false
    property bool trayPreview: false
    readonly property bool playbackActive: !!media.player && media.playing
    readonly property bool playbackPaused: !!media.player && media.paused
    onPlaybackActiveChanged: if (playbackActive) trayPreview = false
    readonly property bool swipeDismissed: wings.lyricsView.dismissedUntilPlay
    onSwipeDismissedChanged: if (swipeDismissed) trayPreview = false
    property real elapsed: 0
    readonly property bool smokeMode: Qt.application.arguments.indexOf("--smoke-test") >= 0
    readonly property bool demoMode: smokeMode || Qt.application.arguments.indexOf("--demo-preview") >= 0
    readonly property bool desktopGlassAvailable: !smokeMode && wings.shaderAvailable
        && stage.GraphicsInfo.api === GraphicsInfo.Direct3D11
    readonly property var media: demoMode ? demoMedia : mediaSessions
    readonly property DiscordCallPreview discordPreview: appState.discordPreview
    readonly property string activeTrackKey: media.player ? media.player.trackKey : ""
    readonly property var localLyrics: appState.localLyrics
    readonly property var onlineLyrics: !demoMode && lyricsSearch.trackKey === activeTrackKey
        && lyricsSearch.document.ok === true ? lyricsSearch.document : null
    readonly property var timingDocument: localLyrics && localLyrics.key === activeTrackKey
        ? localLyrics.document : onlineLyrics
    readonly property var captureBackdrop: wings.backdropItem
    onLocalLyricsChanged: if (localLyrics?.key === activeTrackKey) lyricsExpanded = true
    onActiveTrackKeyChanged: {
        if (activeTrackKey === "")
            trayPreview = false
        if (matchPicker && matchPicker.opened)
            matchPicker.close()
        if (demoMode && localLyrics && localLyrics.key !== activeTrackKey)
            appState.localLyrics = null
        if (!smokeMode)
            lyricsExpanded = true
    }
    property url smokeLrc
    property url smokeWordtime
    readonly property bool smokeImports: smokeMode && smokeLrc.toString() !== "" && smokeWordtime.toString() !== ""
    property int smokePhase: 0
    onSmokePhaseChanged: if (smokeMode) console.info("Standalone soundbar smoke phase", smokePhase)
    property real smokeStarted: 0
    property bool smokeCapturePending: false
    property real smokeLandingTime: 0
    property real smokeFirstMarkerX: 0
    property bool smokeObstructed: false
    property bool smokeHoldOpen: true
    property bool smokeSawGlassNeck: false
    property bool smokeSawPackedEntrance: false
    property bool smokeTestedWingResize: false
    property rect smokeCompactWing: Qt.rect(0, 0, 0, 0)
    property bool smokeSawStaggeredTuck: false
    property bool smokeSawReleaseSpring: false
    property bool smokeSawStaggeredReturn: false
    readonly property var smokeReturnSprings: new Set()
    property rect smokeCallHome: Qt.rect(0, 0, 0, 0)
    property bool smokeSawCallExit: false
    property bool smokeSawCallUnfold: false
    property bool smokeSawCallSlide: false
    property bool smokeSawCallNeck: false

    DockPresence {
        id: presence
        playing: window.playbackActive
        paused: window.playbackPaused
        dismissed: window.swipeDismissed || (noticeLayer.miniPauseExpired && !window.trayPreview)
            || (callLayer.retiring && !window.media.player && !window.appState.dockNotification)
        fullscreen: window.desktop.fullscreenActive
        idleDelay: demoHost.settings.collapseDelay
        pauseDelay: window.smokeMode ? 1700 : 60000
        holdOpen: window.trayPreview
            || window.discordPreview.active
            || (callLayer.retiring && !!window.appState.dockNotification)
            || noticeLayer.keepPausedMini
            || (window.smokeMode && window.smokeHoldOpen)
            || (menuLoader.item?.visible ?? false)
            || lyricsPicker.visible || lyricsMessage.visible || alignmentDialog.visible
            || matchPicker.visible || wings.lyricsView.swipeDragging
    }
    Timer {
        interval: 400
        running: window.expansionClear && !window.expandedSpaceReady
        onTriggered: window.expandedSpaceReady = true
    }
    Timer {
        interval: 400
        running: window.notificationClear && !window.notificationSpaceReady
        onTriggered: window.notificationSpaceReady = true
    }

    readonly property rect bodyRegion: {
        if (wings.noticeVisible && !desktop.fullscreenActive) {
            const body = wings.housingRect
            const pad = noticeGlowMargin
            return scaledRect(body.x - pad, body.y - pad, body.width + 2 * pad, body.height + 2 * pad)
        }
        const padding = 26
        if (callLayer.presenting) {
            const body = wings.playerHousing
            return scaledRect(body.x - padding, body.y - padding,
                body.width + 2 * padding, body.height + 2 * padding)
        }
        if (!presence.interactive)
            return Qt.rect(0, 0, 0, 0)
        return scaledRect(pill.x + wings.lyricsView.swipeX - padding,
            pill.y + wings.lyricsView.swipeY - padding, pill.width + 2 * padding,
            pill.capHeight + 2 * padding)
    }
    readonly property rect leftRegion: capsuleRegion(-1)
    readonly property rect rightRegion: capsuleRegion(1)
    readonly property rect miniPlayerRegion: {
        const body = wings.noticeVisible ? noticeLayer.miniBounds : Qt.rect(0, 0, 0, 0)
        return scaledRect(body.x, body.y, body.width, body.height)
    }
    readonly property rect miniPlayerNeckRegion: {
        const body = wings.noticeVisible ? noticeLayer.neckBounds : Qt.rect(0, 0, 0, 0)
        return scaledRect(body.x, body.y, body.width, body.height)
    }
    readonly property rect sideCallRegion: {
        const body = callLayer.sideBounds
        return scaledRect(body.x, body.y, body.width, body.height)
    }
    readonly property rect sideCallNeckRegion: {
        const body = callLayer.sideNeck
        return scaledRect(body.x, body.y, body.width, body.height)
    }
    readonly property real noticeGlowMargin: !noticeLayer.usesCallLayout && wings.shaderAvailable && wings.fusion > 0.001
        && wings.edgeLight > 0.025 && wings.material.light > 0 ? 22 : 0
    readonly property real regionRadius: (wings.noticeVisible ? wings.housingRadius + noticeGlowMargin
        : wings.radius + 26) * stage.scale
    readonly property rect expandedRegion: {
        const size = callLayer.presenting && callLayer.conversation
            ? Qt.size(callLayer.expandedWidth, callLayer.expandedHeight)
            : wings.lyricsView.expandedBodySize
        return scaledRect((stage.width - size.width) / 2, pill.y, size.width, size.height)
    }
    readonly property rect notificationRegion: {
        const body = noticeLayer.expandedEnvelope
        return scaledRect(body.x, body.y, body.width, body.height)
    }
    onBodyRegionChanged: Qt.callLater(updatePanelRegion)
    onLeftRegionChanged: Qt.callLater(updatePanelRegion)
    onRightRegionChanged: Qt.callLater(updatePanelRegion)
    onMiniPlayerRegionChanged: Qt.callLater(updatePanelRegion)
    onMiniPlayerNeckRegionChanged: Qt.callLater(updatePanelRegion)
    onSideCallRegionChanged: Qt.callLater(updatePanelRegion)
    onSideCallNeckRegionChanged: Qt.callLater(updatePanelRegion)
    onRegionRadiusChanged: Qt.callLater(updatePanelRegion)
    onHeightChanged: Qt.callLater(updatePanelRegion)
    onExpandedRegionChanged: Qt.callLater(updateExpandedRegion)
    onNotificationRegionChanged: Qt.callLater(updateExpandedRegion)
    onWorkAreaChanged: Qt.callLater(updateExpandedRegion)

    function scaledRect(x, y, width, height) {
        const scale = stage.scale
        return Qt.rect(x * scale, y * scale, width * scale, height * scale)
    }

    function capsuleRegion(side) {
        if (!presence.interactive || wings.phase < 0.01 || wings.wingHeight <= 1)
            return Qt.rect(0, 0, 0, 0)
        const padding = 8
        const bounds = side < 0 ? wings.leftWingBounds : wings.rightWingBounds
        return scaledRect(bounds.x - padding, bounds.y - padding,
            bounds.width + 2 * padding, bounds.height + 2 * padding)
    }

    function updatePanelRegion() {
        desktop.setPanelRegion(window, bodyRegion, regionRadius, leftRegion, rightRegion,
                               miniPlayerRegion, miniPlayerNeckRegion, sideCallRegion, sideCallNeckRegion)
    }

    function updateExpandedRegion() {
        desktop.setExpandedRegions(window, expandedRegion, 40 * stage.scale,
                                   notificationRegion, 36 * stage.scale)
    }

    function toggleLyricsLayout() {
        lyricsExpanded = !expandedDock
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

    function clearLyrics() {
        appState.localLyrics = null
        lyricsExpanded = !smokeMode
    }

    function importLyrics(file, targetKey) {
        if (!targetKey || targetKey !== activeTrackKey || !media.player)
            return "Трек сменился. Выберите файл для текущего трека."
        const result = lyricsImport.read(file, media.player.lengthSupported ? media.player.length : 0)
        return appState.applyLyrics(targetKey, result)
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
        property real length: window.smokeMode ? 120 : 22
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
        signal changed()
        onPositionChanged: changed()
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
        readonly property var player: window.smokeNoSession ? null : demoPlayer
        readonly property bool playing: window.demoPlaying
        readonly property bool paused: !window.demoPlaying && !window.smokeNoSession
        readonly property string title: "A little light"
        readonly property string artist: "Sekai Soundbar"
        property string artUrl: ""
        property color artworkAccent: "transparent"
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
        readonly property bool playing: window.playbackActive && (window.demoMode || window.systemAudio.audible)
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
            readonly property color accentMint: dockPalette.accent
        }
        property QtObject settings: QtObject {
            property bool enabled: true
            property real width: 200
            property real height: 38
            property real gap: 12
            property real sensitivity: 1.25
            property string style: "wave"
            property bool dockGlass: window.appearance.values.dockGlass
            property real glassOpacity: window.appearance.values.glassOpacity
            property real glassRefraction: window.appearance.values.glassRefraction
            property real glassBlur: window.appearance.values.glassBlur
            property real glassDarkening: window.appearance.values.glassDarkening
            property real glassLight: window.appearance.values.glassLight
            property int collapseDelay: 600
            property bool lyrics: true
            readonly property bool estimateWordMotion: true
            property bool expandLyrics: true
            property real lyricsWidth: 560
            property bool autoSpotify: false
            property bool multivoice: true
            property int openDuration: 1080
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
            property int expandDuration: 1080
            readonly property bool limitPlayerOvershoot: true
            property real playerSpring: 1.2
            property int followDelay: 190
            property int trailDelay: 230
            property int mistDelay: 300
            property real orbitRadius: 23
            property real progressAmplitude: 3.5
            property real progressWavelength: 30
            property real progressThickness: 3
            readonly property string progressStyle: window.appearance.values.progressStyle
            readonly property bool leftSpectrumReversed: false
        }
        property QtObject dock: QtObject {
            property var item: pill
            property bool vertical: false
            property bool capsule: true
            property string look: "capsule"
            readonly property real radius: Math.min(pill.width, pill.height - 4) / 2
            property real shadow: 4
            readonly property bool asleep: !presence.showing
            property var mediaSource: window.media
            property var lyrics: window.demoMode && !window.timingDocument ? demoLyrics : null
            readonly property var timingDocument: window.timingDocument
            readonly property string lyricsStatus: window.demoMode ? "" : window.lyricsSearch.statusText
            property bool hovered: false
            property bool editing: false
            readonly property bool desktopEmpty: window.expandedDock
            property string screenName: "soundbar"
            property real baseCapHeight: 69
            property real baseWidth: 432
            readonly property real stageWidth: stage.width
            property QtObject palette: QtObject {
                id: dockPalette
                readonly property color sourceColor: window.media.artworkAccent
                readonly property bool useArtwork: window.appearance.values.artworkColors && sourceColor.a > 0

                function shade(base, amount) {
                    return Qt.tint(base, Qt.rgba(sourceColor.r, sourceColor.g, sourceColor.b, amount))
                }

                property color fill: useArtwork ? shade("#0c1014", 0.17) : "#101b18"
                property color rim: useArtwork ? shade("#18242a", 0.38) : "#284a3d"
                property color accent: useArtwork ? sourceColor : "#96dcc0"
                readonly property color ring: fill
                readonly property color shadow: "#060d0a"
                readonly property color ink: "#e8f4ee"
                readonly property real border: 3
                readonly property real ringWidth: 3

                Behavior on fill { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on rim { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on accent { ColorAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }
        }
    }

    Item {
        id: stage
        width: Math.max(760, window.width)
        height: pill.y + Math.max(pill.height, wings.noticeVisible ? noticeLayer.maximumDetailsHeight : 0,
            callLayer.presenting ? callLayer.panelHeight + 4 : 0)
            + 32 + Math.max(0, wings.lyricsView.swipeY)
        scale: window.width / width
        transformOrigin: Item.TopLeft

        Rectangle {
            id: solidHousing
            x: wings.housingRect.x
            y: wings.housingRect.y
            width: wings.housingRect.width
            height: wings.housingRect.height
            radius: wings.housingRadius
            visible: (presence.showing || wings.noticeVisible) && !wings.ownsHousing
            color: wings.noticeVisible && wings.material.enabled
                ? Qt.alpha(demoHost.dock.palette.fill, 0.86) : demoHost.dock.palette.fill
            border.color: demoHost.dock.palette.rim
            border.width: 2
            antialiasing: true
        }
        Rectangle {
            x: noticeLayer.miniBounds.x
            y: noticeLayer.miniBounds.y
            width: noticeLayer.miniBounds.width
            height: noticeLayer.miniBounds.height
            radius: Math.min(width, height) / 2
            color: solidHousing.color
            border.color: solidHousing.border.color
            border.width: solidHousing.border.width
            antialiasing: true
            visible: solidHousing.visible && wings.noticeVisible && width > 0
        }
        Rectangle {
            x: callLayer.sideNeck.x
            y: callLayer.sideNeck.y
            width: callLayer.sideNeck.width
            height: callLayer.sideNeck.height
            radius: height / 2
            color: solidHousing.color
            antialiasing: true
            visible: solidHousing.visible && width > 0
        }
        Rectangle {
            x: callLayer.sideBounds.x
            y: callLayer.sideBounds.y
            width: callLayer.sideBounds.width
            height: callLayer.sideBounds.height
            radius: height / 2
            color: solidHousing.color
            border.color: solidHousing.border.color
            border.width: solidHousing.border.width
            antialiasing: true
            visible: solidHousing.visible && width > 0
        }

        MouseArea {
            x: pill.x + wings.lyricsView.swipeX
            y: pill.y + wings.lyricsView.swipeY
            width: pill.width
            height: pill.capHeight
            enabled: presence.interactive && !wings.noticeVisible && !callLayer.presenting && !!window.media.player
            cursorShape: Qt.PointingHandCursor
            onClicked: window.toggleLyricsLayout()
        }

        DockWings {
            id: wings
            objectName: "standaloneDockWings"
            anchors.fill: parent
            host: demoHost
            hideProgress: presence.hideProgress
            staggeredOpening: true
            notification: noticeLayer
            playerOverride: callLayer.layoutBounds
            playerOverrideMix: callLayer.housingMix
            sideCallBounds: callLayer.sideBounds
            sideCallBlend: callLayer.sideBlend
            lyricsCover: callLayer.lyricsCover
            backdropComponent: window.desktopGlassAvailable ? monitorBackdrop : null
            backdropEnabled: window.visible && window.appearance.values.desktopGlass
            desktopLens: backdropEnabled && (backdropItem?.hasFrame === true)
        }
        Component {
            id: monitorBackdrop
            MonitorBackdrop {
                borderless: window.appearance.values.captureBorderless
                onBorderlessGranted: window.appearance.setCaptureBorderless(true)
            }
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
        }
        DockNotification {
            id: noticeLayer
            anchors.fill: parent
            event: window.appState.dockNotification
            wifi: window.appState.wifiStatus.snapshot
            battery: window.appState.batteryStatus.snapshot
            renderer: wings
            media: window.media
            allowed: !window.desktop.fullscreenActive
            clearForDetails: window.notificationSpaceReady
            suspended: callLayer.ringOnTop
            callSpan: callLayer.presenting && callLayer.conversation ? callLayer.sideWidth + miniGap : 0
            attached: !callLayer.presenting && presence.showing && presence.hideProgress < 0.55
                && (window.playbackActive || (!!window.media.player && !window.swipeDismissed))
            paused: window.playbackPaused
            trackKey: window.activeTrackKey
            miniPauseDelay: window.smokeMode ? 1450 : 40000
            topInset: pill.y
            availableHeight: Math.max(compactHeight, window.workArea.height / Math.max(0.01, stage.scale)
                - topInset - 44)
            onDismissed: window.appState.dismissNotification()
            onNeckBoundsChanged: {
                if (window.smokePhase === 22 && neckBounds.width > 0 && miniBounds.width > miniBounds.height
                        && miniBounds.x + miniBounds.width > bodyBounds.x + bodyBounds.width + 8) {
                    window.smokeSawGlassNeck = true
                }
            }
            onReleaseRecoilChanged: if (window.smokePhase === 22 && releaseRecoil > 0.25)
                window.smokeSawReleaseSpring = true
        }
        DockDiscordCall {
            id: callLayer
            anchors.fill: parent
            preview: window.discordPreview
            media: window.media
            notification: noticeLayer
            housing: wings.playerHousing
            opening: 1 - presence.hideProgress
            topInset: pill.y
            expansionAllowed: window.expandedSpaceReady
                && window.workArea.height >= (topInset + expandedHeight + 16) * stage.scale
            musicProgress: wings.lyricsView.duration > 0 ? wings.lyricsView.position / wings.lyricsView.duration : 0
        }
    }

    Connections {
        target: wings.lyricsView
        enabled: window.smokeMode && (window.smokePhase === 22 || window.smokePhase === 23)
        function onPartProgressChanged() {
            const parts = wings.lyricsView.partProgress
            const staggered = Math.max(...parts) - Math.min(...parts) > 0.3
            if (window.smokePhase === 22) {
                if (staggered && wings.lyricsView.coverAlpha > 0.2)
                    window.smokeSawStaggeredTuck = true
            } else {
                if (staggered)
                    window.smokeSawStaggeredReturn = true
                parts.forEach((part, index) => {
                    if (part < -0.012)
                        window.smokeReturnSprings.add(index)
                })
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: presence.interactive
        acceptedButtons: Qt.RightButton
        onClicked: mouse => {
            menuLoader.active = true
            menuLoader.item.popup(mouse.x, mouse.y)
        }
    }
    Loader {
        id: menuLoader
        active: false
        sourceComponent: contextMenu
    }
    Dialogs.FileDialog {
        id: lyricsPicker
        property string targetKey: ""
        parentWindow: window
        title: "Выбрать файл лирики"
        nameFilters: ["Лирика (*.lrc *.json)"]
        onAccepted: {
            const message = window.importLyrics(selectedFile, targetKey)
            if (message) {
                lyricsMessage.title = "Импорт лирики"
                lyricsMessage.text = message
                lyricsMessage.open()
            }
        }
    }
    Dialog {
        id: lyricsMessage
        property alias text: errorText.text
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: Math.min(396, window.width)
        popupType: Popup.Window
        modal: true
        title: "Импорт лирики"
        standardButtons: Dialog.Ok
        contentItem: Label {
            id: errorText
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
        }
    }
    AlignmentDialog {
        id: alignmentDialog
        parent: Overlay.overlay
        controller: window.lyricsAlignment
        ownerWindow: window
    }
    Connections {
        target: window.desktop
        function onShowRequested() {
            if (window.activeTrackKey !== "" && !window.desktop.fullscreenActive && !window.playbackActive) {
                wings.lyricsView.dismissedUntilPlay = false
                window.trayPreview = true
            }
        }
    }
    Connections {
        target: window.appState
        function onAlignmentFailed(message) {
            if (alignmentDialog.visible)
                alignmentDialog.saveError = message
        }
    }
    Dialog {
        id: matchPicker
        property string targetKey: ""
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: Math.min(440, window.width)
        popupType: Popup.Window
        modal: true
        title: "Найденные версии лирики"
        standardButtons: Dialog.Cancel
        contentItem: ListView {
            clip: true
            implicitHeight: Math.min(count * 56, 280)
            model: window.lyricsSearch.choices
            ScrollBar.vertical: ScrollBar {}
            delegate: ItemDelegate {
                id: trackChoice
                required property int index
                required property var modelData
                width: ListView.view.width - 12
                height: 56
                contentItem: Column {
                    spacing: 3
                    Label {
                        width: parent.width
                        text: trackChoice.modelData.title
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                    }
                    Label {
                        width: parent.width
                        text: [trackChoice.modelData.source, trackChoice.modelData.album,
                            trackChoice.modelData.duration].filter(Boolean).join(" · ")
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        opacity: 0.7
                    }
                }
                onClicked: {
                    if (window.lyricsSearch.choose(matchPicker.targetKey, index)) {
                        window.appState.localLyrics = null
                        window.lyricsExpanded = true
                    }
                    matchPicker.close()
                }
            }
        }
    }
    Component {
        id: contextMenu
        Menu {
            id: panelMenu
            popupType: Popup.Window
            onClosed: {
                if (stage.GraphicsInfo.api === GraphicsInfo.Software) {
                    Qt.callLater(() => {
                        if (!panelMenu.visible)
                            menuLoader.active = false
                    })
                }
            }
            MenuItem {
                text: window.expandedDock ? "Свернуть лирику" : "Развернуть лирику"
                enabled: !!window.media.player && window.expansionClear
                onTriggered: window.toggleLyricsLayout()
            }
            MenuItem {
                text: "Загрузить лирику…"
                enabled: window.activeTrackKey !== ""
                onTriggered: {
                    lyricsPicker.targetKey = window.activeTrackKey
                    Qt.callLater(() => lyricsPicker.open())
                }
            }
            MenuItem {
                text: "Выровнять лирику…"
                enabled: !window.demoMode
                onTriggered: Qt.callLater(() => {
                    const player = window.media.player
                    const length = player && player.lengthSupported ? player.length : 0
                    const lines = window.timingDocument ? (window.timingDocument.lines || []) : []
                    alignmentDialog.openForTrack(window.activeTrackKey, length, lines)
                })
            }
            MenuItem {
                text: "Убрать загруженную лирику"
                visible: !!window.localLyrics
                height: visible ? implicitHeight : 0
                enabled: visible
                onTriggered: window.clearLyrics()
            }
            Menu {
                title: "Поиск лирики"
                enabled: !window.demoMode
                MenuItem {
                    text: "Автопоиск лирики"
                    checkable: true
                    checked: window.lyricsSearch.automatic
                    onTriggered: window.lyricsSearch.automatic = checked
                }
                MenuItem {
                    text: "Найти лирику"
                    enabled: window.lyricsSearch.canSearch && !window.lyricsSearch.searching
                    onTriggered: window.lyricsSearch.retry()
                }
                MenuItem {
                    text: "Прокси поиска…"
                    onTriggered: window.desktop.settingsRequested("lyrics")
                }
                MenuItem {
                    text: "Выбрать версию лирики…"
                    enabled: window.lyricsSearch.choices.length > 0
                    onTriggered: {
                        matchPicker.targetKey = window.activeTrackKey
                        Qt.callLater(() => matchPicker.open())
                    }
                }
                MenuItem {
                    text: "Состояние источников…"
                    enabled: window.lyricsSearch.sourceDetails !== ""
                    onTriggered: {
                        lyricsMessage.title = "Состояние источников"
                        lyricsMessage.text = window.lyricsSearch.sourceDetails
                        Qt.callLater(() => lyricsMessage.open())
                    }
                }
                MenuItem {
                    text: window.lyricsSearch.statusText
                    enabled: false
                    visible: text !== ""
                    height: visible ? implicitHeight : 0
                }
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
                text: "Настройки…"
                onTriggered: window.desktop.settingsRequested("general")
            }
            MenuItem {
                text: "Скрыть док"
                visible: window.trayPreview && !window.playbackActive
                height: visible ? implicitHeight : 0
                onTriggered: window.trayPreview = false
            }
            MenuItem {
                text: "Выход"
                onTriggered: Qt.quit()
            }
        }
    }

    Timer {
        interval: 50
        repeat: true
        running: window.demoMode && window.demoPlaying && !window.smokeMode
        onTriggered: {
            window.elapsed += 0.05
            demoPlayer.position += 0.05
            if (demoPlayer.position >= demoPlayer.length) demoPlayer.position = 0
            visualizerService.demoBands = window.spectrumAt(window.elapsed)
        }
    }

    Timer {
        interval: 33
        repeat: true
        running: !window.demoMode && visualizerService.playing
        onTriggered: visualizerService.beatState = BeatTracker.update(
            visualizerService.beatState, visualizerService.bands, Date.now())
        onRunningChanged: if (!running) visualizerService.resetRhythm()
    }

    FrameAnimation {
        running: window.smokeMode && window.smokePhase === 0 && !window.smokeSawPackedEntrance
        onTriggered: {
            const hull = wings.playerHousing
            const parts = wings.lyricsView.openingPose()
            if (hull.y < 0 && hull.y + hull.height > 0 && parts.cover > 0.12
                    && parts.coverScale < 0.65 && parts.volume < 0.015) {
                window.smokeSawPackedEntrance = true
            }
        }
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
                        || (window.flags & Qt.WindowStaysOnTopHint)) {
                    window.failSmoke("panel is not frameless, transparent and centered on the top edge")
                    return
                }
                if (stage.GraphicsInfo.api === GraphicsInfo.Software && !solidHousing.visible) {
                    window.failSmoke("the software renderer needs a solid housing")
                    return
                }
                if (!window.smokeSawPackedEntrance) {
                    window.failSmoke("the compressed cover must appear at the top edge before the volume control")
                    return
                }
                if (!wings.visible || (wings.ownsHousing === solidHousing.visible) || !isFinite(pill.width)
                        || Math.abs(pill.width - Math.min(demoHost.settings.compactWidth,
                            wings.lyricsView.maxBody)) > 0.5
                        || wings.suppressMediaKey || wings.reveal < 0.95
                        || !JSON.parse(wings.lyricsView.diagnostics()).trackHeaderVisible
                        || visualizerService.bands.length !== 64) return
                if (!Qt.colorEqual(dockPalette.accent, "#96dcc0") || !Qt.colorEqual(dockPalette.fill, "#101b18")) {
                    window.failSmoke("missing artwork should keep the default mint palette")
                    return
                }
                window.captureSmoke("compact", function() {
                    if (window.smokeImports) {
                        const message = window.importLyrics(window.smokeLrc, window.activeTrackKey)
                        if (message) {
                            window.failSmoke(message)
                            return
                        }
                        demoPlayer.seek(4.8)
                    } else {
                        demoLyrics.status = "ready"
                    }
                    demoMedia.artworkAccent = "#ec9dad"
                    window.lyricsExpanded = true
                    window.smokePhase = 1
                    window.smokeStarted = Date.now()
                })
            } else if (window.smokePhase === 1 && wait >= 1800) {
                const lyrics = JSON.parse(wings.lyricsView.diagnostics())
                if (!wings.suppressMediaKey || wings.lyricsHeightExtra <= 100
                        || Math.abs(pill.width - Math.min(demoHost.settings.lyricsWidth,
                            wings.lyricsView.maxBody)) > 0.5
                        || !lyrics.wide || !lyrics.visible) return
                const expected = window.smokeImports
                    ? lyrics.text === "Вторая строка" && lyrics.lineOnly && lyrics.wordSpans === 0
                    : demoLyrics.lines.some(line => line.text === lyrics.text)
                if (!expected) return
                if (!Qt.colorEqual(dockPalette.accent, demoMedia.artworkAccent)
                        || Qt.colorEqual(dockPalette.fill, "#101b18")
                        || Qt.colorEqual(dockPalette.rim, "#284a3d")
                        || !Qt.colorEqual(dockPalette.ink, "#e8f4ee")) {
                    window.failSmoke("cover tint must reach the player and leave its text readable")
                    return
                }
                if (window.smokeImports && (lyrics.wordStart !== 4
                        || !(lyrics.nextWordStart > 4.9 && lyrics.nextWordStart < 9))) {
                    window.failSmoke("the LRC line has no estimated second word landing")
                    return
                }
                window.captureSmoke("expanded lyrics", function() {
                    if (window.smokeImports) {
                        demoMedia.artworkAccent = "#92bfff"
                        window.smokeLandingTime = lyrics.nextWordStart
                        window.smokeFirstMarkerX = lyrics.marker[0]
                        demoPlayer.seek(window.smokeLandingTime - 0.12)
                        window.smokePhase = 2
                        window.smokeStarted = Date.now()
                        return
                    }
                    smokeTimer.stop()
                    console.log("PASS standalone soundbar smoke test")
                    Qt.exit(0)
                })
            } else if (window.smokePhase === 2 && wait >= 250) {
                const lyrics = JSON.parse(wings.lyricsView.diagnostics())
                if (lyrics.text !== "Вторая строка" || lyrics.wordStart !== 4
                        || !(lyrics.markerAir > 0.2 && lyrics.marker[0] > window.smokeFirstMarkerX + 2)) {
                    window.failSmoke("the marker did not arc between words of the LRC line")
                    return
                }
                demoPlayer.seek(window.smokeLandingTime + 0.1)
                window.smokePhase = 3
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 3 && wait >= 250) {
                const lyrics = JSON.parse(wings.lyricsView.diagnostics())
                if (lyrics.text !== "Вторая строка" || lyrics.wordStart !== window.smokeLandingTime
                        || !(lyrics.marker[0] > window.smokeFirstMarkerX + 8 && lyrics.splashes > 0)) {
                    window.failSmoke("the marker did not land with a splash on the second LRC word")
                    return
                }
                if (!Qt.colorEqual(dockPalette.accent, demoMedia.artworkAccent)) {
                    window.failSmoke("a new cover did not replace the previous tint")
                    return
                }
                window.appearance.setArtworkColors(false)
                demoMedia.togglePlaying()
                demoPlayer.seek(1.25)
                window.smokePhase = 4
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 4 && wait >= 350) {
                const lyrics = JSON.parse(wings.lyricsView.diagnostics())
                if (lyrics.playing || lyrics.position !== 1.25 || lyrics.text !== "Первая строка") {
                    window.failSmoke("paused rewind did not restore the first LRC line")
                    return
                }
                if (!Qt.colorEqual(dockPalette.accent, "#96dcc0")) {
                    window.failSmoke("disabling the tint did not restore the mint accent")
                    return
                }
                demoMedia.artworkAccent = "transparent"
                window.appearance.setArtworkColors(true)
                const message = window.importLyrics(window.smokeWordtime, window.activeTrackKey)
                if (message) {
                    window.failSmoke(message)
                    return
                }
                demoPlayer.seek(6)
                window.smokePhase = 5
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 5 && wait >= 250) {
                const lyrics = JSON.parse(wings.lyricsView.diagnostics())
                if (lyrics.playing || lyrics.position !== 6 || lyrics.text !== "Свет звучит"
                        || lyrics.lineOnly || lyrics.wordSpans !== 2 || lyrics.timingWords !== 4
                        || !(Math.abs(lyrics.nextWordStart - 6.05) < 0.001)) {
                    window.failSmoke("the Wordtime document did not follow the paused seek")
                    return
                }
                const oldKey = window.activeTrackKey
                demoPlayer.trackKey = "second"
                if (!window.importLyrics(window.smokeWordtime, oldKey)) {
                    window.failSmoke("an import started for the previous track was accepted")
                    return
                }
                window.smokePhase = 6
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 6 && wait >= 250) {
                if (window.timingDocument || JSON.parse(wings.lyricsView.diagnostics()).available) {
                    window.failSmoke("lyrics from the previous track remain visible")
                    return
                }
                window.smokeObstructed = true
                window.lyricsExpanded = true
                window.demoPlaying = true
                window.smokePhase = 7
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 7 && wait >= 750) {
                if (wings.lyricsView.wide || !window.visible) {
                    window.failSmoke("an obstructed expanded region should leave a compact dock")
                    return
                }
                window.smokeObstructed = false
                window.smokePhase = 8
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 8) {
                if (wait < 350 && wings.lyricsView.wide) {
                    window.failSmoke("the dock expanded before its clear area settled")
                    return
                }
                if (wait < 1700) return
                if (!wings.lyricsView.wide || wings.lyricsHeightExtra <= 100) {
                    window.failSmoke("the dock did not expand after its area was clear")
                    return
                }
                window.smokeHoldOpen = false
                window.demoPlaying = false
                window.smokePhase = 9
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 9 && wait >= 950) {
                if (!wings.lyricsView.wide || wings.lyricsHeightExtra <= 100 || !presence.interactive) {
                    window.failSmoke("pause should preserve the expanded dock until its delay expires")
                    return
                }
                window.demoPlaying = true
                window.smokePhase = 10
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 10 && wait >= 850) {
                if (!presence.interactive || !wings.lyricsView.wide) {
                    window.failSmoke("resuming within the pause delay did not cancel the departure")
                    return
                }
                window.smokeStarted = Date.now()
                window.demoPlaying = false
                window.smokePhase = 11
            } else if (window.smokePhase === 11) {
                const progress = presence.hideProgress
                if (wait < 1550 && progress > 0) {
                    window.failSmoke("the dock started to leave " + wait + " ms after pausing")
                    return
                }
                if (progress <= 0.2) return
                if (progress >= 1 || window.bodyRegion.width > 0 || !window.visible) {
                    window.failSmoke("the departing drop should be visible and click-through")
                    return
                }
                window.demoPlaying = true
                if (Math.abs(presence.hideProgress - progress) > 0.05) {
                    window.failSmoke("resuming playback reset the drop position")
                    return
                }
                window.smokePhase = 12
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 12) {
                if (presence.hideProgress > 0 && wait < presence.motion.duration + 300)
                    return
                if (!presence.interactive || presence.hideProgress !== 0) {
                    window.failSmoke("the reversed animation did not restore the panel")
                    return
                }
                window.demoPlaying = false
                window.smokeNoSession = true
                window.desktop.showRequested()
                if (window.trayPreview) {
                    window.failSmoke("losing the media session opened an idle placeholder")
                    return
                }
                window.smokePhase = 13
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 13 && presence.hideProgress === 1) {
                if (window.visible || window.bodyRegion.width > 0
                        || wings.housingRect.y + wings.housingRect.height > 0) {
                    window.failSmoke("the idle drop did not fully leave through the top edge")
                    return
                }
                window.smokeObstructed = true
                const message = "Автоматически сохраняются в папке снимков экрана."
                window.appState.showNotification({
                    kind: "app", accent: "#c3b5ff", title: "Снимок экрана скопирован в буфер обмена",
                    summary: message, detail: message, source: "Ножницы", sentAt: new Date()
                })
                window.smokePhase = 14
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 14 && noticeLayer.reveal === 1) {
                if (!window.visible || !wings.visible || noticeLayer.attached || presence.showing
                        || window.bodyRegion.width === 0 || window.leftRegion.width > 0
                        || window.rightRegion.width > 0 || window.miniPlayerRegion.width > 0
                        || wings.housingRect.height !== noticeLayer.compactHeight) {
                    window.failSmoke("the obstructed idle notification did not use a compact glass body")
                    return
                }
                const text = noticeLayer.textLayout()
                if (noticeLayer.bodyBounds.width <= 450 || text.titleOverflow > 0.5 || text.messageTruncated
                        || text.messageY >= text.detailY) {
                    window.failSmoke("the compact app notice did not make room for its full title and preview")
                    return
                }
                window.smokeObstructed = false
                window.smokePhase = 15
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 15 && noticeLayer.detailProgress === 1) {
                if (Math.abs(window.bodyRegion.height - noticeLayer.detailsHeight * stage.scale) > 0.1
                        || (wings.shaderAvailable && wings.material.enabled && wings.glassAmount <= 0)) {
                    window.failSmoke("the notification did not expand automatically in the glass housing")
                    return
                }
                const text = noticeLayer.textLayout()
                if (text.titleOverflow > 0.5 || Math.abs(text.titleCenterOffset.x) > 0.1
                        || Math.abs(text.titleCenterOffset.y) > 0.1) {
                    window.failSmoke("the expanded app title did not center between the icon and close button")
                    return
                }
                if (text.duplicateVisible || Math.abs(text.messageY - text.detailY) > 0.1
                        || !Qt.colorEqual(text.messageColor, noticeLayer.accent)
                        || text.message !== window.appState.dockNotification.detail) {
                    window.failSmoke("the accent message did not move from the preview into the body")
                    return
                }
                if (wait < 1850) return
                window.appState.enqueueNotification(window.appState.testScenarios.charging)
                if (window.appState.dockNotification.kind !== "app") {
                    window.failSmoke("the automatic event displaced the visible notification")
                    return
                }
                window.appState.dismissNotification()
                if (window.appState.dockNotification?.kind !== "battery") {
                    window.failSmoke("dismissing the notification did not show the queued battery event")
                    return
                }
                window.appState.dismissNotification()
                window.smokePhase = 16
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 16 && !noticeLayer.presenting) {
                if (window.visible || window.bodyRegion.width > 0) {
                    window.failSmoke("closing the test notification did not hide the idle dock")
                    return
                }
                window.smokeObstructed = true
                window.smokeNoSession = false
                window.demoPlaying = true
                window.smokePhase = 17
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 17 && wait >= 1150) {
                if (!presence.interactive || !window.visible || wings.lyricsView.wide) {
                    window.failSmoke("resuming playback did not restore the unobscured compact layout")
                    return
                }
                if (!window.smokeTestedWingResize) {
                    window.smokeCompactWing = wings.leftWingBounds
                    const message = "Автоматически сохраняются в папке снимков экрана."
                    window.appState.showNotification({
                        kind: "app", accent: "#c3b5ff",
                        title: "Снимок экрана скопирован в буфер обмена и автоматически сохранён в папке снимков экрана",
                        summary: message, detail: message, source: "Ножницы", sentAt: new Date()
                    })
                    window.smokePhase = 34
                    window.smokeStarted = Date.now()
                    return
                }
                window.demoPlaying = false
                window.desktop.showRequested()
                const lyricsView = wings.lyricsView
                if (!window.trayPreview || !lyricsView.beginSwipe(0, 0)) {
                    window.failSmoke("the paused dock was not available to swipe")
                    return
                }
                lyricsView.moveSwipe(10, 0)
                lyricsView.finishSwipe(true)
                window.smokePhase = 18
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 34 && wait >= 1350) {
                const card = noticeLayer.bodyBounds
                const left = wings.leftWingBounds
                const right = wings.rightWingBounds
                const previous = window.smokeCompactWing
                const leftGap = card.x - left.x - left.width
                const rightGap = right.x - card.x - card.width
                const canShowWings = wings.wingLength >= 64
                if (!noticeLayer.attached || card.width < pill.capWidth + 30 || noticeLayer.detailProgress > 0
                        || (canShowWings && (Math.abs(leftGap - wings.gap) > 2 || Math.abs(rightGap - wings.gap) > 2
                            || left.x < 0 || right.x + right.width > stage.width
                            || left.width >= previous.width || window.leftRegion.width <= 0
                            || window.rightRegion.width <= 0))
                        || (wings.wingLength <= 30 && (window.leftRegion.width > 0 || window.rightRegion.width > 0))) {
                    window.failSmoke("compact spectrum capsules must follow the edges of a wider notification")
                    return
                }
                window.appState.dismissNotification()
                window.smokePhase = 35
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 35 && !noticeLayer.presenting) {
                const left = wings.leftWingBounds
                const previous = window.smokeCompactWing
                if (Math.abs(left.x - previous.x) > 2 || Math.abs(left.width - previous.width) > 2) {
                    window.failSmoke("compact spectrum capsules did not return with the player")
                    return
                }
                window.smokeTestedWingResize = true
                window.smokePhase = 17
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 18 && wait >= 700) {
                const lyricsView = wings.lyricsView
                if (!presence.interactive || window.swipeDismissed || !lyricsView.beginSwipe(0, 0)) {
                    window.failSmoke("a short swipe dismissed the dock")
                    return
                }
                lyricsView.moveSwipe(110, 0)
                if (!lyricsView.finishSwipe(true)) {
                    window.failSmoke("the dock did not accept a completed swipe")
                    return
                }
                window.smokePhase = 19
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 19 && wait >= 1000) {
                if (window.visible || window.trayPreview || presence.hideProgress !== 1) {
                    window.failSmoke("a completed swipe left a visible dock")
                    return
                }
                window.desktop.showRequested()
                window.smokePhase = 20
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 20 && wait >= 1150) {
                if (!presence.interactive || window.swipeDismissed
                        || !JSON.parse(wings.lyricsView.diagnostics()).trackHeaderVisible) {
                    window.failSmoke("the tray did not restore the paused track after a swipe")
                    return
                }
                window.smokeObstructed = false
                window.lyricsExpanded = true
                window.demoPlaying = true
                window.smokePhase = 21
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 21 && wings.lyricsView.wideReveal === 1 && window.notificationSpaceReady) {
                window.appState.postTestNotification()
                window.smokePhase = 22
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 22) {
                const body = wings.housingRect
                const mini = noticeLayer.miniBounds
                const parts = wings.lyricsView.partProgress
                if (noticeLayer.splitProgress !== 1 || parts.some(part => part !== 1))
                    return
                if (!window.smokeSawGlassNeck || !window.smokeSawStaggeredTuck || !window.smokeSawReleaseSpring
                        || mini.x < body.x + body.width + 12 || mini.width !== noticeLayer.miniDiameter
                        || Math.abs(window.miniPlayerRegion.width - mini.width * stage.scale) > 0.1) {
                    window.failSmoke("the connected glass drop did not gather the player in separate parts"
                        + " (neck: " + window.smokeSawGlassNeck + ", stagger: " + window.smokeSawStaggeredTuck
                        + ", spring: " + window.smokeSawReleaseSpring + ")")
                    return
                }
                window.appState.dismissNotification()
                window.smokePhase = 23
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 23) {
                if (wings.housingRect.height + 0.1 < noticeLayer.detailsHeight) {
                    window.failSmoke("the glass body shrank into compact mode while merging with the mini-player")
                    return
                }
                if (noticeLayer.presenting || wings.lyricsView.partProgress.some(part => part !== 0))
                    return
                if (!window.visible || !wings.lyricsView.wide || window.miniPlayerRegion.width !== 0
                        || !window.smokeSawStaggeredReturn || window.smokeReturnSprings.size < 2) {
                    window.failSmoke("the player did not return in staggered pieces and spring into place"
                        + " (stagger: " + window.smokeSawStaggeredReturn + ", springs: "
                        + window.smokeReturnSprings.size + ")")
                    return
                }
                window.appState.postTestNotification("wifi")
                window.smokePhase = 24
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 24 && noticeLayer.splitProgress === 1) {
                const wifi = window.appState.wifiStatus.snapshot
                if (!wifi.preview || wifi.samples.length < 8 || noticeLayer.bodyBounds.height < 230) {
                    window.failSmoke("the Wi-Fi debug card did not expand with traffic samples")
                    return
                }
                window.appState.postTestNotification("update")
                if (window.appState.wifiStatus.active || window.appState.dockNotification.kind !== "system") {
                    window.failSmoke("switching test events left the Wi-Fi sampler active")
                    return
                }
                window.appState.postTestNotification("charged")
                if (window.appState.dockNotification.charge !== 100) {
                    window.failSmoke("the full battery test did not carry its charge level")
                    return
                }
                demoPlayer.seek(58)
                window.appearance.setProgressStyle("plassglass")
                window.smokePhase = 25
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 25 && noticeLayer.miniProgressRenderer === "plassglassProgressRenderer"
                    && noticeLayer.miniProgressSpectrum > 0.002) {
                demoMedia.togglePlaying()
                window.smokePhase = 26
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 26 && noticeLayer.keepPausedMini) {
                window.appState.dismissNotification()
                window.smokePhase = 27
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 27 && noticeLayer.cardRetraction === 1
                    && noticeLayer.miniProgressSpectrum <= 0.002) {
                if (!window.visible || !noticeLayer.keepPausedMini || noticeLayer.miniBounds.width < 60
                        || wings.housingRect.y + wings.housingRect.height > 0) {
                    window.failSmoke("a dismissed notification did not leave only the paused mini-player")
                    return
                }
                window.smokePhase = 28
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 28 && noticeLayer.miniPauseExpired && !noticeLayer.presenting) {
                if (window.visible || presence.showing || window.miniPlayerRegion.width > 0) {
                    window.failSmoke("the mini-player timeout brought back the paused dock")
                    return
                }
                demoMedia.togglePlaying()
                window.smokePhase = 29
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 29 && presence.interactive) {
                if (!window.visible || noticeLayer.miniPauseExpired || !wings.lyricsView.wide) {
                    window.failSmoke("resuming did not restore the expanded dock after the mini-player timeout")
                    return
                }
                const instrument = JSON.parse(wings.lyricsView.diagnostics())
                if (instrument.progressRenderer !== "plassglassProgressRenderer" || instrument.progressSpectrum <= 0.002)
                    return
                window.appearance.setProgressStyle("material")
                window.smokePhase = 30
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 30 && JSON.parse(wings.lyricsView.diagnostics()).progressRenderer
                    === "materialProgressRenderer") {
                const line = "Длинное уведомление переносится на новые строки, чтобы сохранить весь текст."
                const lineCount = Math.ceil(noticeLayer.availableHeight / 10)
                window.appState.showNotification({
                    kind: "app", accent: "#c3b5ff",
                    title: "Длинный заголовок уведомления прокручивается вперёд и назад с паузами на обоих концах",
                    summary: line,
                    detail: (line + "\n").repeat(lineCount) + "Конец сообщения.", source: "Ножницы", sentAt: new Date()
                })
                window.smokePhase = 31
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 31 && noticeLayer.reveal === 1
                    && noticeLayer.detailProgress === 1 && noticeLayer.splitProgress === 1) {
                const text = noticeLayer.textLayout()
                const body = noticeLayer.bodyBounds
                if (text.titleOverflow <= 0.5 || text.messageTruncated || text.messageLines < 4
                        || text.scrollRange <= 0 || text.duplicateVisible
                        || !text.message.endsWith("Конец сообщения.")
                        || body.x < 0 || body.y + body.height > stage.height
                        || Math.abs(body.width - noticeLayer.maxCardWidth) > 1
                        || body.x + body.width >= noticeLayer.miniBounds.x) {
                    window.failSmoke("long notification text did not wrap and scroll inside the available desktop area")
                    return
                }
                window.smokePhase = 32
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 32 && noticeLayer.textLayout().titleScroll === 1) {
                window.smokePhase = 33
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 33 && noticeLayer.textLayout().titleScroll < 0.85) {
                window.discordPreview.start()
                window.smokePhase = 36
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 36 && callLayer.lifetime === 1) {
                if (!callLayer.ringOnTop || wings.noticeVisible || !window.appState.dockNotification) {
                    window.failSmoke("an incoming call did not preserve the notification behind it")
                    return
                }
                window.discordPreview.decline()
                window.smokePhase = 37
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 37) {
                if (callLayer.retiring && callLayer.lifetime < 0.9 && callLayer.lifetime > 0.3
                        && callLayer.housingMix > 0 && window.visible) {
                    window.smokeSawCallExit = true
                }
                if (!callLayer.presenting) {
                    if (!window.smokeSawCallExit || !noticeLayer.active || window.discordPreview.active) {
                        window.failSmoke("declining did not animate out and restore the queued notification")
                        return
                    }
                    window.appState.dismissNotification()
                    demoMedia.togglePlaying()
                    window.smokeNoSession = true
                    window.smokeHoldOpen = false
                    window.smokePhase = 38
                    window.smokeStarted = Date.now()
                }
            } else if (window.smokePhase === 38 && !noticeLayer.presenting && presence.hideProgress === 1) {
                window.discordPreview.start()
                window.smokePhase = 39
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 39 && presence.interactive) {
                if (!window.visible || !callLayer.ringOnTop || callLayer.showMusic) {
                    window.failSmoke("a test call did not open the dock without a media session")
                    return
                }
                window.smokeCallHome = callLayer.identityBounds
                window.discordPreview.accept()
                window.smokePhase = 40
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 40) {
                if (callLayer.expandProgress > 0.28 && callLayer.expandProgress < 0.8
                        && callLayer.participantTravel - callLayer.controlTravel > 0.16
                        && Math.abs(callLayer.identityBounds.x - window.smokeCallHome.x) < 55
                        && window.visible && wings.playerHousing.height > 80) {
                    window.smokeSawCallUnfold = true
                }
                if (window.discordPreview.seconds === 0 || callLayer.expandProgress < 1)
                    return
                const call = window.discordPreview
                if (!window.smokeSawCallUnfold || !callLayer.expanded || call.participants.length !== 4
                        || Math.abs(wings.playerHousing.height - callLayer.expandedHeight) > 1) {
                    window.failSmoke("the call did not unfold its participants and controls from the incoming card")
                    return
                }
                call.toggleMute()
                call.toggleDeafen()
                call.toggleMute()
                call.toggleDeafen()
                if (call.deafened || !call.microphoneOff || !call.muted) {
                    window.failSmoke("deafen did not preserve the previous microphone setting")
                    return
                }
                call.toggleMute()
                window.smokeObstructed = true
                window.smokeNoSession = false
                demoMedia.togglePlaying()
                window.smokePhase = 41
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 41 && callLayer.expandProgress === 0 && callLayer.musicMix === 1
                    && wings.wingSpan > 60 && wings.contentOpacity === 1) {
                if (callLayer.expanded || !callLayer.showMusic || window.discordPreview.microphoneOff
                        || wings.playerHousing.height > 74
                        || wings.leftWingBounds.x < 0 || wings.rightWingBounds.x + wings.wingSpan > stage.width) {
                    window.failSmoke("the occupied space did not fold voice and music into the compact dock")
                    return
                }
                demoMedia.togglePlaying()
                demoPlayer.trackKey = "discord-preview-smoke"
                if (!callLayer.showMusic || !window.discordPreview.connected || !presence.wanted) {
                    window.failSmoke("pausing or changing tracks cleared the test call")
                    return
                }
                demoMedia.togglePlaying()
                window.smokeObstructed = false
                window.smokePhase = 42
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 42 && callLayer.expandProgress === 1) {
                window.smokeCallHome = callLayer.identityBounds
                window.appState.postTestNotification("update")
                window.smokePhase = 43
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 43) {
                const body = noticeLayer.bodyBounds
                const voice = callLayer.sideBounds
                const music = noticeLayer.miniBounds
                if (!window.visible || body.y < 0 || body.height < noticeLayer.compactHeight - 5) {
                    window.failSmoke("the housing retracted instead of splitting in place for the notification")
                    return
                }
                if (callLayer.split > 0.24 && callLayer.split < 0.87 && voice.width > 20
                        && callLayer.identityBounds.x < window.smokeCallHome.x - 28) {
                    window.smokeSawCallSlide = true
                }
                if (callLayer.sideNeck.width > 0 && voice.x + voice.width > body.x - 12)
                    window.smokeSawCallNeck = true
                if (noticeLayer.splitProgress !== 1 || noticeLayer.reveal !== 1 || noticeLayer.detailProgress !== 1)
                    return
                if (!window.smokeSawCallSlide || !window.smokeSawCallNeck
                        || voice.width < 165 || voice.x < 0 || voice.x + voice.width >= body.x
                        || music.width < 60 || body.x + body.width >= music.x || music.x + music.width > stage.width
                        || window.sideCallRegion.width <= 0 || window.discordPreview.seconds <= 0
                        || Math.abs(callLayer.identityBounds.x - voice.x - 10) > 1) {
                    window.failSmoke("the moving call identity and music did not separate from the notification")
                    return
                }
                window.appState.dismissNotification()
                window.smokePhase = 44
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 44 && !noticeLayer.presenting) {
                if (!callLayer.expanded || callLayer.controlTravel !== 1 || !window.discordPreview.connected
                        || callLayer.sideBounds.width > 0 || Math.abs(callLayer.identityBounds.x - window.smokeCallHome.x) > 1) {
                    window.failSmoke("dismissing the notification did not restore the expanded call")
                    return
                }
                window.discordPreview.hangUp()
                window.smokeSawCallExit = false
                window.smokePhase = 45
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 45) {
                if (callLayer.retiring && callLayer.lifetime < 0.8 && callLayer.lifetime > 0.2
                        && callLayer.controlTravel < 1 && window.visible && wings.lyricsCover < 1) {
                    window.smokeSawCallExit = true
                }
                if (callLayer.presenting)
                    return
                if (!window.smokeSawCallExit || window.discordPreview.active || !window.playbackActive || wings.lyricsCover > 0) {
                    window.failSmoke("ending the call did not fold the controls and return to continuing music")
                    return
                }
                smokeTimer.stop()
                console.log("PASS LRC word jumps and splashes, exact Wordtime, paused seeks and track change")
                console.log("PASS desktop expansion, staggered player, notification sizing, progress styles and pause")
                console.log("PASS Discord preview, automatic folding, staggered entry and exit, connected notification split")
                Qt.exit(0)
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(updatePanelRegion)
        Qt.callLater(updateExpandedRegion)
        if (smokeMode) {
            console.info("Starting standalone soundbar smoke test")
            restartDemo()
            demoLyrics.status = "none"
            smokeStarted = Date.now()
            smokeTimer.start()
        }
    }
}
