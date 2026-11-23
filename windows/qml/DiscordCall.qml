import QtQuick

QtObject {
    id: call
    required property var live
    required property DiscordCallPreview testCall

    // The last source supplies the labels while the dock animates out.
    property bool lastWasLive: false
    Component.onCompleted: lastWasLive = live.connected
    readonly property bool usesLive: live.connected || (!testCall.active && lastWasLive)
    readonly property var source: usesLive ? live : testCall
    readonly property int phase: live.connected ? DiscordCallPreview.Connected : testCall.phase
    readonly property bool ringing: phase === DiscordCallPreview.Ringing
    readonly property bool connected: phase === DiscordCallPreview.Connected
    readonly property bool active: phase !== DiscordCallPreview.Idle
    readonly property string caller: usesLive ? "" : testCall.caller
    readonly property string room: source.room
    readonly property string context: usesLive ? live.context : "Discord · Тестовый звонок"
    readonly property var participantModel: source.participantModel
    readonly property int participantCount: source.participantCount
    readonly property var participants: source.participants
    readonly property string voiceStatus: source.voiceStatus
    readonly property string durationText: source.durationText
    readonly property bool muted: source.muted
    readonly property bool deafened: source.deafened
    readonly property bool microphoneOff: muted || deafened
    readonly property bool canChangeVoice: connected && (!usesLive || live.canChangeVoice)
    readonly property bool canHangUp: connected && (!usesLive || live.canHangUp)

    property Connections liveState: Connections {
        target: call.live
        function onChanged() {
            if (call.live.connected) {
                call.lastWasLive = true
                call.testCall.phase = DiscordCallPreview.Idle
            }
        }
    }
    property Connections testState: Connections {
        target: call.testCall
        function onActiveChanged() {
            if (call.testCall.active && !call.live.connected)
                call.lastWasLive = false
        }
    }

    function accept() { if (ringing) testCall.accept() }
    function decline() { if (ringing) testCall.decline() }
    function toggleMute() { if (canChangeVoice) source.toggleMute() }
    function toggleDeafen() { if (canChangeVoice) source.toggleDeafen() }
    function hangUp() { if (canHangUp) source.hangUp() }
}
