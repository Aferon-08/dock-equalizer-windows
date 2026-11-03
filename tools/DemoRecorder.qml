import QtQuick
import Quickshell

Item {
    id: root
    required property Item scene
    property bool pending: false
    property bool finishing: false
    property int frame: 0
    readonly property string output: Quickshell.env("DEMO_OUT")

    function fail(reason) {
        console.error("DEMO_FAIL " + reason)
        Qt.quit()
    }
    function record(phase) {
        if (pending || finishing) return
        pending = true
        watchdog.restart()
        const id = frame
        const filename = String(id).padStart(5, "0") + ".png"
        const accepted = scene.grabToImage(result => {
            watchdog.stop()
            if (!result.saveToFile(output + "/" + filename)) {
                fail("cannot save " + filename)
                return
            }
            console.log("DEMO_FRAME " + id + " " + phase)
            ++frame
            pending = false
            if (finishing) finish()
        }, Qt.size(scene.width, scene.height))
        if (!accepted) fail("grab request rejected")
    }
    function finish() {
        finishing = true
        if (pending) return
        console.log("DEMO_DONE " + frame)
        Qt.quit()
    }
    Timer { id: watchdog; interval: 3000; onTriggered: root.fail("grab timed out") }
}
