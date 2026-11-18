import QtQuick
import Quickshell.Io
import "BeatTracker.js" as BeatTracker
import "SpectrumEnvelope.js" as Envelope
import "DurationCache.js" as Durations
import "HostContract.js" as HostContract

QtObject {
    id: root
    required property var host
    property bool settingsPanelOpen: false
    readonly property var integration: HostContract.resolve(host)
    readonly property bool nativeIntegration: integration.state !== "unsupported"
    function extensionEnabled(slot) {
        if (integration.supported[slot] !== true) return false
        if (slot === "wallpaper") return wallpaperWanted && (wallpaperSeed !== "" || wallpaperError === "")
        if (slot === "dock") return host.settings.enabled !== false
        return true
    }
    property Process missingApiNotice:Process {
        command:["notify-send","Dock Equalizer","Нужен SekaiPOP с native extensions API. Файлы оболочки автоматически не изменяются. См. docs/NATIVE-INTEGRATION.md."]
        running:!root.nativeIntegration
    }
    // A single session seed for all monitors; changing palette never regenerates geometry.
    property var widgetRects: ({})
    function setWidgetRect(id,rect) {
        if(JSON.stringify(widgetRects[id])===JSON.stringify(rect || undefined))return
        const next=Object.assign({},widgetRects)
        if(rect)next[id]=rect;else delete next[id]
        widgetRects=next
    }
    property string wallpaperSeed: ""
    property string wallpaperError: ""
    property string wallpaperCandidate: ""
    property string wallpaperDiagnostic: ""
    property int wallpaperFailures: 0
    property bool wallpaperRefreshing: false
    readonly property bool wallpaperNewRequested: host.settings.wallpaperRegenerate === true
    readonly property bool wallpaperWanted: integration.supported.wallpaper && host.settings.proceduralWallpaper === true
    function startWallpaperSeed() {
        if (!integration.supported.wallpaper || (!wallpaperWanted && !wallpaperNewRequested) || wallpaperSeedJob.running || wallpaperDeadline.running
            || (wallpaperSeed && !wallpaperNewRequested)) return
        wallpaperRetry.stop()
        wallpaperCandidate = ""
        wallpaperDiagnostic = ""
        wallpaperRefreshing = wallpaperNewRequested
        wallpaperSeedJob.command = ["python3", host.path("wallpaper-seed.py")].concat(wallpaperRefreshing ? ["--new"] : [])
        wallpaperSeedJob.running = true
        wallpaperDeadline.restart()
    }
    function finishWallpaperSeed(code) {
        wallpaperDeadline.stop()
        const refreshed = wallpaperRefreshing
        wallpaperRefreshing = false
        if (code === 0 && /^[a-f0-9]{24}$/.test(wallpaperCandidate)) {
            wallpaperSeed = wallpaperCandidate
            wallpaperError = ""
            wallpaperFailures = 0
        } else {
            // Never remove an already visible scene on a failed refresh.
            wallpaperError = wallpaperDiagnostic || "Не удалось получить seed обоев"
            wallpaperFailures = Math.min(wallpaperFailures + 1, 8)
            if (!wallpaperSeed && wallpaperWanted) wallpaperRetry.restart()
        }
        if (refreshed && wallpaperNewRequested) host.setSetting("wallpaperRegenerate", false)
        else if (wallpaperNewRequested) Qt.callLater(startWallpaperSeed)
    }
    onWallpaperNewRequestedChanged: if (wallpaperNewRequested) startWallpaperSeed()
    onWallpaperWantedChanged: {
        if (wallpaperWanted) Qt.callLater(startWallpaperSeed)
        else wallpaperRetry.stop()
    }
    Component.onCompleted: startWallpaperSeed()
    property Timer wallpaperRetry: Timer {
        interval: Math.min(30000, 2000 * Math.pow(2, Math.max(0, root.wallpaperFailures - 1)))
        onTriggered: root.startWallpaperSeed()
    }
    property Timer wallpaperDeadline: Timer {
        interval: 8000
        onTriggered: {
            if (root.wallpaperSeedJob.processId > 0) root.wallpaperSeedJob.signal(9)
            else { root.wallpaperSeedJob.running = false; root.finishWallpaperSeed(-1) }
        }
    }
    property Process wallpaperSeedJob: Process {
        stdout: StdioCollector { onStreamFinished: {
            try { root.wallpaperCandidate = JSON.parse(text).seed || "" }
            catch (_) {}
        } }
        stderr: SplitParser { onRead: data => {
            if (data.trim()) root.wallpaperDiagnostic = data.trim().slice(0, 300)
        } }
        onExited: code => root.finishWallpaperSeed(code)
    }
    property WordtimeStore wordtimes: WordtimeStore { host: root.host }
    property MediaContext mediaContext: MediaContext {
        timelineDemand: root.host.working && root.extensionEnabled("dock")
        timelineCommand: ["setpriv", "--pdeathsig", "TERM", "python3", root.host.path("media-position.py")]
    }
    property MusicPalette musicPalette: MusicPalette {
        host: root.host
        supported: root.integration.paletteLease
        context: root.mediaContext.snapshot
    }

    property var beatState: BeatTracker.reset()
    property var rhythm: BeatTracker.reading(beatState)
    readonly property real beatPulse: rhythm.beat
    readonly property real beatBpm: rhythm.bpm
    readonly property real beatConfidence: rhythm.confidence
    function resetRhythm() {
        beatState = BeatTracker.reset()
        rhythm = BeatTracker.reading(beatState)
    }
    property var bands: []
    property var envelope: Envelope.reset()
    property bool audible: false
    function resetAudio() {
        envelope = Envelope.reset()
        bands = []
        audible = false
        resetRhythm()
    }
    readonly property string error: tap.error
    property bool profileFrames:false
    property var frameSamples:({})
    function collectFrame(screen,seconds){if(!profileFrames)return;const a=frameSamples[screen] || (frameSamples[screen]=[]);if(a.length<4000)a.push(seconds*1000)}
    property int frames: 0
    property var surfaces: ({})
    function setSurface(screen, state) {
        const next = Object.assign({}, surfaces)
        if (state) next[screen] = state; else delete next[screen]
        surfaces = next
    }
    // Share metadata lookups across monitors; positive and negative TTLs
    // are separate. A failed refresh keeps the last valid duration.
    property var durationEntries: ({})
    readonly property var durationCache: {
        const cache = {}
        for (const id of Object.keys(durationEntries)) cache[id] = durationEntries[id].seconds
        return cache
    }
    property var durationQueue: []
    property string durationJob: ""
    property real durationSeconds: 0
    property string durationError: ""
    function requestYoutubeDuration(id, force) {
        if (!Durations.eligible(durationEntries, id, Date.now(), force)
            || durationJob === id || durationQueue.includes(id) || durationQueue.length >= 16) return false
        durationQueue = durationQueue.concat([id])
        pumpDuration()
        return true
    }
    function pumpDuration() {
        if (durationJob !== "" || durationQueue.length === 0) return
        durationJob = durationQueue[0]
        durationQueue = durationQueue.slice(1)
        durationSeconds = 0
        durationLookup.command = ["python3", root.host.path("youtube-duration.py"), durationJob]
        durationLookup.running = true
        durationDeadline.restart()
    }
    function finishDuration() {
        if (!durationJob) return
        durationDeadline.stop()
        durationEntries = Durations.remember(durationEntries, durationJob, durationSeconds, Date.now())
        durationError = durationEntries[durationJob].failed ? "Длительность YouTube пока недоступна." : ""
        durationJob = ""
        Qt.callLater(root.pumpDuration)
    }
    property Timer durationDeadline: Timer {
        interval: 18000
        onTriggered: {
            // Terminate stalled helpers before pumping the next lookup.
            if (root.durationLookup.processId > 0) root.durationLookup.signal(9)
            else { root.durationLookup.running = false; root.finishDuration() }
        }
    }
    property Process durationLookup: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text)
                    if (result.id === root.durationJob) root.durationSeconds = result.seconds
                } catch (_) {}
            }
        }
        onExited: root.finishDuration()
    }
    // MPRIS announces state changes. Waiting for music needs no audio tap.
    readonly property var playerModel: mediaContext.playerModel
    readonly property bool playing: mediaContext.playing
    property Connections contextChanges: Connections {
        target: root.mediaContext
        function onTrackIdChanged() { root.resetAudio() }
    }
    readonly property bool wanted: host.working && playing && (extensionEnabled("dock")
        || (extensionEnabled("wallpaper") && host.settings.wallpaperPet !== false))
    readonly property bool running: tap.running
    readonly property list<string> spectrumCommand: ["setpriv", "--pdeathsig", "TERM", "nice", "-n", "5",
        "python3", host.path("audio-output.py"), host.path("cava.conf")]

    property SpectrumCapture tap: SpectrumCapture {
        wanted: root.wanted
        command: root.spectrumCommand
        onCleared: root.resetAudio()
        onSpectrum: next => {
            const stamp = root.tap.lastPacketAt
            const frame = Envelope.update(root.envelope, next, stamp)
            root.audible = frame.audible
            root.rhythm = BeatTracker.update(root.beatState, next, stamp, frame.audible)
            ++root.frames
            if (frame.bands.length !== root.bands.length || frame.bands.some((v, i) => v !== root.bands[i]))
                root.bands = frame.bands
        }
    }
    property AudioSelfTest audioSelfTest: AudioSelfTest {
        command: Array.from(root.spectrumCommand).concat("--self-test")
    }

    function audioStatus() {
        return {
            state: tap.state, wanted: wanted, ready: tap.ready, failures: tap.failures,
            signal: !wanted ? "released" : !tap.ready ? "unknown" : audible ? "audible" : "silence",
            mode: mediaContext.visualizationMode, playerId: mediaContext.playerId, trackId: mediaContext.trackId,
            processId: tap.pid || null, output: tap.output, bands: bands.length,
            gain: tap.ready ? Math.round(envelope.gain * 100) / 100 : null,
            rhythm: rhythm,
            lastPacketAt: tap.lastPacketAt || null,
            packetAgeMs: tap.lastPacketAt ? Math.max(0, Date.now() - tap.lastPacketAt) : null,
            retryInMs: tap.retryIn, reason: tap.error || tap.output?.reason || "",
            testRunning: audioSelfTest.running, testResult: audioSelfTest.result
        }
    }

    function moduleStatus() {
        return {
            host: { state: integration.state, api: integration.api, capabilities: integration.supported,
                missing: integration.missing, paletteLease: integration.paletteLease,
                demand: host.working, surfaces: Object.keys(surfaces).length },
            media: Object.assign({},mediaContext.snapshot,{hostShared:integration.sharedMedia,
                integration:integration.sharedMedia ? "ready" : "degraded",
                clock: mediaContext.timeline.status(),
                reason:integration.sharedMedia ? "" : "Для общего выбора native-контролов обновите host API (native-media-v1)."}),
            audio: audioStatus(),
            palette: { state: musicPalette.state, active: musicPalette.active,
                playerId: musicPalette.sourcePlayerId, trackId: musicPalette.sourceTrackId,
                running: musicPalette.worker.running, message: musicPalette.message, reason: musicPalette.error },
            duration: { state: durationJob ? "running" : durationError ? "degraded" : "idle",
                queued: durationQueue.length, reason: durationError },
            wallpaper: { state: !integration.supported.wallpaper ? "unsupported"
                : !wallpaperWanted ? "disabled"
                : wallpaperRetry.running ? "recovering"
                : wallpaperSeedJob.running ? (wallpaperError ? "recovering" : "starting")
                : wallpaperError ? "degraded" : wallpaperSeed ? "running" : "idle",
                reason: wallpaperError, retries: wallpaperFailures },
            analysis: { state: wordtimes.generationBusy ? "running"
                : wordtimes.engineReady ? "ready" : "unavailable", phase: wordtimes.generationPhase }
        }
    }

    property IpcHandler ipc: IpcHandler {
        target: "dockequalizer"
        function profile(on:bool):string {
            if(on){root.frameSamples={};root.profileFrames=true;return "started"}
            root.profileFrames=false
            const result={}
            for(const key of Object.keys(root.frameSamples)){const a=root.frameSamples[key].slice(10).sort((x,y)=>x-y);if(a.length)result[key]={frames:a.length,median:a[Math.floor(a.length*.5)],p95:a[Math.floor(a.length*.95)],worst:a[a.length-1]}}
            return JSON.stringify(result)
        }
        function settingsPanel(show: bool): string {
            if (show && !root.extensionEnabled("settings")) return "Нужна возможность native-settings-v1."
            if (typeof root.host.setSettingsOpen === "function") root.host.setSettingsOpen(show)
            else root.settingsPanelOpen = show
            return ""
        }
        function settingsPanelStatus(): string {return JSON.stringify({open:root.host.settingsOpen || root.settingsPanelOpen,count:Object.keys(root.host.settings).length})}
        function audioStatus(): string { return JSON.stringify(root.audioStatus()) }
        function testAudio(): bool { return root.audioSelfTest.start() }
        function status(): string {
            return JSON.stringify({ nativeIntegration:root.nativeIntegration, playing: root.playing, working: root.wanted, running: root.running,
                players: root.playerModel.values.length, surfaces: root.surfaces, modules: root.moduleStatus(),
                frames: root.frames, beatPulse: root.beatPulse, bpm: root.beatBpm, beatConfidence: root.beatConfidence, audible: root.audible, error: root.error,
                wordtimeBusy: root.wordtimes.busy, wordtimeCached: Object.keys(root.wordtimes.cache).length,
                wordtimeEngineReady: root.wordtimes.engineReady, wordtimeGenerating: root.wordtimes.generationBusy,
                wordtimeCapturing: root.wordtimes.captureBusy, wordtimeCapturePhase: root.wordtimes.capturePhase,
                bands: root.bands.length, peak: Math.max(0, ...root.bands) })
        }
    }
}
