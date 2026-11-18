import QtQuick
import Quickshell.Io

// Demand survives a broken audio output. A failed child only delays the next
// attempt; it never changes the demand or any other module's state.
QtObject {
    id: root
    required property bool wanted
    required property list<string> command
    readonly property bool running: tap.running
    readonly property int pid: tap.processId ?? 0
    readonly property string state: !wanted ? "idle" : retry.running ? "recovering"
        : output?.state === "waiting-output" ? "waiting-output" : ready ? "running" : "starting"
    readonly property int retryIn: retry.running ? retry.interval : 0
    property bool ready: false
    property string error: ""
    property int failures: 0
    property string diagnostic: ""
    property var output: null
    property real lastPacketAt: 0
    signal spectrum(var values)
    signal cleared()

    function clearSpectrum() {
        ready = false
        lastPacketAt = 0
        cleared()
    }

    function syncDemand() {
        if (!wanted) {
            retry.stop()
            startup.stop()
            stopTap()
            output = null
            failures = 0
            error = ""
            clearSpectrum()
        } else if (!tap.running && !retry.running) {
            diagnostic = ""
            output = null
            tap.running = true
            startup.restart()
        }
    }
    function fail(reason) {
        startup.stop()
        output = null
        clearSpectrum()
        if (!wanted || retry.running) return
        error = reason
        failures = Math.min(failures + 1, 16)
        retry.interval = Math.min(30000, 1000 * Math.pow(2, failures - 1))
        retry.start()
        stopTap()
    }
    function receiveOutput(line) {
        let event
        try { event = JSON.parse(line) } catch (_) { return }
        if (event?.type !== "output") return
        if (!["binding", "capturing", "waiting-output"].includes(event.state)) return
        output = event
        if (event.state === "capturing" || event.state === "binding") startup.restart()
        else startup.stop()
        if (event.state !== "capturing") clearSpectrum()
    }
    function stopTap() {
        tap.running = false
        if (tap.running) terminateDeadline.restart()
    }
    onWantedChanged: syncDemand()
    Component.onCompleted: syncDemand()

    property Timer retry: Timer { onTriggered: root.syncDemand() }
    property Timer terminateDeadline: Timer {
        interval: 500
        onTriggered: if (root.tap.running) root.tap.signal(9)
    }
    property Timer startup: Timer {
        interval: 6000
        onTriggered: root.fail(root.diagnostic || "CAVA не передала спектр после запуска.")
    }
    property Timer stalled: Timer {
        interval: 1000
        repeat: true
        running: root.wanted && root.ready
        onTriggered: {
            if (Date.now() - root.lastPacketAt >= 4500)
                root.fail("CAVA перестала передавать спектр.")
        }
    }
    property Process tap: Process {
        command: root.command
        stdout: SplitParser {
            onRead: data => {
                if (!root.wanted || root.retry.running) return
                const line = data.trim()
                if (line.startsWith("{")) { root.receiveOutput(line); return }
                if (root.output && root.output.state !== "capturing") return
                const fields = line.split(";")
                if (fields[fields.length - 1] === "") fields.pop()
                if (fields.length !== 64) return
                const next = []
                for (const field of fields) {
                    const value = Number(field)
                    if (!field.trim() || !Number.isFinite(value)) return
                    next.push(Math.max(0, Math.min(1000, value)))
                }
                root.startup.stop()
                root.lastPacketAt = Date.now()
                root.ready = true
                root.failures = 0
                root.error = ""
                root.spectrum(next)
            }
        }
        // Bound diagnostic storage even if a driver writes to stderr repeatedly.
        stderr: SplitParser {
            onRead: data => { if (data.trim()) root.diagnostic = data.trim().slice(0, 500) }
        }
        onExited: code => {
            root.terminateDeadline.stop()
            if (root.wanted) root.fail(root.diagnostic || "CAVA остановлена (код " + code + ").")
        }
    }
}
