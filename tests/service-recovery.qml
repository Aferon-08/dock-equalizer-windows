import QtQuick
import Quickshell
import ".." as Plugin

ShellRoot {
    id: root
    settings.watchFiles: false
    property int phase: 0
    property string seed: "feed00112233445566778899"
    property string video: "abc123def45"

    Plugin.Service { id: pluginService; host: host }
    QtObject {
        id: host
        property var capabilities: ["native-dock-v1", "native-wallpaper-v1", "native-settings-v1"]
        property bool working: true
        property var settings: ({enabled:true, proceduralWallpaper:true, lyrics:true, autoSpotify:false})
        property var service: pluginService
        property var theme: ({fontFamily:"sans-serif", iconFont:"sans-serif"})
        property QtObject dock: QtObject {
            property var item: dockItem
            property string screenName: "fixture"
            property bool vertical: false
            property bool hovered: false
            property bool editing: false
            property bool asleep: false
            property bool desktopEmpty: true
            property bool bare: false
            property var mediaSource: media
            property var lyrics: provider
            property var palette: ({fill:Qt.color("#202b28"), ink:Qt.color("white"), accent:Qt.color("#96dcc0")})
        }
        function path(name) { return Quickshell.env("DOCK_FIXTURE_DIR") + "/" + name }
        function setSetting(key, value) { settings = Object.assign({}, settings, {[key]: value}) }
    }
    QtObject {
        id: media
        property string title: "Fixture"
        property string artist: "Demo"
        property string artUrl: ""
        property bool playing: false
        property QtObject player: QtObject {
            property bool lengthSupported: false
            property bool canSeek: false
            property bool volumeSupported: false
            property bool canControl: false
            property bool canTogglePlaying: false
            property bool canGoPrevious: false
            property bool canGoNext: false
            property bool positionSupported: true
            property real position: 4
            property var metadata: ({"xesam:url": "https://www.youtube.com/watch?v=abc123def45"})
        }
    }
    QtObject {
        id: provider
        property string status: "loading"
        property var lastArgs: ["Demo","Fixture"]
        property var lines: []
    }
    Window {
        width: 640; height: 400; visible: true
        Item { id: dockItem; width: 440; height: 75 }
        Plugin.DockLyrics { id: lyrics; host: host }
    }

    function check(ok, message) {
        if (ok) return true
        console.error("FAIL " + message)
        Qt.quit()
        return false
    }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            const entry = pluginService.durationEntries[root.video]
            if (root.phase === 0 && entry && entry.failed && pluginService.wallpaperError) {
                if (!root.check(pluginService.moduleStatus().host.state === "ready" &&
                    pluginService.moduleStatus().wallpaper.state === "recovering", "failed wallpaper has its own status")) return
                if (!root.check(lyrics.emptyState === "loading", "loading lyric state")) return
                provider.status = "none"
                if (!root.check(lyrics.emptyState === "missing", "a missing text is not instrumental")) return
                provider.status = "offline"
                if (!root.check(lyrics.emptyState === "offline", "network failure is distinct")) return
                provider.status = "instrumental"
                if (!root.check(lyrics.emptyState === "instrumental", "explicit instrumental flag")) return
                provider.status = "none"
                const key = pluginService.wordtimes.token(lyrics.wordtimeTrack)
                pluginService.wordtimes.analysisRequests = {[key]: {}}
                if (!root.check(lyrics.emptyState === "pending", "pending manual analysis is distinct")) return
                pluginService.wordtimes.analysisRequests = {}
                root.phase = 1
            }
            if (root.phase === 1 && pluginService.wallpaperSeed === root.seed) {
                host.setSetting("wallpaperRegenerate", true)
                root.phase = 2
            }
            if (root.phase === 2 && pluginService.wallpaperError && !pluginService.wallpaperNewRequested) {
                if (!root.check(pluginService.extensionEnabled("wallpaper") && pluginService.wallpaperSeed === root.seed,
                    "failed refresh must preserve the previously rendered seed")) return
                root.phase = 3
            }
            if (root.phase === 3 && entry && !entry.failed && lyrics.duration === 231) {
                const store = pluginService.wordtimes, key = store.token(lyrics.wordtimeTrack)
                store.cache = {[key]: {status:"ready", lines:[], analysis:{revision:4, state:"partial", voices:"estimated", textScanComplete:false}}}
                if (!root.check(lyrics.analysisUpdateReason === "partial" && !store.generationBusy,
                    "partial result offers a retry without auto-start")) return
                store.requestAnalysis(lyrics.wordtimeTrack, "[00:03]Test line", null)
                if (!root.check(store.generationBusy, "explicit request starts generation")) return
                root.phase = 4
            }
            if (root.phase === 4 && !pluginService.wordtimes.generationBusy) {
                if (!root.check(lyrics.hasTimingDocument && pluginService.wordtimes.lastAction.state === "failed",
                    "failed analysis attempt preserves the previous result")) return
                console.log("PASS duration retried after TTL; wallpaper recovered and kept its seed; lyric states distinct")
                console.log("PASS partial analysis stays manual and a failed attempt retains timings")
                Qt.quit()
            }
        }
    }
    Timer {
        interval: 26000; running: true
        onTriggered: { console.error("FAIL service timed out", root.phase, lyrics.duration, JSON.stringify(pluginService.moduleStatus())); Qt.quit() }
    }
}
