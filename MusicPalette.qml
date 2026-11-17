import QtQuick
import Quickshell.Io

// One background session for the plugin, independent of monitor/surface count.
QtObject {
    id: root
    required property var host
    property bool supported: false
    readonly property bool enabled: host.settings.musicPalette === true
    readonly property int stopDelay: host.settings.musicPaletteStopDelay ?? 600
    readonly property bool wanted: enabled && supported
    property bool active: false
    property string message: "Ожидание музыки — исходная палитра"
    property string error: ""
    property int failures: 0
    readonly property string state: !enabled ? "disabled" : !supported ? "unsupported"
        : retry.running ? "recovering" : error ? "degraded" : active ? "active" : worker.running ? "waiting" : "starting"

    function start() {
        if (!wanted || worker.running) return
        error = ""
        worker.command = ["python3", host.path("music-palette.py"), "--stop-delay", String(stopDelay)]
        worker.running = true
    }
    function reconcile() {
        retry.stop()
        if (wanted) start()
        else { worker.running = false; active = false; error = "" }
    }
    onWantedChanged: Qt.callLater(reconcile)
    onStopDelayChanged: {
        // A new worker clears its old lease before reapplying the current track.
        retry.stop()
        if (worker.running) worker.running = false
        else Qt.callLater(start)
    }
    Component.onCompleted: Qt.callLater(reconcile)
    property Timer retry: Timer {
        interval: Math.min(15000, 1000 * Math.pow(2, Math.min(root.failures, 4)))
        onTriggered: root.start()
    }
    property Process worker: Process {
        stdout: SplitParser { onRead: data => {
            try {
                const result = JSON.parse(data)
                root.active = result.active === true
                root.message = result.message || ""
                root.error = ""
                root.failures = 0
            } catch (_) {}
        } }
        stderr: SplitParser { onRead: data => {
            if (data.trim()) root.error = data.trim().slice(0, 500)
        } }
        onExited: code => {
            root.active = false
            if (root.wanted) {
                if (code !== 0) root.failures++
                root.retry.restart()
            }
        }
    }
}
