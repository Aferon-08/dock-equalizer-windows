import QtQuick
import Quickshell.Io

// Demand survives a broken audio output. A failed child only delays the next
// attempt; it never changes the demand or any other module's state.
QtObject {
    id: root
    required property bool wanted
    required property list<string> command
    readonly property bool running: tap.running
    readonly property string state: !wanted ? "idle" : retry.running ? "recovering"
        : ready ? "running" : "starting"
    readonly property int retryIn: retry.running ? retry.interval : 0
    property bool ready: false
    property string error: ""
    property int failures: 0
    property string diagnostic: ""
    signal spectrum(var values)
    signal cleared()

    function syncDemand() {
        if (!wanted) {
            retry.stop()
            startup.stop()
            stopTap()
            ready = false
            failures = 0
            error = ""
            cleared()
        } else if (!tap.running && !retry.running) {
            diagnostic = ""
            tap.running = true
            startup.restart()
        }
    }
    function fail(reason) {
        startup.stop()
        ready = false
        cleared()
        if (!wanted || retry.running) return
        error = reason
        failures = Math.min(failures + 1, 16)
        retry.interval = Math.min(30000, 1000 * Math.pow(2, failures - 1))
        retry.start()
        stopTap()
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
    property Process tap: Process {
        command: root.command
        stdout: SplitParser {
            onRead: data => {
                if (!root.wanted || root.retry.running) return
                const fields = data.trim().split(";")
                if (fields[fields.length - 1] === "") fields.pop()
                if (fields.length !== 64) return
                const next = []
                for (const field of fields) {
                    const value = Number(field)
                    if (!field.trim() || !Number.isFinite(value)) return
                    next.push(Math.max(0, Math.min(1000, value)))
                }
                root.startup.stop()
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
