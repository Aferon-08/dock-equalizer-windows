import QtQuick

QtObject {
    id: preview

    enum Phase { Idle, Ringing, Connected }
    readonly property bool ringing: phase === DiscordCallPreview.Ringing
    readonly property bool connected: phase === DiscordCallPreview.Connected
    readonly property bool active: phase !== DiscordCallPreview.Idle
    readonly property string caller: "Мира"
    readonly property string room: "Ночной эфир"
    readonly property var sampleParticipants: [
        { name: "Алекс", portrait: 0, speaking: false, micOff: false },
        { name: preview.caller, portrait: 1, speaking: true, micOff: false },
        { name: "Кирилл", portrait: 2, speaking: false, micOff: true },
        { name: "Саша", portrait: 3, speaking: false, micOff: false },
        { name: "Надя", portrait: 4, speaking: true, micOff: false },
        { name: "Саша", portrait: 5, speaking: false, micOff: false },
        { name: "Александра Воскресенская", portrait: 6, speaking: false, micOff: false },
        { name: "Женя", portrait: 0, speaking: false, micOff: false }
    ]
    readonly property var participants: {
        const rows = []
        const count = Math.max(1, Math.min(sampleParticipants.length, participantCount))
        for (let index = 0; index < count; ++index) {
            const sample = sampleParticipants[index]
            const localUser = index === 0
            const micOff = localUser ? microphoneOff : sample.micOff
            const avatar = sample.portrait
                ? String(Qt.resolvedUrl("assets/discord-avatar-" + sample.portrait + ".jpg")) : ""
            rows.push({
                participantId: "test-" + (index + 1), name: sample.name, avatar: avatar, avatarUrl: avatar,
                localUser: localUser, speaking: sample.speaking, micOff: micOff,
                status: localUser && deafened ? "Без звука" : micOff ? "Микрофон выкл."
                    : sample.speaking ? "Говорит" : "В канале"
            })
        }
        return rows
    }
    readonly property ListModel participantModel: ListModel {}
    property int participantCount: 4
    property string voiceStatus: "connected"
    onParticipantsChanged: syncParticipants()
    Component.onCompleted: syncParticipants()

    property int phase: DiscordCallPreview.Idle
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

    function syncParticipants() {
        const rows = participants
        const model = participantModel
        if (!model)
            return
        if (model.count > rows.length)
            model.remove(rows.length, model.count - rows.length)
        for (let index = model.count; index < rows.length; ++index)
            model.append(rows[index])
        model.setProperty(0, "micOff", rows[0].micOff)
        model.setProperty(0, "status", rows[0].status)
    }

    function start() {
        if (!active)
            phase = DiscordCallPreview.Ringing
    }

    function accept() {
        if (!ringing)
            return
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
