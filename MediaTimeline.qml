import QtQuick
import Quickshell
import Quickshell.Io
import "PositionClock.js" as Clock

QtObject {
    id: root
    property var player: null
    property string key: ""
    property string playback: "absent"
    property bool active: true
    property list<string> command: []
    readonly property real rate: Number(player?.rate) > 0 ? Number(player.rate) : 1
    readonly property string busName: String(player?.dbusName || "")
    readonly property string identity: JSON.stringify(trackMetadata())
    readonly property bool bridgeWanted: active && !!player?.positionSupported && command.length > 0
        && /^org\.mpris\.MediaPlayer2\.[A-Za-z0-9_.-]+$/.test(busName) && identity !== "{}"
    readonly property bool current: active && player === selected && key === selectedKey
    readonly property bool known: current && model.known

    property var selected: null
    property string selectedKey: ""
    property string verifiedIdentity: ""
    property int serial: 0
    property double waitingSince: 0
    property bool bridgeAnswered: false
    property bool bridgeFailed: false
    property bool bridgeStopping: false
    property string bridgeError: ""
    property var model: Clock.start(0, 0, "absent", 1)
    property ElapsedTimer timer: ElapsedTimer {}

    function trackMetadata() {
        const props = player?.metadata || {}
        const identity = {}
        const id = props["mpris:trackid"]
        const path = typeof id === "string" ? id : id?.path
        if (path && path !== "/org/mpris/MediaPlayer2/TrackList/NoTrack")
            identity["mpris:trackid"] = path
        if (typeof props["xesam:url"] === "string" && props["xesam:url"])
            identity["xesam:url"] = props["xesam:url"]
        if (typeof props["xesam:title"] === "string" && props["xesam:title"])
            identity["xesam:title"] = props["xesam:title"]
        else if (player?.trackTitle)
            identity["xesam:title"] = player.trackTitle
        return identity
    }

    function sync() {
        const next = active ? player : null
        const now = timer.elapsedMs()
        const trackChanged = next !== selected || key !== selectedKey
        if (trackChanged) {
            selected = next
            selectedKey = key
            model = Clock.start(model.epoch + 1, now, next ? playback : "absent", rate)
            bridgeFailed = false
            bridgeError = ""
        } else {
            model = Clock.playbackChanged(model, next ? playback : "absent", rate, now)
        }
        if (trackChanged || identity !== verifiedIdentity) {
            ++serial
            verifiedIdentity = identity
            bridgeAnswered = false
            waitingSince = now
        }
        syncBridge()
        sampleNative()
    }
    function syncBridge() {
        if (bridgeWanted && current && !bridgeFailed) {
            if (!bridgeStopping) {
                bridge.running = true
                sendContext()
            }
        } else if (bridge.running) {
            bridgeStopping = bridge.processId > 0
            bridge.running = false
        }
    }
    function sendContext() {
        if (!current || !bridgeWanted || !bridge.running || bridge.processId <= 0) return
        bridge.write(JSON.stringify({player: busName, epoch: serial,
            metadata: JSON.parse(verifiedIdentity), playing: playback === "playing"}) + "\n")
    }
    function sampleNative() {
        if (!current || identity !== verifiedIdentity || !player?.positionSupported) return
        const now = timer.elapsedMs()
        if (bridgeWanted && !bridgeFailed && (bridgeAnswered || now - waitingSince < 1200)) return
        model = Clock.observe(model, player.position, now, "native", model.epoch)
    }
    function sampleBridge(line) {
        let reply
        try { reply = JSON.parse(line) } catch (_) { return }
        if (!current || identity !== verifiedIdentity || reply?.epoch !== serial) return
        const now = timer.elapsedMs()
        if (typeof reply.seek === "number") {
            bridgeAnswered = true
            model = Clock.seek(model, reply.seek, now, false)
        } else if (typeof reply.position === "number" && reply.position >= 0) {
            bridgeAnswered = true
            model = Clock.observe(model, reply.position, now, "mpris", model.epoch)
        }
    }
    function position() { return current ? Clock.estimate(model, timer.elapsedMs()) : 0 }
    function seek(seconds) {
        if (!current || identity !== verifiedIdentity || !player?.canSeek || !player.positionSupported
            || !Number.isFinite(seconds) || seconds < 0)
            return false
        model = Clock.seek(model, seconds, timer.elapsedMs(), true)
        player.position = seconds
        return true
    }
    function status() {
        return {epoch: model.epoch, position: position(), source: model.source, ready: known,
            playback: model.playback, rate: model.rate, ignoredZeros: model.ignoredZeros,
            seekRevision: model.seekRevision, bridge: bridge.running, error: bridgeError}
    }

    onActiveChanged: Qt.callLater(sync)
    onPlayerChanged: Qt.callLater(sync)
    onKeyChanged: Qt.callLater(sync)
    onPlaybackChanged: Qt.callLater(sync)
    onRateChanged: Qt.callLater(sync)
    onIdentityChanged: Qt.callLater(sync)
    onBridgeWantedChanged: Qt.callLater(sync)
    Component.onCompleted: Qt.callLater(sync)

    property Connections positionEvents: Connections {
        target: root.active ? root.player : null
        ignoreUnknownSignals: true
        function onPositionChanged() { root.sampleNative() }
        function onPostTrackChanged() { Qt.callLater(root.sync) }
    }
    property Timer fallbackPoll: Timer {
        interval: 250
        repeat: true
        running: root.current && !!root.player?.positionSupported && (!root.bridgeWanted || root.bridgeFailed
            || !root.bridgeAnswered) && (root.playback === "playing" || (!root.known && root.playback === "paused"))
        onTriggered: root.sampleNative()
    }
    property Process bridge: Process {
        command: root.command
        stdinEnabled: true
        onStarted: Qt.callLater(root.sendContext)
        stdout: SplitParser { onRead: line => root.sampleBridge(line) }
        stderr: SplitParser { onRead: line => { if (line.trim()) root.bridgeError = line.trim().slice(0, 300) } }
        onExited: code => {
            if (root.bridgeStopping) {
                root.bridgeStopping = false
                Qt.callLater(root.syncBridge)
            } else if (root.current && root.bridgeWanted) {
                root.bridgeFailed = true
                if (!root.bridgeError) root.bridgeError = "MPRIS завершился (код " + code + ")"
                root.sampleNative()
            }
        }
    }
}
