import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs as Dialogs
import QtQml.Models
import "BeatTracker.js" as BeatTracker
import "ImportedLyrics.js" as ImportedLyrics

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
    flags: Qt.Tool | Qt.FramelessWindowHint
        | Qt.WindowDoesNotAcceptFocus | Qt.NoDropShadowWindowHint
    title: "Sekai Soundbar"
    color: "transparent"
    readonly property rect workArea: desktop.workArea
    width: Math.min(1088, workArea.width)
    height: Math.min(workArea.height, Math.ceil(stage.height * stage.scale))
    x: workArea.x + Math.floor((workArea.width - width) / 2)
    y: workArea.y
    visible: workArea.width > 0 && presence.showing
    onVisibleChanged: {
        if (visible) {
            Qt.callLater(updateExpandedRegion)
            Qt.callLater(openPendingAppearance)
        } else {
            if (menuLoader && menuLoader.item && menuLoader.item.visible)
                menuLoader.item.dismiss()
            if (appearanceDialog && appearanceDialog.visible)
                appearanceDialog.close()
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
    property bool trayPreview: false
    property bool trayAppearancePending: false
    readonly property bool audioFallback: !demoMode && !media.player && systemAudio.audible
    property bool sustainedAudio: false
    onAudioFallbackChanged: if (!audioFallback) sustainedAudio = false
    readonly property bool playbackActive: media.player ? media.playing : sustainedAudio
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
    readonly property string activeTrackKey: media.player ? media.player.trackKey : ""
    property var localLyrics: null
    readonly property var onlineLyrics: !demoMode && lyricsSearch.trackKey === activeTrackKey
        && lyricsSearch.document.ok === true ? lyricsSearch.document : null
    readonly property var timingDocument: localLyrics && localLyrics.key === activeTrackKey
        ? localLyrics.document : onlineLyrics
    onActiveTrackKeyChanged: {
        if (activeTrackKey === "")
            trayPreview = false
        if (matchPicker && matchPicker.opened)
            matchPicker.close()
        if (localLyrics && localLyrics.key !== activeTrackKey)
            clearLyrics()
        if (!smokeMode)
            lyricsExpanded = true
    }
    property url smokeLrc
    property url smokeWordtime
    readonly property bool smokeImports: smokeMode && smokeLrc.toString() !== "" && smokeWordtime.toString() !== ""
    property int smokePhase: 0
    property real smokeStarted: 0
    property bool smokeCapturePending: false
    property real smokeLandingTime: 0
    property real smokeFirstMarkerX: 0
    property bool smokeObstructed: false
    property bool smokeHoldOpen: true

    DockPresence {
        id: presence
        playing: window.playbackActive
        paused: window.playbackPaused
        dismissed: window.swipeDismissed
        fullscreen: window.desktop.fullscreenActive
        idleDelay: demoHost.settings.collapseDelay
        pauseDelay: window.smokeMode ? 1700 : 60000
        holdOpen: window.trayPreview || window.trayAppearancePending
            || (window.smokeMode && window.smokeHoldOpen)
            || (menuLoader.item?.visible ?? false) || appearanceDialog.visible
            || lyricsPicker.visible || lyricsMessage.visible || alignmentDialog.visible
            || proxyDialog.visible || matchPicker.visible || wings.lyricsView.swipeDragging
    }
    Timer {
        interval: 350
        running: window.audioFallback && !window.sustainedAudio
        onTriggered: window.sustainedAudio = true
    }
    Timer {
        interval: 400
        running: window.expansionClear && !window.expandedSpaceReady
        onTriggered: window.expandedSpaceReady = true
    }

    readonly property rect bodyRegion: {
        if (!presence.interactive)
            return Qt.rect(0, 0, 0, 0)
        const padding = 26
        return scaledRect(pill.x + wings.lyricsView.swipeX - padding,
            pill.y + wings.lyricsView.swipeY - padding, pill.width + 2 * padding,
            pill.capHeight + 2 * padding)
    }
    readonly property rect leftRegion: capsuleRegion(-1)
    readonly property rect rightRegion: capsuleRegion(1)
    readonly property real regionRadius: (wings.radius + 26) * stage.scale
    readonly property rect expandedRegion: {
        const size = wings.lyricsView.expandedBodySize
        return scaledRect((stage.width - size.width) / 2, pill.y, size.width, size.height)
    }
    onBodyRegionChanged: Qt.callLater(updatePanelRegion)
    onLeftRegionChanged: Qt.callLater(updatePanelRegion)
    onRightRegionChanged: Qt.callLater(updatePanelRegion)
    onRegionRadiusChanged: Qt.callLater(updatePanelRegion)
    onHeightChanged: Qt.callLater(updatePanelRegion)
    onExpandedRegionChanged: Qt.callLater(updateExpandedRegion)
    onWorkAreaChanged: Qt.callLater(updateExpandedRegion)

    function scaledRect(x, y, width, height) {
        const scale = stage.scale
        return Qt.rect(x * scale, y * scale, width * scale, height * scale)
    }

    function capsuleRegion(side) {
        if (!presence.interactive || wings.phase < 0.01)
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

    function updateExpandedRegion() {
        desktop.setExpandedRegion(window, expandedRegion, 40 * stage.scale)
    }

    function toggleLyricsLayout() {
        lyricsExpanded = !expandedDock
    }

    function openPendingAppearance() {
        if (visible && trayAppearancePending) {
            appearanceDialog.open()
            trayAppearancePending = false
        }
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
        localLyrics = null
        lyricsExpanded = !smokeMode
    }

    function importLyrics(file, targetKey) {
        if (!targetKey || targetKey !== activeTrackKey || !media.player)
            return "Трек сменился. Выберите файл для текущего трека."
        const result = lyricsImport.read(file, media.player.lengthSupported ? media.player.length : 0)
        return applyLyricsDocument(result, targetKey)
    }

    function applyLyricsDocument(result, targetKey) {
        if (!result.ok)
            return result.message
        let document = result
        if (result.format === "wordtime") {
            try {
                const lines = ImportedLyrics.convert(result)
                document = Object.assign({}, result, {lines: lines, voices: ImportedLyrics.voices(result, lines)})
            } catch (error) {
                return String(error.message)
            }
        }
        localLyrics = {key: targetKey, document: document}
        lyricsExpanded = true
        return ""
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
            readonly property bool limitPlayerOvershoot: true
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
        width: Math.max(760, window.width)
        height: pill.y + pill.height + 32 + Math.max(0, wings.lyricsView.swipeY)
        scale: window.width / width
        transformOrigin: Item.TopLeft

        Rectangle {
            id: solidHousing
            x: wings.housingRect.x
            y: wings.housingRect.y
            width: wings.housingRect.width
            height: wings.housingRect.height
            radius: wings.housingRadius
            visible: !wings.ownsHousing
            color: demoHost.dock.palette.fill
            border.color: demoHost.dock.palette.rim
            border.width: 2
            antialiasing: true
        }

        MouseArea {
            x: pill.x + wings.lyricsView.swipeX
            y: pill.y + wings.lyricsView.swipeY
            width: pill.width
            height: pill.capHeight
            enabled: presence.interactive && !!window.media.player
            cursorShape: Qt.PointingHandCursor
            onClicked: window.toggleLyricsLayout()
        }

        DockWings {
            id: wings
            objectName: "standaloneDockWings"
            anchors.fill: parent
            host: demoHost
            hideProgress: presence.hideProgress
            previewGlass: appearanceDialog.visible
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
    AppearanceDialog {
        id: appearanceDialog
        parent: Overlay.overlay
        appearance: window.appearance
        ownerWindow: window
        effectsAvailable: wings.shaderAvailable
        desktopGlassAvailable: window.desktopGlassAvailable
        backdrop: wings.backdropItem
    }
    Connections {
        target: window.desktop
        function onShowRequested() {
            if (window.activeTrackKey !== "" && !window.desktop.fullscreenActive && !window.playbackActive) {
                wings.lyricsView.dismissedUntilPlay = false
                window.trayPreview = true
            }
        }
        function onAppearanceRequested() {
            if (window.desktop.fullscreenActive)
                return
            window.trayAppearancePending = true
            Qt.callLater(window.openPendingAppearance)
        }
    }
    Connections {
        target: window.lyricsAlignment
        function onAligned(trackKey, document) {
            if (trackKey === "" || trackKey !== window.activeTrackKey)
                return
            const message = window.applyLyricsDocument(document, trackKey)
            if (message)
                alignmentDialog.saveError = message
        }
    }
    Dialog {
        id: proxyDialog
        parent: Overlay.overlay
        width: Math.min(460, window.width)
        x: Math.round((window.width - width) / 2)
        y: Math.max(40, Math.round((window.height - height) / 2))
        popupType: Popup.Window
        modal: true
        focus: true
        title: "Прокси поиска лирики"
        onOpened: {
            proxyInput.text = window.lyricsSearch.proxyAddress
            proxyError.text = ""
            proxyInput.forceActiveFocus()
        }
        function save() {
            proxyError.text = window.lyricsSearch.configureProxy(proxyInput.text)
            if (!proxyError.text)
                accept()
        }
        contentItem: Column {
            spacing: 8
            Label {
                width: parent.width
                text: "Укажите адрес локального прокси. Пустое поле включает обычное подключение."
                wrapMode: Text.WordWrap
            }
            TextField {
                id: proxyInput
                width: parent.width
                placeholderText: "socks5h://127.0.0.1:10808"
                placeholderTextColor: "#8bb0a4"
                maximumLength: 120
                selectByMouse: true
                onAccepted: proxyDialog.save()
            }
            Row {
                spacing: 8
                Button {
                    text: "INCY SOCKS5"
                    onClicked: proxyInput.text = "socks5h://127.0.0.1:10808"
                }
                Button {
                    text: "INCY HTTP"
                    onClicked: proxyInput.text = "http://127.0.0.1:10809"
                }
            }
            Label {
                id: proxyError
                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
                color: "#f6adad"
                wrapMode: Text.WordWrap
            }
            Row {
                width: parent.width
                spacing: 8
                layoutDirection: Qt.RightToLeft
                Button {
                    text: "Сохранить"
                    onClicked: proxyDialog.save()
                }
                Button {
                    text: "Отмена"
                    onClicked: proxyDialog.reject()
                }
            }
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
                        window.localLyrics = null
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
            property bool openAppearanceAfterClose: false
            function openAppearance() {
                if (window.visible)
                    appearanceDialog.open()
            }
            onClosed: {
                const showAppearance = openAppearanceAfterClose
                openAppearanceAfterClose = false
                Qt.callLater(() => {
                    // Release the software backing store when its top-level popup closes.
                    if (stage.GraphicsInfo.api === GraphicsInfo.Software && !panelMenu.visible)
                        menuLoader.active = false
                    if (showAppearance && window.visible)
                        appearanceDialog.open()
                })
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
                    onTriggered: Qt.callLater(() => proxyDialog.open())
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
                text: "Оформление дока…"
                onTriggered: {
                    if (panelMenu.visible) {
                        panelMenu.openAppearanceAfterClose = true
                        panelMenu.dismiss()
                    } else {
                        Qt.callLater(panelMenu.openAppearance)
                    }
                }
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
                        || (window.flags & Qt.WindowStaysOnTopHint)) {
                    window.failSmoke("panel is not frameless, transparent and centered on the top edge")
                    return
                }
                if (stage.GraphicsInfo.api === GraphicsInfo.Software && !solidHousing.visible) {
                    window.failSmoke("the software renderer needs a solid housing")
                    return
                }
                if (!wings.visible || (wings.ownsHousing === solidHousing.visible) || !isFinite(pill.width)
                        || Math.abs(pill.width - Math.min(demoHost.settings.compactWidth,
                            wings.lyricsView.maxBody)) > 0.5
                        || wings.suppressMediaKey || wings.reveal < 0.95
                        || !JSON.parse(wings.lyricsView.diagnostics()).trackHeaderVisible
                        || visualizerService.bands.length !== 64) return
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
                if (window.smokeImports && (lyrics.wordStart !== 4
                        || !(lyrics.nextWordStart > 4.9 && lyrics.nextWordStart < 9))) {
                    window.failSmoke("the LRC line has no estimated second word landing")
                    return
                }
                window.captureSmoke("expanded lyrics", function() {
                    if (window.smokeImports) {
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
                if (wait < 1050) return
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
            } else if (window.smokePhase === 12 && wait >= 500) {
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
            } else if (window.smokePhase === 13 && wait >= 1250) {
                if (window.visible || presence.hideProgress !== 1 || window.bodyRegion.width > 0
                        || wings.housingRect.y + wings.housingRect.height > 0) {
                    window.failSmoke("the idle drop did not fully leave through the top edge")
                    return
                }
                window.smokeObstructed = true
                window.smokeNoSession = false
                window.demoPlaying = true
                window.smokePhase = 14
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 14 && wait >= 850) {
                if (!presence.interactive || !window.visible || wings.lyricsView.wide) {
                    window.failSmoke("resuming playback did not restore the unobscured compact layout")
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
                window.smokePhase = 15
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 15 && wait >= 700) {
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
                window.smokePhase = 16
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 16 && wait >= 1000) {
                if (window.visible || window.trayPreview || presence.hideProgress !== 1) {
                    window.failSmoke("a completed swipe left a visible dock")
                    return
                }
                window.desktop.showRequested()
                window.smokePhase = 17
                window.smokeStarted = Date.now()
            } else if (window.smokePhase === 17 && wait >= 850) {
                if (!presence.interactive || window.swipeDismissed
                        || !JSON.parse(wings.lyricsView.diagnostics()).trackHeaderVisible) {
                    window.failSmoke("the tray did not restore the paused track after a swipe")
                    return
                }
                smokeTimer.stop()
                console.log("PASS LRC word jumps and splashes, exact Wordtime, paused seeks and track change")
                console.log("PASS desktop expansion, pause delay, swipe dismissal and restoring the dock")
                Qt.exit(0)
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(updatePanelRegion)
        Qt.callLater(updateExpandedRegion)
        if (smokeMode) {
            restartDemo()
            demoLyrics.status = "none"
            smokeStarted = Date.now()
            smokeTimer.start()
        }
    }
}
