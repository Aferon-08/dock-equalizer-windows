import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root
    settings.watchFiles: false

    MediaContext {
        id: media
        timelineCommand: ["python3", Quickshell.env("TEST_PLUGIN_DIR") + "/media-position.py"]
    }

    IpcHandler {
        target: "timeline-test"
        function status(): string {
            return JSON.stringify(Object.assign({title: media.title, identity: media.timeline.identity,
                player: media.playerId, bridgeWanted: media.timeline.bridgeWanted},
                media.timeline.status()))
        }
        function seek(seconds: real): bool { return media.timeline.seek(seconds) }
        function quit(): void { Qt.quit() }
    }
}
