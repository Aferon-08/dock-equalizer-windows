// Linux/SekaiPOP integration, injected by dock-adapter.qml only.
import QtQuick
import Quickshell.Io

Item {
    id: bridge
    required property var surface
    readonly property var lyrics: surface ? surface.lyrics : null
    readonly property bool sameTrack: !!surface && surface.sameTrack
    property string rawLyricsText: ""
    property string rawLyricsKey: ""
    onSurfaceChanged: rawLyricsRequest.restart()
    onSameTrackChanged: rawLyricsRequest.restart()
    Component.onCompleted: rawLyricsRequest.restart()

    Timer {
        id: rawLyricsRequest
        interval: 250
        onTriggered: {
            if (rawLyricsReader.running || !bridge.sameTrack || !bridge.lyrics || !bridge.lyrics.cacheScript
                || !/^[a-f0-9]{32}$/.test(bridge.lyrics.trackId || "")) return
            rawLyricsReader.requestKey = bridge.lyrics.trackId
            rawLyricsReader.command = ["bash", bridge.lyrics.cacheScript, "get", rawLyricsReader.requestKey]
            rawLyricsReader.running = true
        }
    }
    Process {
        id: rawLyricsReader
        property string requestKey: ""
        stdout: StdioCollector { onStreamFinished: {
            if (!bridge.sameTrack || !bridge.lyrics || bridge.lyrics.trackId !== rawLyricsReader.requestKey) return
            try {
                const cached = JSON.parse(text)
                if (typeof cached.synced === "string" && cached.synced.length <= 256 * 1024) {
                    bridge.rawLyricsKey = rawLyricsReader.requestKey
                    bridge.rawLyricsText = cached.synced
                }
            } catch (_) {}
        } }
        onExited: {
            if (bridge.sameTrack && bridge.lyrics && bridge.lyrics.trackId !== requestKey) rawLyricsRequest.restart()
        }
    }
    Connections {
        target: bridge.lyrics
        ignoreUnknownSignals: true
        function onLinesChanged() { rawLyricsRequest.restart() }
        function onTrackIdChanged() { rawLyricsRequest.restart() }
    }
    Connections {
        target: bridge.surface
        function onSignatureChanged() {
            bridge.rawLyricsText = ""
            bridge.rawLyricsKey = ""
            rawLyricsRequest.restart()
        }
    }
    IpcHandler {
        target: "docklyrics-" + (bridge.surface.host.dock.screenName || "preview")
        function status(): string { return bridge.surface.diagnostics() }
        function importWordtime(file: string): string {
            return bridge.surface.importWordtime(file) ? "Проверяем JSON для текущего трека." : "Нет выбранного трека или обработчик недоступен."
        }
        function removeWordtime(): string {
            return bridge.surface.removeWordtime() ? "Возвращаем обычную лирику." : "Нет выбранного трека или обработчик недоступен."
        }
        function wordtimeStatus(): string {
            const result = bridge.surface.wordtimeResult || { status: "loading" }
            return JSON.stringify({ status: result.status, message: result.message || "",
                words: result.wordCount || 0, review: result.reviewCount || 0,
                voices: (result.voices || []).map(v => ({id: v.id, label: v.label})),
                voiceAnalysis: result.multivoice || null, analysisStages: result.analysis || null,
                busy: !!bridge.surface.wordtimeStore && bridge.surface.wordtimeStore.busy,
                engineReady: !!bridge.surface.wordtimeStore && bridge.surface.wordtimeStore.engineReady,
                generating: !!bridge.surface.wordtimeStore && bridge.surface.wordtimeStore.generationBusy,
                recordingReady: !!bridge.surface.wordtimeStore && !!bridge.surface.wordtimeStore.recordingFor(bridge.surface.wordtimeTrack),
                analysisRequested: !!bridge.surface.wordtimeStore && !!bridge.surface.wordtimeStore.analysisRequests[bridge.surface.wordtimeStore.token(bridge.surface.wordtimeTrack)],
                capturing: !!bridge.surface.wordtimeStore && bridge.surface.wordtimeStore.captureBusy,
                capturePhase: bridge.surface.wordtimeStore ? bridge.surface.wordtimeStore.capturePhase : "",
                captureProgress: bridge.surface.wordtimeStore ? bridge.surface.wordtimeStore.captureProgress : 0,
                compute: bridge.surface.wordtimeStore ? bridge.surface.wordtimeStore.generationCompute : null,
                detail: bridge.surface.wordtimeStore ? bridge.surface.wordtimeStore.generationDetail : null,
                phase: bridge.surface.wordtimeStore ? bridge.surface.wordtimeStore.generationPhase : "",
                progress: bridge.surface.wordtimeStore ? bridge.surface.wordtimeStore.generationProgress : 0,
                lastAction: bridge.surface.wordtimeStore ? bridge.surface.wordtimeStore.lastAction : null })
        }
        function generateWordtime(audio: string): string {
            return bridge.surface.wordtimeStore && bridge.surface.wordtimeStore.startGeneration(bridge.surface.wordtimeTrack, audio, bridge.surface.standardLyricsText, false)
                ? "Рассчитываем тайминги в фоне." : "Нет текста песни, обработчик не готов или уже занят."
        }
        function cancelWordtime(): void { if (bridge.surface.wordtimeStore) bridge.surface.wordtimeStore.cancelGeneration() }
    }
}
