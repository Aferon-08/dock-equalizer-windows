import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    settings.watchFiles: false
    property bool demand: true
    property var bands: []
    property int frames: 0
    property int clears: 0
    readonly property list<string> command: ["setpriv", "--pdeathsig", "TERM", "python3",
        Quickshell.env("TEST_PLUGIN_DIR") + "/audio-output.py",
        Quickshell.env("TEST_PLUGIN_DIR") + "/cava.conf"]

    SpectrumCapture {
        id: capture
        wanted: root.demand
        command: root.command
        onCleared: { root.bands = []; ++root.clears }
        onSpectrum: frame => { root.bands = frame; ++root.frames }
    }
    AudioSelfTest {
        id: selfTest
        command: Array.from(root.command).concat("--self-test")
    }

    IpcHandler {
        target: "audio-output-test"
        function status(): string {
            const left = root.bands.slice(0, 32)
            const peak = Math.max(0, ...left)
            return JSON.stringify({state: capture.state, output: capture.output, error: capture.error,
                frames: root.frames, clears: root.clears, peak, bin: left.indexOf(peak),
                lastPacketAt: capture.lastPacketAt, testResult: selfTest.result,
                pid: capture.running ? capture.pid : null})
        }
        function checkAudio(): bool { return selfTest.start() }
        function pause(): void { root.demand = false }
        function quit(): void { Qt.quit() }
    }
}
