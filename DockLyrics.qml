pragma ComponentBehavior: Bound
import QtQuick
import "DockMaterial.js" as Material
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion
import QtQuick.Effects
import QtQuick.Controls as Controls
import "LyricsMath.js" as LM
import "LightMotion.js" as LightMotion
import "ImportedLyrics.js" as ImportedLyrics
import "VoiceAnnotations.js" as VoiceAnnotations
import "AnalysisPolicy.js" as AnalysisPolicy
import "LyricsEnd.js" as LyricsEnd
import "BackingLayout.js" as BackingLayout
import "MultiVoiceMath.js" as Voices

Item {
    id: root
    property var glassSource: null
    property bool desktopLens: false
    readonly property var material: Material.read(host.settings)
    readonly property vector4d materialStyle: Qt.vector4d(material.enabled ? 1 : 0, material.blur, material.darkening, material.refraction)
    property rect glassRect: Qt.rect(0, 0, 1, 1)
    property bool gatheringParts: false
    property bool staggeredOpening: false
    property real openingProgress: 1
    property rect openingBounds: Qt.rect(0, 0, 1, 1)
    property point miniCenter: Qt.point(0, 0)
    readonly property real coverAlpha: coverMotion.alpha
    readonly property real progressAlpha: progressMotion.alpha
    readonly property var partProgress: [coverMotion.progress, titleMotion.progress, artistMotion.progress,
        progressMotion.progress, sheetMotion.progress]
    required property var host

    component PlayerPart: DockPartMotion {
        destination: root.miniCenter
        tucking: root.gatheringParts
        entrance: root.openingProgress
        entranceBounds: root.openingBounds
        entranceSurface: Qt.size(root.width, root.height)
    }
    // Optional host-specific cache/IPC behavior; the view itself uses only Qt.
    property Component bridgeComponent: null
    Loader {
        id: platformBridge
        sourceComponent: root.bridgeComponent
        onLoaded: item.surface = Qt.binding(() => root)
    }
    readonly property var media: host.dock.mediaSource || null
    readonly property var player: media ? media.player : null
    readonly property var lyrics: host.dock.lyrics || null
    readonly property bool playing: !!media && media.playing
    readonly property bool nativeClock: !!player && typeof player.positionNow === "function"
    readonly property string trackUrl: player && !nativeClock ? String((player.metadata || {})["xesam:url"] || "") : ""
    readonly property string youtubeId: {
        if (!/^https?:\/\/(?:www\.|m\.|music\.)?(?:youtube\.com|youtu\.be)\//i.test(trackUrl)) return ""
        const match = trackUrl.match(/(?:[?&]v=|youtu\.be\/|\/shorts\/)([A-Za-z0-9_-]{11})(?:[^A-Za-z0-9_-]|$)/)
        return match ? match[1] : ""
    }
    readonly property string signature: nativeClock ? player.trackKey : AnalysisPolicy.identity({url: trackUrl,
        artist: media ? media.artist : "", title: media ? media.title : ""})
    readonly property real reportedDuration: player && player.lengthSupported && isFinite(Number(player.length))
        && Number(player.length) > 0 ? Number(player.length) : 0
    property real rememberedDuration: 0
    readonly property var wordtimeStore: host.service ? host.service.wordtimes || null : null
    readonly property var wordtimeTrack: ({ title: media ? media.title : "", artist: media ? media.artist : "",
        url: trackUrl, duration: reportedDuration || rememberedDuration
            || (youtubeId && host.service && host.service.durationCache ? host.service.durationCache[youtubeId] || 0 : 0) })
    readonly property var wordtimeResult: wordtimeStore ? wordtimeStore.resultFor(wordtimeTrack)
        : nativeClock ? (host.dock.timingDocument ?? null) : null
    readonly property bool importedTiming: !!wordtimeResult && wordtimeResult.status === "ready"
    readonly property bool hasTimingDocument: importedTiming || (!!wordtimeResult && wordtimeResult.status === "partial")
    readonly property bool processingForLyrics: !!wordtimeStore && !!wordtimeStore.generationJob
        && wordtimeStore.generationJob.token === wordtimeStore.token(wordtimeTrack)
    readonly property bool recordingForLyrics: !!wordtimeStore
        && wordtimeStore.captureBusy && !!wordtimeStore.captureJob
        && wordtimeStore.captureJob.key === signature
    Timer {
        id: timingRequest
        interval: 180
        onTriggered: { if (root.wordtimeStore && root.player) root.wordtimeStore.request(root.wordtimeTrack, false) }
    }
    onWordtimeTrackChanged: { timingRequest.restart(); autoTiming.restart() }
    onWordtimeStoreChanged: timingRequest.restart()
    onWordtimeResultChanged: { if (wordtimeStore && !wordtimeResult) timingRequest.restart() }
    function importWordtime(file) {
        return !!wordtimeStore && !!player && wordtimeStore.enqueue("import", wordtimeTrack, file)
    }
    function removeWordtime() {
        return !!wordtimeStore && !!player && wordtimeStore.enqueue("remove", wordtimeTrack, "")
    }
    readonly property real duration: reportedDuration || rememberedDuration
        || (youtubeId && host.service && host.service.durationCache ? host.service.durationCache[youtubeId] || 0 : 0)
        || (hasTimingDocument ? wordtimeResult.duration : 0)
    function refreshDuration() {
        if (reportedDuration > 0) rememberedDuration = reportedDuration
        else if (youtubeId && host.service && typeof host.service.requestYoutubeDuration === "function")
            host.service.requestYoutubeDuration(youtubeId)
    }
    onReportedDurationChanged: refreshDuration()
    onYoutubeIdChanged: refreshDuration()
    onHostChanged: refreshDuration()
    readonly property bool sameTrack: !!lyrics && !!media && lyrics.lastArgs
        && lyrics.lastArgs[0] === media.artist && lyrics.lastArgs[1] === media.title
    readonly property string rawLyricsText: platformBridge.item ? platformBridge.item.rawLyricsText : ""
    readonly property string rawLyricsKey: platformBridge.item ? platformBridge.item.rawLyricsKey : ""
    readonly property bool rawLyricsCurrent: sameTrack && !!lyrics && rawLyricsKey === lyrics.trackId && rawLyricsText !== ""
    readonly property var standardLines: sameTrack && lyrics.status === "ready"
        ? (rawLyricsCurrent ? VoiceAnnotations.rawLines(rawLyricsText) : lyrics.lines) : []
    readonly property string standardLyricsText: rawLyricsCurrent ? rawLyricsText : ImportedLyrics.toLrc(standardLines)
    readonly property var annotatedDocument: VoiceAnnotations.fromLines(standardLines, duration)
    readonly property var presentationDocument: hasTimingDocument && wordtimeResult.format === "lrc"
        ? wordtimeResult : BackingLayout.project(hasTimingDocument ? wordtimeResult : annotatedDocument,
            hasTimingDocument && wordtimeResult.format === "enhanced-lrc" ? wordtimeResult.lines : standardLines, duration)
    readonly property var voiceDocument: presentationDocument
    readonly property var allLines: presentationDocument.lines
    readonly property var lines: allLines.filter(l=>l.role!=="backing")
    readonly property bool multiVoiceAvailable: host.settings.multivoice !== false
        && Voices.normalize(voiceDocument).length>1
        && !lines.some(l => String(l.text || "").trim() && (!l.voiceIds || !l.voiceIds.length))
    readonly property var endBounds: LyricsEnd.bounds(allLines, duration)
    readonly property var finaleState: LyricsEnd.frame(endBounds, lyricTime, duration,
        processingForLyrics ? {timelineComplete:false} : hasTimingDocument ? wordtimeResult.analysis : null)
    readonly property bool lyricsEnded: available && finaleState.ended
    readonly property bool multiVoiceActive: multiVoiceAvailable && layout > 0.5
    readonly property var timingReference: ImportedLyrics.reference(annotatedDocument.lines, duration, annotatedDocument.voices)
    Timer {
        id: autoTiming
        interval: 600
        onTriggered: {
            if (!root.wordtimeStore || !root.wordtimeStore.analysisRequests[root.wordtimeStore.token(root.wordtimeTrack)]) return
            root.wordtimeStore.requestAnalysis(root.wordtimeTrack,root.standardLyricsText,root.timingReference)
        }
    }
    Timer {
        interval: 100; repeat: true
        running: !!root.wordtimeStore && (!!root.player || root.wordtimeStore.captureBusy)
        onTriggered: {
            const stamp = Date.now()
            const spotify = !!root.player && (String(root.player.identity || "").toLowerCase() === "spotify"
                || String(root.player.desktopEntry || "").toLowerCase() === "spotify"
                || String(root.player.dbusName || "").toLowerCase() === "org.mpris.mediaplayer2.spotify")
            root.wordtimeStore.updatePlayback({ track: root.wordtimeTrack, text: root.standardLyricsText, reference: root.timingReference,
                owner: root.host.dock.screenName || "dock", spotify: spotify,
                sourceReady: root.rawLyricsCurrent || !root.lyrics || !root.lyrics.cacheScript,
                state: { key: root.signature, playing: root.playing, stamp: stamp,
                    position: LM.estimate(root.clock, stamp, root.playing),
                    enabled: !root.host.dock.asleep && root.host.settings.enabled !== false
                        && root.host.settings.lyrics !== false && root.host.settings.autoSpotify !== false
                        && !!root.player && root.player.positionSupported
 } })
        }
    }
    onStandardLyricsTextChanged: autoTiming.restart()
    Connections {
        target: root.wordtimeStore
        function onEngineReadyChanged() { autoTiming.restart() }
        function onGenerationBusyChanged() { autoTiming.restart() }
        function onCacheChanged() { autoTiming.restart() }
        function onRequestedRefreshChanged() { autoTiming.restart() }
    }
    Connections { target: root.host; function onWorkingChanged() { autoTiming.restart() } }
    readonly property bool available: host.settings.lyrics !== false && !host.dock.vertical
        && lines.some(line => !!line.text && line.text.trim() !== "")
    readonly property bool compactTrackHeader: nativeClock && !available
    // A selected track keeps its player surface when paused or without lyrics.
    property bool dismissedUntilPlay: false
    readonly property bool wantsMusic: host.working && !!player && !!media && !!media.title
        && !dismissedUntilPlay && host.settings.lyrics !== false && !host.dock.vertical && !host.dock.editing
    readonly property string emptyLabel: nativeClock && !lyrics
        ? (host.dock.lyricsStatus || "Лирика недоступна") : sameTrack && lyrics
        && (lyrics.status === "none" || lyrics.status === "instrumental") ? "Инструментальная"
        : sameTrack && lyrics && lyrics.status === "offline" ? "Лирика недоступна" : "Поиск лирики…"
    readonly property bool wide: wantsMusic && host.settings.expandLyrics !== false && !!host.dock.desktopEmpty
    readonly property string mode: !wantsMusic ? "icons" : host.dock.hovered ? (wide ? "icons+controls" : "icons")
        : wide ? (available ? "lyrics-expanded" : "instrumental-expanded")
            : (available ? "lyrics-compact" : "instrumental-compact")
    function report() {
        if (typeof host.reportSurface === "function")
            host.reportSurface({ mode: mode, desktopEmpty: !!host.dock.desktopEmpty,
                playing: playing, lyrics: lines.length, wide: wide, content: available ? "lyrics" : emptyLabel })
    }
    onModeChanged: report()
    onLinesChanged: report()
    property real wideReveal: 0
    property bool ready: false
    readonly property real layout: Math.max(0, Math.min(staggeredOpening || host.settings.limitPlayerOvershoot ? 1 : 1.08,
        staggeredOpening ? Geometry.arrival(wideReveal, 0.055) : wideReveal))
    readonly property real layoutSpring: staggeredOpening ? Geometry.recoil(Geometry.phase(wideReveal, 0.72, 1)) : 0
    readonly property real headerUnfold: staggeredOpening && !compactTrackHeader ? wideReveal : 1
    readonly property real baseWidth: host.dock.baseWidth || host.dock.item.width
    readonly property real baseHeight: host.dock.baseCapHeight || 69
    readonly property real maxBody: Math.max(280,
        (host.dock.stageWidth || 1100) - 2 * (Math.min(host.settings.width || 200, 200) + (host.settings.gap || 12) + 26))
    readonly property bool showMusic: wantsMusic && (!host.dock.hovered || wide)
    property real musicReveal: showMusic ? 1 : 0
    Behavior on musicReveal { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }
    readonly property real musicLayout: Math.max(0, Math.min(1, musicReveal))
    property real voiceExpansion: multiVoiceAvailable ? 1 : 0
    Behavior on voiceExpansion { NumberAnimation { duration: 480; easing.type: Easing.OutCubic } }
    function expandedWidthFor(voices) {
        return Math.min((host.settings.lyricsWidth || 560) + (host.settings.voiceWidth ?? 80) * voices, maxBody)
    }
    function expandedHeightExtraFor(voices) {
        return 136 + (host.settings.voiceHeight ?? 28) * voices
    }
    readonly property size expandedBodySize: Qt.size(expandedWidthFor(multiVoiceAvailable ? 1 : 0),
        76 + expandedHeightExtraFor(multiVoiceAvailable ? 1 : 0))
    readonly property real expandedWidth: expandedWidthFor(voiceExpansion)
    readonly property real targetWidth: Math.min(host.settings.compactWidth ?? 480, maxBody) + (expandedWidth - Math.min(host.settings.compactWidth ?? 480, maxBody)) * layout
    // Signed deltas let a long native dock contract to the reference proportions.
    readonly property real extraWidth: (targetWidth - baseWidth) * musicLayout + 10 * layoutSpring
    readonly property real extraHeight: (76 - baseHeight) * musicLayout
        + expandedHeightExtraFor(voiceExpansion) * layout + 6 * layoutSpring
    readonly property real headerHeight: Math.max(100 * layout, swipeEnabled ? 14 : 0)
    readonly property real iconsOffset: 84 * layout
    readonly property real iconsScale: 1 - (1 - Math.min(1,
        Math.max(1, dock.capWidth - 48) / Math.max(1, baseWidth - 36))) * Math.min(1, layout)
    property real lyricsOpacity: wantsMusic && !host.dock.hovered ? 1 : 0
    Behavior on lyricsOpacity { NumberAnimation { duration: root.host.settings.lyricFade ?? 240; easing.type: Easing.InOutCubic } }

    function animateLayout() {
        if (!ready) return
        const value = wideReveal
        widen.stop(); narrow.stop()
        const animation = wide ? widen : narrow
        animation.from = value
        animation.start()
    }
    onWideChanged: animateLayout()
    NumberAnimation {
        id: widen; target: root; property: "wideReveal"; to: 1
        duration: root.host.settings.expandDuration ?? 850
        easing.type: root.staggeredOpening ? Easing.Linear : Easing.OutBack
        easing.overshoot: root.host.settings.playerSpring ?? 1.2
    }
    NumberAnimation { id: narrow; target: root; property: "wideReveal"; to: 0; duration: 600; easing.type: Easing.InOutCubic }

    property var clock: LM.clockReset(0, Date.now())
    property real now: Date.now()
    property real lastPosition: -1
    property int stale: 0
    property real position: 0
    function tick(stamp) {
        now = stamp
        position = nativeClock ? player.positionNow() : Math.max(0, LM.estimate(clock, stamp, playing))
    }
    readonly property real lyricTime: position + (hasTimingDocument ? 0 : 0.2) + (sameTrack && lyrics ? lyrics.syncTotal / 1000 : 0)

    function poll() {
        if (nativeClock) { tick(Date.now()); return }
        if (!player || !player.positionSupported) { tick(Date.now()); return }
        player.positionChanged()
        const value = Number(player.position)
        if (!isFinite(value) || value < 0) { tick(Date.now()); return }
        // A browser may briefly return zero without a real restart. Keep the
        // clock running; a genuine seek is accepted as soon as it advances.
        if (value === 0 && ((playing && lastPosition === 0) || LM.estimate(clock, Date.now(), playing) > 2)) {
            tick(Date.now()); return
        }
        const trust = LM.pollTrust(lastPosition, value, stale, playing)
        lastPosition = value; stale = trust.stale
        if (trust.use) clock = LM.observe(clock, value, Date.now(), playing)
        tick(Date.now())
    }
    onSignatureChanged: {
        if (playing && host.service && typeof host.service.resetRhythm === "function") host.service.resetRhythm()
        rememberedDuration = 0; refreshDuration()
        clock = LM.clockReset(0, Date.now()); lastPosition = -1; stale = 0; tick(Date.now())
        poll()
    }
    Connections {
        target: root.nativeClock ? root.player : null
        function onChanged() { root.tick(Date.now()) }
    }
    onPlayingChanged: {
        autoTiming.restart()
        if (playing) {
            if (swipeDragging) finishSwipe(false)
            dismissedUntilPlay = false
        }
        const stamp = Date.now()
        clock = LM.clockReset(LM.estimate(clock, stamp, !playing), stamp)
        lastPosition = -1; stale = 0; tick(stamp)
        poll()
    }
    Timer { interval: 250; repeat: true; running: root.host.working && !!root.player; onTriggered: root.poll() }
    property real ambientTime: 0
    property real glowTime: 0
    property real heartPhase: 0
    property real visualStamp: Date.now()
    FrameAnimation {
        running: root.host.working && (root.playing || root.ambientBlend > 0.001)
            && (root.lyricsOpacity > 0.001 || root.layout > 0.001)
        onRunningChanged: root.visualStamp = Date.now()
        onTriggered: {
            const stamp = Date.now()
            if (stamp - root.visualStamp >= 16) {
                const dt = Math.min(0.06, (stamp - root.visualStamp) / 1000)
                root.glowTime += dt
                root.heartPhase = (root.heartPhase + dt * root.heartBpm / 60) % 1
                if (root.ambientBlend > 0.001)
                    root.ambientTime += dt
                root.visualStamp = stamp
                if (root.playing) root.tick(stamp)
            }
        }
    }
    Component.onCompleted: { ready = true; animateLayout(); refreshDuration(); poll(); report(); timingRequest.restart() }

    function mixColor(a, b, amount) {
        return Qt.rgba(a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount,
            a.b + (b.b - a.b) * amount, a.a + (b.a - a.a) * amount)
    }
    readonly property var colors: {
        const p = host.dock.palette
        return { ink: p.ink, accent: p.accent,
            muted: mixColor(p.fill, p.ink, 0.46),
            secondary: mixColor(p.fill, p.ink, 0.7),
            module: mixColor(p.fill, p.ink, 0.025),
            divider: p.rim }
    }
    // A delayed light pool follows the shared marker, including line bridges.
    // Two softer followers spread the trail instead of drawing a rigid beam.
    readonly property real waitingLightAmount: {
        if (!available || !playing || !reel.waiting || multiVoiceActive) return 0
        const p = reel.transfer ? reel.transfer.phase : 0
        return 1 - p * p * (3 - 2 * p)
    }
    readonly property real waitingLightAngle: LightMotion.motionTime(
        Math.max(0, lyricTime - (reel.current.t || 0))) * Math.PI * 2 / 1.8
    readonly property bool ambientLight: wantsMusic && wide && (!playing || !available || lyricsEnded)
    property real ambientBlend: ambientLight ? 1 : 0
    Behavior on ambientBlend { NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
    readonly property real fishTime: LightMotion.motionTime(ambientTime)
    readonly property real audioPulse: playing && host.service ? (host.service.beatPulse || 0) : 0
    property real beatGlow: audioPulse
    Behavior on beatGlow { NumberAnimation { duration: 65 } }
    readonly property real heartBpm: host.service && host.service.beatBpm > 0
        && host.service.beatConfidence >= 0.65 ? host.service.beatBpm : 72
    onAudioPulseChanged: if (audioPulse > 0.9 && playing) heartPhase = 0
    readonly property real heartPulse: Math.exp(-Math.pow((heartPhase - 0.1) / 0.065, 2))
        + 0.5 * Math.exp(-Math.pow((heartPhase - 0.32) / 0.08, 2))
    readonly property vector2d glowBreath: Qt.vector2d(
        1 + 0.035 * Math.sin(glowTime * 1.3) + 0.015 * Math.sin(glowTime * 0.71 + 0.8) + beatGlow * 0.065,
        1 + 0.055 * Math.sin(glowTime * 1.05 + 0.4) + 0.025 * Math.sin(glowTime * 1.81) + beatGlow * 0.2)
    readonly property vector2d fishPosition: Qt.vector2d(
        reel.x + reel.width * (0.5 + 0.32 * Math.sin(fishTime * 0.47)
            + 0.035 * Math.sin(fishTime * 0.91 + 1.3)),
        reel.y + reel.height * (0.5 + 0.22 * Math.sin(fishTime * 0.63 + 0.6)))
    readonly property vector3d wordLightTarget: {
        if (multiVoiceActive && playing) return Qt.vector3d(0, 0, 0)
        const orbit = waitingLightAmount
        const centerX = reel.x + reel.width / 2
        const centerY = reel.y + reel.height / 2 + (reel.currentIndex - reel.cursor) * 30
        const x = centerX + Math.cos(waitingLightAngle) * (host.settings.orbitRadius ?? 23)
        const y = centerY + Math.sin(waitingLightAngle) * (host.settings.orbitRadius ?? 23)
        const markerX = reel.x + reel.markerPose.x
        const markerY = reel.y + reel.markerPose.y + 15
        const followX = markerX + (x - markerX) * orbit
        const followY = markerY + (y - markerY) * orbit
        const followAlpha = available ? (reel.waiting ? 1 : reel.markerPose.alpha) : 0
        return Qt.vector3d(followX + (fishPosition.x - followX) * ambientBlend,
            followY + (fishPosition.y - followY) * ambientBlend,
            wantsMusic ? (followAlpha + (1 - followAlpha) * ambientBlend) * lyricsOpacity : 0)
    }
    property vector3d wordLight: wordLightTarget
    property vector3d wordLightTail: wordLight
    property vector3d wordLightMist: wordLightTail
    Behavior on wordLight {
        enabled: root.ready && (root.playing || root.ambientBlend > 0.001)
            && Math.abs(root.wordLightTarget.x - root.wordLight.x) < 180
        Vector3dAnimation { duration: root.host.settings.followDelay ?? 190; easing.type: Easing.OutCubic }
    }
    Behavior on wordLightTail { Vector3dAnimation { duration: root.waitingLightAmount > 0.5 ? 320 : (root.host.settings.trailDelay ?? 230); easing.type: Easing.OutCubic } }
    Behavior on wordLightMist { Vector3dAnimation { duration: root.waitingLightAmount > 0.5 ? 420 : (root.host.settings.mistDelay ?? 300); easing.type: Easing.OutCubic } }
    readonly property var dock: host.dock.item
    function openingPose() {
        return { cover: cover.opacity, coverScale: coverMotion.edgeScale.width, volume: volume.opacity }
    }
    function diagnostics(): string {
        return JSON.stringify({ mode: root.mode, available: root.available, wide: root.wide,
            timingSource: root.importedTiming ? "imported" : root.hasTimingDocument ? "mixed" : "standard",
            timingWords: root.hasTimingDocument ? root.wordtimeResult.wordCount : 0,
            voices: root.multiVoiceAvailable ? root.voiceDocument.voices.map(v => ({id: v.id, label: v.label})) : [],
            voiceRegions: root.multiVoiceActive ? multiReel.regions : [],
            lyricsEnded: root.lyricsEnded, finale: root.finaleState.phase, playing: root.playing, content: root.available ? "lyrics" : root.emptyLabel, ambient: root.ambientLight, dismissed: root.dismissedUntilPlay, swipe: [root.swipeX, root.swipeY], swipeDirection: root.lastSwipeDirection, position: root.position, duration: root.duration, reportedDuration: root.reportedDuration, youtubeId: root.youtubeId, index: reel.currentIndex,
            text: reel.current.text, lineOnly: reel.current.lineOnly === true,
            wordSpans: (reel.current.wordSpans || []).length,
            trackHeaderVisible: header.visible && header.opacity * titleMotion.alpha * titleMotion.entranceOpacity > 0.95,
            progressRenderer: progress.rendererName, progressSpectrum: progress.spectrumPeak,
            waiting: reel.waiting, waitProgress: reel.waitProgress, cursor: reel.cursor,
            marker: [reel.markerPose.x, reel.markerPose.y, reel.markerPose.alpha], handoff: reel.transfer,
            wordStart: reel.markerPose.start, nextWordStart: reel.markerPose.next, markerAir: reel.markerPose.air,
            splashes: reel.landings.length, loadingLight: root.waitingLightAmount, heartBpm: root.heartBpm, beatGlow: root.beatGlow, wordLight: [root.wordLight.x, root.wordLight.y, root.wordLight.z],
            opacity: root.lyricsOpacity, musicLayout: root.musicLayout, iconsScale: root.iconsScale,
            bare: root.dock.bare, color: String(root.colors.ink), accent: String(root.colors.accent), visible: root.visible,
            box: [root.x, root.y, root.width, root.height], dock: [root.dock.x, root.dock.y, root.dock.width, root.dock.height] })
    }
    // The top edge is a grip, away from the playback controls. Parent-space
    // coordinates keep dragging stable while the visual surface follows it.
    readonly property bool swipeEnabled: wantsMusic && !playing
    property bool swipeDragging: false
    property real swipeX: 0
    property real swipeY: 0
    property real swipeStartX: 0
    property real swipeStartY: 0
    property real swipeDX: 0
    property real swipeDY: 0
    property real swipeVelocity: 0
    property real swipeStamp: 0
    property string lastSwipeDirection: ""
    onSwipeEnabledChanged: if (!swipeEnabled && swipeDragging) finishSwipe(false)
    function beginSwipe(x, y) {
        if (!swipeEnabled) return false
        swipeReturn.stop()
        swipeDragging = true
        swipeStartX = x; swipeStartY = y
        swipeDX = 0; swipeDY = 0; swipeVelocity = 0; swipeStamp = Date.now()
        return true
    }
    function moveSwipe(x, y) {
        if (!swipeDragging) return
        const dx = x - swipeStartX, dy = y - swipeStartY
        const stamp = Date.now()
        swipeVelocity = Math.hypot(dx - swipeDX, dy - swipeDY) / Math.max(8, stamp - swipeStamp)
        swipeDX = dx; swipeDY = dy; swipeStamp = stamp
        swipeX = Math.max(-64, Math.min(64, dx * 0.35))
        swipeY = Math.max(-64, Math.min(64, dy * 0.35))
    }
    function finishSwipe(allowDismiss) {
        if (!swipeDragging) return false
        swipeDragging = false
        const distance = Math.hypot(swipeDX, swipeDY)
        const flick = Date.now() - swipeStamp < 100 && swipeVelocity > 0.65 && distance > 18
        const commit = allowDismiss && swipeEnabled && (distance >= 46 || flick)
        if (commit) {
            lastSwipeDirection = Math.abs(swipeDX) > Math.abs(swipeDY)
                ? (swipeDX < 0 ? "left" : "right") : (swipeDY < 0 ? "up" : "down")
            swipeX += swipeDX / distance * 16
            swipeY += swipeDY / distance * 16
            dismissedUntilPlay = true
        }
        swipeBackX.from = swipeX; swipeBackY.from = swipeY
        swipeReturn.start()
        return commit
    }
    ParallelAnimation {
        id: swipeReturn
        NumberAnimation { id: swipeBackX; target: root; property: "swipeX"; to: 0; duration: 650; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
        NumberAnimation { id: swipeBackY; target: root; property: "swipeY"; to: 0; duration: 650; easing.type: Easing.OutBack; easing.overshoot: 0.9 }
    }
    transform: Translate { x: root.swipeX; y: root.swipeY }
    x: dock.x
    y: dock.y
    width: Math.max(1, dock.capWidth)
    height: Math.max(1, dock.capHeight)

    function timeLabel(seconds) {
        const value = Math.max(0, Math.floor(seconds || 0))
        return Math.floor(value / 60) + ":" + (value % 60 < 10 ? "0" : "") + value % 60
    }
    function seekTo(fraction) {
        if (player && player.canSeek && player.positionSupported && duration > 0) {
            if (nativeClock) {
                player.seek(fraction * duration)
                return
            }
            player.position = fraction * duration
            clock = LM.clockReset(fraction * duration, Date.now())
            tick(Date.now())
        }
    }

    // The same art and progress move between the two layouts, without crossfading copies.
    Rectangle {
        id: cover
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: coverMask
        }
        Rectangle {
            id: coverMask
            width: cover.width; height: cover.height
            radius: cover.radius
            color: "white"
            visible: false
            layer.enabled: true
        }
        x: 19 - 2 * Math.min(1, root.layout)
        y: 17 + 10 * Math.min(1, root.layout)
        width: 41 + 17 * Math.min(1, root.layout)
        height: 41 + 16 * Math.min(1, root.layout)
        radius: 10 + 2 * Math.min(1, root.layout)
            + (Math.min(width, height) / 2 - 12) * Math.max(0, coverMotion.progress)
        color: root.colors.module
        opacity: root.musicLayout * coverMotion.alpha * coverMotion.entranceOpacity
        visible: opacity > 0.001
        transform: PlayerPart {
            id: coverMotion
            part: cover
            entranceSlot: Qt.point(-0.23, 0.48); entranceDelay: 0.30; entranceEnd: 0.86
            tuckedScale: Qt.size(0.70, 0.72)
            tuckDelay: 120; tuckDuration: 710; tuckEasing: Easing.InOutSine
            returnDelay: 160; returnDuration: 685; spring: 0.86
            arc: 14; tilt: 14
        }
        Image {
            id: coverImage
            anchors.fill: parent
            source: root.media ? root.media.artUrl : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Text {
            anchors.centerIn: parent
            text: root.host.theme.iconFont ? "music_note" : "♪"
            visible: coverImage.status !== Image.Ready
            color: root.colors.ink
            font.family: root.host.theme.iconFont || root.host.theme.fontFamily; font.pixelSize: 25
        }
        Rectangle { anchors.fill: parent; color: root.colors.ink; opacity: artArea.containsMouse ? .12 : 0 }
        MouseArea {
            id: artArea
            objectName: "wordtimeCoverButton"
            anchors.fill: parent
            enabled: root.layout > .95 && !!root.wordtimeStore && root.wantsMusic
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            Controls.ToolTip.visible: containsMouse && enabled
            Controls.ToolTip.delay: 600
            Controls.ToolTip.text: "Тайминги слов · расчёт и импорт"
            onClicked: root.wordtimeStore.showForTrack(root.wordtimeTrack, root.host.theme, root.standardLyricsText)
        }
    }
    DockProgress {
        id: progress
        x: 68 + 14 * Math.min(1, root.layout)
        y: root.compactTrackHeader ? 53 + 10 * Math.min(1, root.layout) : 45 + 18 * Math.min(1, root.layout)
        width: Math.max(1, root.width - x - (68 + 14 * Math.min(1, root.layout)))
        height: 20
        opacity: root.musicLayout * progressMotion.alpha * progressMotion.entranceOpacity
        visible: opacity > 0.001 && root.opacity > 0.001 && (!root.nativeClock || root.player.positionSupported)
        transform: PlayerPart {
            id: progressMotion
            part: progress
            entranceSlot: Qt.point(0.03, 0.72); entranceDelay: 0.39; entranceEnd: 0.94
            entranceScale: Qt.size(0.22, 0.23)
            tuckedScale: Qt.size(0.075, 0.70)
            tuckDelay: 166; tuckDuration: 642; tuckEasing: Easing.InOutSine
            returnDelay: 205; returnDuration: 750; spring: 1.22
            arc: 22; tilt: -8
        }
        settings: root.host.settings
        palette: root.colors
        secondary: root.host.theme.accentMint || root.colors.ink
        bands: root.host.working ? (root.host.service?.bands ?? []) : []
        fraction: root.duration > 0 ? Math.max(0, Math.min(1, root.position / root.duration)) : 0
        indeterminate: root.duration <= 0
        playing: root.playing
        phase: root.position / 1.8
        seekable: !!root.player && root.player.canSeek && root.player.positionSupported && root.duration > 0
        onSeek: fraction => root.seekTo(fraction)
    }
    Item {
        id: volume
        x: root.width - 54
        y: root.compactTrackHeader ? 51 + 10 * Math.min(1, root.layout) : 26 + 34 * Math.min(1, root.layout)
        width: 24; height: 24
        opacity: root.musicLayout * volumeMotion.alpha * volumeMotion.entranceOpacity
        visible: opacity > 0.001 && (!root.nativeClock || root.player.volumeSupported)
        transform: PlayerPart {
            id: volumeMotion
            part: volume
            entranceSlot: Qt.point(0.27, 0.63); entranceDelay: 0.50; entranceEnd: 0.98
            tuckDelay: 82; tuckDuration: 480
            returnDelay: 278; returnDuration: 530; spring: 1.23
            arc: 21; tilt: -18
        }
        property real unmutedVolume: 1
        Image {
            anchors.centerIn: parent; width: 19; height: 19
            source: "assets/volume.svg"
            opacity: root.player && root.player.volume === 0 ? 0.4 : 1
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1
                colorizationColor: root.colors.ink
            }
        }
        MouseArea {
            anchors.fill: parent; anchors.margins: -5
            enabled: !!root.player && root.player.volumeSupported && root.player.canControl
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.nativeClock) { root.player.toggleMute(); return }
                if (root.player.volume > 0) { volume.unmutedVolume = root.player.volume; root.player.volume = 0 }
                else root.player.volume = volume.unmutedVolume
            }
            onWheel: wheel => { if (root.media) root.media.changeVolume(wheel.angleDelta.y > 0 ? 1 : -1) }
        }
    }
    Item {
        id: header
        width: parent.width
        height: 90
        visible: opacity > 0.001
        opacity: root.compactTrackHeader ? root.musicLayout
            : root.staggeredOpening ? Motion.smooth(root.wideReveal / 0.48) : Math.min(1, root.layout)
        Text {
            id: trackTitle
            x: progress.x; y: 12
            width: Math.max(1, playbackControls.x - x - 12)
            height: 20
            text: root.media ? root.media.title : ""
            elide: Text.ElideRight
            color: root.colors.ink
            font.family: root.host.theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold
            opacity: titleMotion.alpha * titleMotion.entranceOpacity
            transform: PlayerPart {
                id: titleMotion
                part: trackTitle
                unfold: Geometry.phase(root.headerUnfold, 0.02, 0.80)
                entranceSlot: Qt.point(0.04, 0.23); entranceDelay: 0.35; entranceEnd: 0.89
                pivot: Qt.point(Math.min(trackTitle.width, trackTitle.contentWidth) / 2, trackTitle.height / 2)
                tuckDelay: 78; tuckDuration: 585
                returnDelay: 245; returnDuration: 621; spring: 0.98
                arc: -14; tilt: -11
            }
        }
        Text {
            id: trackArtist
            x: progress.x; y: 33
            width: Math.max(1, playbackControls.x - x - 12)
            height: 16
            text: root.media ? root.media.artist : ""
            elide: Text.ElideRight
            color: root.colors.secondary
            font.family: root.host.theme.fontFamily; font.pixelSize: 11
            opacity: artistMotion.alpha * artistMotion.entranceOpacity
            transform: PlayerPart {
                id: artistMotion
                part: trackArtist
                unfold: Geometry.phase(root.headerUnfold, 0.08, 0.86)
                entranceSlot: Qt.point(-0.04, 0.43); entranceDelay: 0.40; entranceEnd: 0.94
                pivot: Qt.point(Math.min(trackArtist.width, trackArtist.contentWidth) / 2, trackArtist.height / 2)
                tuckDelay: 118; tuckDuration: 560; tuckEasing: Easing.InOutQuint
                returnDelay: 285; returnDuration: 626; spring: 1.08
                arc: 9; tilt: 10
            }
        }
        Row {
            id: playbackControls
            anchors.right: parent.right
            anchors.rightMargin: 26
            y: 14
            spacing: 6
            Repeater {
                model: ["previous", "pause", "next"]
                delegate: Item {
                    id: button
                    required property int index
                    required property string modelData
                    readonly property bool commandAvailable: !!root.player && (index === 0 ? root.player.canGoPrevious
                        : index === 1 ? root.player.canTogglePlaying : root.player.canGoNext)
                    width: root.nativeClock && root.width < 390 ? 30 : 42
                    height: 32
                    opacity: buttonMotion.alpha * buttonMotion.entranceOpacity
                        * (root.nativeClock && !commandAvailable ? 0.35 : 1)
                    transform: PlayerPart {
                        id: buttonMotion
                        part: button
                        unfold: Geometry.phase(root.headerUnfold, 0.11 + 0.045 * button.index, 0.86 + 0.045 * button.index)
                        entranceSlot: Qt.point(0.10 + 0.10 * button.index, 0.26 + 0.065 * button.index)
                        entranceDelay: 0.43 + 0.035 * button.index
                        entranceEnd: 0.91 + 0.035 * button.index
                        restingCenter: Qt.point(playbackControls.x + button.x + pivot.x,
                            playbackControls.y + button.y + pivot.y)
                        tuckDelay: button.index === 1 ? 180 : 34 + 20 * button.index
                        tuckDuration: 490 + 24 * button.index
                        returnDelay: 190 + 46 * button.index; returnDuration: 580 - 27 * button.index
                        spring: 1.2 + 0.13 * button.index
                        arc: -16 + 13 * button.index; tilt: 16 - 14 * button.index
                    }
                    Rectangle { anchors.fill: parent; radius: 12; color: root.colors.ink; opacity: area.containsMouse ? 0.08 : 0 }
                    Image {
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: button.index === 0 ? "assets/previous.svg" : "assets/next.svg"
                        visible: button.index !== 1
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1
                            colorizationColor: root.colors.ink
                        }
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 5
                        visible: button.index === 1 && root.playing
                        Repeater { model: 2; Rectangle { width: 4; height: 18; radius: 1; color: root.colors.ink } }
                    }
                    Text {
                        anchors.centerIn: parent; text: root.host.theme.iconFont ? "play_arrow" : "▶"
                        visible: button.index === 1 && !root.playing
                        color: root.colors.ink; font.family: root.host.theme.iconFont || root.host.theme.fontFamily; font.pixelSize: 28
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        enabled: button.commandAvailable
                        onClicked: {
                            if (!root.media) return
                            if (button.index === 0) root.media.previous()
                            else if (button.index === 1) root.media.togglePlaying()
                            else root.media.next()
                        }
                    }
                }
            }
        }
        Text {
            id: playedTime
            x: progress.x; y: 51
            visible: !root.nativeClock || root.layout > 0.5
            text: !root.nativeClock || root.player.positionSupported ? root.timeLabel(root.position) : "—:—"
            color: root.colors.secondary
            font.family: root.host.theme.fontFamily; font.pixelSize: 10
            opacity: playedTimeMotion.alpha * playedTimeMotion.entranceOpacity
            transform: PlayerPart {
                id: playedTimeMotion
                part: playedTime
                unfold: root.staggeredOpening ? Geometry.phase(root.wideReveal, 0.23, 0.92) : 1
                entranceSlot: Qt.point(-0.12, 0.64); entranceDelay: 0.50; entranceEnd: 0.97
                tuckDelay: 82; tuckDuration: 515
                returnDelay: 287; returnDuration: 581; spring: 0.92
                arc: -11; tilt: 13
            }
        }
        Text {
            id: totalTime
            x: progress.x + progress.width - width; y: 51
            visible: !root.nativeClock || root.layout > 0.5
            text: root.duration > 0 ? root.timeLabel(root.duration) : "—:—"
            color: root.colors.secondary
            font.family: root.host.theme.fontFamily; font.pixelSize: 10
            opacity: totalTimeMotion.alpha * totalTimeMotion.entranceOpacity
            transform: PlayerPart {
                id: totalTimeMotion
                part: totalTime
                unfold: root.staggeredOpening ? Geometry.phase(root.wideReveal, 0.27, 0.97) : 1
                entranceSlot: Qt.point(0.23, 0.68); entranceDelay: 0.54
                tuckDelay: 115; tuckDuration: 470
                returnDelay: 317; returnDuration: 570
                arc: 12; tilt: -16
            }
        }
    }
    Item {
        id: lyricSheet
        anchors.fill: parent
        opacity: sheetMotion.alpha * sheetMotion.entranceOpacity
        visible: opacity > 0.001
        transform: PlayerPart {
            id: sheetMotion
            part: lyricSheet
            unfold: root.staggeredOpening ? Geometry.phase(root.wideReveal, 0.23, 1) : 1
            entranceSlot: Qt.point(0, 0.77); entranceDelay: 0.51
            entranceScale: Qt.size(0.15, 0.22)
            pivot: Qt.point(lyricSheet.width / 2, lyricGlass.y + lyricGlass.height / 2)
            tuckedScale: Qt.size(0.087, 0.19)
            tuckDuration: 568
            returnDelay: 316; returnDuration: 680; spring: 1.3
            arc: 22; tilt: -9
        }
        Rectangle {
            x: 24; y: 90; width: Math.max(1, parent.width - 48); height: 1
            color: root.colors.divider; opacity: Math.min(1, root.layout)
        }
        Item {
            id: lyricGlass
            x: 24; y: 101; width: Math.max(1, parent.width - 48); height: 94 + 28 * root.voiceExpansion
            opacity: Math.min(1, root.layout)
            visible: opacity > 0.001
            ShaderEffectSource {
                id: glassCapture
                sourceItem: root.glassSource
                sourceRect: root.glassRect
                live: lyricGlass.visible
                visible: false
                smooth: true
            }
            ShaderEffect {
                id: glass
                anchors.fill: parent
                property var backdrop: glassCapture
                property vector2d resolution: Qt.vector2d(width, height)
                property color tintColor: root.colors.module
                property color highlightColor: root.colors.ink
                property vector4d materialStyle: root.materialStyle
                property real desktopLens: root.desktopLens ? 1 : 0
                fragmentShader: Qt.resolvedUrl("glass.frag.qsb")
                visible: !root.multiVoiceActive && !!root.glassSource && status !== ShaderEffect.Error
            }
            Rectangle {
                anchors.fill: parent; radius: 26
                color: Qt.rgba(root.colors.module.r, root.colors.module.g, root.colors.module.b, root.material.enabled ? 0.4 : 1)
                visible: !root.multiVoiceActive && !glass.visible
            }
        }
        LyricsReel {
            id: reel
            x: 68 - 44 * Math.min(1, root.layout)
            y: 15 + 86 * Math.min(1, root.layout)
            width: Math.max(1, root.width - 2 * x)
            height: 34 + (60 + 28 * root.voiceExpansion) * Math.min(1, root.layout)
            theme: root.host.theme
            lines: root.lines
            duration: root.duration
            rendering: root.available && !root.multiVoiceActive && !root.lyricsEnded
            estimateWordMotion: root.host.settings.estimateWordMotion === true
            time: rendering ? root.lyricTime : 0
            playing: rendering && root.playing
            pixelSize: (root.host.settings.lyricFontSize ?? 17) - 1 + Math.min(1, root.layout)
            ink: root.colors.ink
            accent: root.colors.accent
            upperContextOpacity: singleBacking.active ? .1 : 1
            opacity: root.available && !root.multiVoiceActive && !root.lyricsEnded ? root.lyricsOpacity : 0
        }
        BackingLayer {
            id: singleBacking
            x:reel.x;y:reel.y;width:reel.width;height:reel.height
            lines:root.allLines.filter(l=>l.role==="backing");time:visible?root.lyricTime:0
            opacity:root.available && !root.multiVoiceActive && !root.lyricsEnded ? root.lyricsOpacity : 0
            visible:opacity>.001
            fontFamily:root.host.theme.fontFamily;pixelSize:12
            accent:root.colors.accent
        }
        MultiVoiceLyrics {
            id: multiReel
            objectName: "multiVoiceLyrics"
            x: lyricGlass.x; y: lyricGlass.y
            width: lyricGlass.width; height: lyricGlass.height
            beatPulse: root.audioPulse; heartPulse: root.heartPulse
            resumeOrigin: Qt.point(root.fishPosition.x-x,root.fishPosition.y-y)
            allowFinale: !root.processingForLyrics && (!root.hasTimingDocument || !root.wordtimeResult.analysis || root.wordtimeResult.analysis.timelineComplete !== false)
            document: root.multiVoiceAvailable ? root.voiceDocument : null
            estimateWordMotion: root.host.settings.estimateWordMotion === true
            lyricTime: root.lyricTime
            duration: root.duration
            playing: root.playing
            theme: root.host.theme
            ink: root.colors.ink; accent: root.colors.accent; moduleColor: root.colors.module
            glassSource: root.glassSource
            desktopLens: root.desktopLens
            materialStyle: root.materialStyle
            glassRect: Qt.rect(root.glassRect.x + 8, root.glassRect.y + 8, width, height)
            opacity: root.multiVoiceActive && root.available ? root.lyricsOpacity : 0
            visible: opacity > 0.001
        }
        LyricsFinale {
            objectName: "lyricsFinale"
            x: reel.x; y: reel.y; width: reel.width; height: reel.height
            fontFamily: root.host.theme.fontFamily
            pixelSize: (root.host.settings.lyricFontSize ?? 17)-1+Math.min(1,root.layout)
            ink: root.colors.ink; accent: root.colors.accent
            phase: root.finaleState.phase
            opacity: root.lyricsEnded && !root.multiVoiceActive ? root.lyricsOpacity : 0
            visible: opacity>.001
            Behavior on opacity {NumberAnimation{duration:350}}
        }
        Item {
            x: reel.x; y: reel.y; width: reel.width; height: reel.height
            visible: !root.available && (!root.nativeClock || root.layout > 0.01)
            opacity: root.lyricsOpacity * (root.nativeClock ? Math.min(1, root.layout) : 1)
            Text {
                anchors.centerIn: parent
                text: root.emptyLabel; color: root.colors.secondary
                font.family: root.host.theme.fontFamily; font.pixelSize: 16
            }
        }
        Text {
            objectName: "lyricsAnalysisProgress"
            anchors.right: lyricGlass.right; anchors.bottom: lyricGlass.bottom
            anchors.rightMargin: 14; anchors.bottomMargin: 7
            text: root.processingForLyrics ? "Анализ · "+Math.round(root.wordtimeStore.generationProgress*100)+"%" : ""
            font.family: root.host.theme.fontFamily; font.pixelSize: 9
            color: root.colors.accent; opacity: .65*root.lyricsOpacity
            visible: root.wide && root.processingForLyrics
        }
        Item {
            id: recordingIndicator
            objectName: "lyricsRecordingIndicator"
            anchors.right: lyricGlass.right; anchors.bottom: lyricGlass.bottom
            anchors.rightMargin: 14; anchors.bottomMargin: 12
            width: 14; height: 14
            opacity: root.wide && !!root.wordtimeStore && !!root.player && !root.hasTimingDocument && !root.processingForLyrics ? Math.min(1, root.layout) * root.musicLayout : 0
            visible: opacity > 0.001
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.InOutCubic } }
            Accessible.name: "Обработать лирику"
            Controls.ToolTip.visible: analysisClick.containsMouse
            readonly property bool requested: !!root.wordtimeStore
                && !!root.wordtimeStore.analysisRequests[root.wordtimeStore.token(root.wordtimeTrack)]
            readonly property bool pulsing: requested && visible && root.playing && root.recordingForLyrics
            Controls.ToolTip.text: requested ? "Обработка запрошена · ожидаем полную запись"
                : root.recordingForLyrics ? "Запись идёт · нажмите для обработки после прослушивания" : "Обработать лирику"
            MouseArea {
                id: analysisClick
                objectName: "lyricsGenerationButton"
                // Only this input target sits above the native dock's hit area.
                // Keep the housing and icons in their original visual stacking.
                parent: root.host.dock.item.parent
                z: 3
                x: root.x + recordingIndicator.x + root.swipeX - 7
                y: root.y + recordingIndicator.y + root.swipeY - 7
                width: 28; height: 28
                enabled: root.enabled
                visible: root.visible && recordingIndicator.visible && root.host.working
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.wordtimeStore.requestAnalysis(root.wordtimeTrack,root.standardLyricsText,root.timingReference)
            }
            property real pulse: 1
            SequentialAnimation on pulse {
                running: recordingIndicator.pulsing
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.4; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.4; to: 1; duration: 800; easing.type: Easing.InOutSine }
            }
            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: "transparent"; border.width: 1; border.color: root.colors.accent
                opacity: recordingIndicator.pulsing ? 0.4 + recordingIndicator.pulse * 0.3 : 0.7
            }
            Rectangle {
                anchors.centerIn: parent; width: 5; height: 5; radius: 2.5
                color: root.colors.accent
                opacity: recordingIndicator.pulsing ? recordingIndicator.pulse : 0.8
            }
        }
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4; width: 32; height: 3; radius: 1.5
        color: root.colors.ink; opacity: swipeGrip.containsMouse || root.swipeDragging ? 0.45 : 0.17
        visible: root.swipeEnabled
    }
    MouseArea {
        id: swipeGrip
        objectName: "pausedPlayerGrip"
        x: 24; y: 0; width: Math.max(1, parent.width - 48); height: 14
        enabled: root.swipeEnabled
        hoverEnabled: true; preventStealing: true
        acceptedButtons: Qt.LeftButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: mouse => {
            const p = mapToItem(root.parent, mouse.x, mouse.y)
            mouse.accepted = root.beginSwipe(p.x, p.y)
        }
        onPositionChanged: mouse => {
            if (!root.swipeDragging) return
            const p = mapToItem(root.parent, mouse.x, mouse.y)
            root.moveSwipe(p.x, p.y)
        }
        onReleased: root.finishSwipe(true)
        onCanceled: root.finishSwipe(false)
    }

}
