import QtQuick
import Quickshell
import Quickshell.Io
import ".." as Plugin

ShellRoot {
    id: root
    settings.watchFiles: false
    property bool wanted: true
    property int samples: 0
    property int worstSeries: 0
    property int phase: 0
    Plugin.SpectrumCapture {
        id: tap
        wanted: root.wanted
        command: ["python3", Quickshell.env("DOCK_TEST_AUDIO_HELPER"), Quickshell.env("DOCK_TEST_AUDIO_COUNTER")]
        onFailuresChanged: root.worstSeries = Math.max(root.worstSeries, failures)
        onSpectrum: values => {
            if (values.length !== 64 || Math.abs(values[0] - 100) >= 0.1) throw new Error("bad frame")
            ++root.samples
        }
    }
    Timer {
        interval: 30
        repeat: true
        running: true
        onTriggered: {
            if (root.phase === 0 && root.samples >= 1 && root.worstSeries >= 3 && tap.ready && tap.failures === 0) {
                root.phase = 1
                console.log("PASS recovered after three exits without changing demand")
            }
            if (root.phase === 1 && tap.failures === 1 && tap.state === "recovering"
                    && tap.lastPacketAt === 0 && tap.error.includes("перестала передавать")) {
                root.phase = 2
                root.wanted = false
                pauseCheck.start()
            }
        }
    }
    Timer {
        id: pauseCheck
        interval: 1300
        onTriggered: {
            if (!tap.running && !tap.ready && tap.state === "idle" && tap.failures === 0) {
                console.log("PASS valid frames reset failures; pause cancels retry")
                Qt.quit()
            }
        }
    }
    Timer {
        interval: 18000
        running: true
        onTriggered: {
            console.error("FAIL audio recovery", root.phase, tap.state, tap.failures, root.samples, tap.error)
            Qt.quit()
        }
    }
}
