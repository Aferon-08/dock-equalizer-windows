import QtQuick

QtObject {
    id: preview

    enum Phase { Idle, Ringing, Connected }
    readonly property bool ringing: phase === DiscordCallPreview.Ringing
    readonly property bool connected: phase === DiscordCallPreview.Connected
    readonly property bool active: phase !== DiscordCallPreview.Idle
    readonly property string caller: "Мира"
    readonly property string room: "Ночной эфир"
    readonly property var participants: [
        { name: "Ты", status: preview.deafened ? "Без звука" : preview.muted ? "Микрофон выкл." : "В канале" },
        { name: preview.caller, status: "Говорит", speaking: true },
        { name: "Кирилл", status: "Микрофон выкл." },
        { name: "Саша", status: "Слушает" }
    ]

    property int phase: DiscordCallPreview.Idle
    property bool expanded: false
    property bool muted: false
    property bool deafened: false
    readonly property bool microphoneOff: muted || deafened
    property real connectedAt: 0
    property int seconds: 0
    readonly property string durationText: {
        const hours = Math.floor(seconds / 3600)
        const minutes = Math.floor(seconds / 60) % 60
        const remainder = seconds % 60
        return (hours ? hours + ":" : "") + String(minutes).padStart(2, "0")
            + ":" + String(remainder).padStart(2, "0")
    }

    function start() {
        if (!active)
            phase = DiscordCallPreview.Ringing
    }

    function accept() {
        if (!ringing)
            return
        expanded = true
        muted = false
        deafened = false
        seconds = 0
        connectedAt = Date.now()
        phase = DiscordCallPreview.Connected
    }

    function decline() {
        if (ringing)
            phase = DiscordCallPreview.Idle
    }

    function hangUp() {
        if (connected)
            phase = DiscordCallPreview.Idle
    }

    function toggleMute() {
        if (connected && !deafened)
            muted = !muted
    }

    function toggleDeafen() {
        if (connected)
            deafened = !deafened
    }

    function toggleExpanded() {
        if (connected)
            expanded = !expanded
    }

    property Timer ringTimeout: Timer {
        interval: 30000
        running: preview.ringing
        onTriggered: preview.decline()
    }

    property Timer clock: Timer {
        interval: 1000
        repeat: true
        running: preview.connected
        onTriggered: preview.seconds = Math.max(0, Math.floor((Date.now() - preview.connectedAt) / 1000))
    }
}
