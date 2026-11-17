import QtQuick
import QtQml.Models
import Quickshell.Services.Mpris

// One selection shared by every monitor, the audio gate and the cover worker.
QtObject {
    id: root
    property var playerModel: Mpris.players
    readonly property var players: playerModel.values
    property string lastStartedId: ""
    property int epoch: 0
    function idFor(p) {return p ? String(p.dbusName || "") : ""}
    function pickPlayer() {
        const list=players.filter(p=>!!p).sort((a,b)=>idFor(a)<idFor(b)?-1:idFor(a)>idFor(b)?1:0)
        return list.find(p=>idFor(p)===lastStartedId && (p.playbackState===MprisPlaybackState.Playing || p.trackTitle))
            || list.find(p=>p.playbackState===MprisPlaybackState.Playing)
            || list.find(p=>!!p.trackTitle) || null
    }
    readonly property var player: pickPlayer()
    readonly property string playerId: idFor(player)
    readonly property bool present: !!player
    readonly property bool playing: !!player && player.playbackState===MprisPlaybackState.Playing
    readonly property string playback: !player ? "absent" : playing ? "playing"
        : player.playbackState===MprisPlaybackState.Paused ? "paused" : "stopped"
    readonly property string title: player ? player.trackTitle || player.identity || "" : ""
    readonly property string artist: player ? player.trackArtist || "" : ""
    readonly property string url: player ? String((player.metadata || {})["xesam:url"] || "") : ""
    readonly property string artUrl: {
        if(!player)return ""
        if(player.trackArtUrl)return player.trackArtUrl
        if(!/^https?:\/\/(?:www\.|m\.|music\.)?(?:youtube\.com|youtu\.be)\//i.test(url))return ""
        const match=url.match(/(?:[?&]v=|youtu\.be\/|\/shorts\/)([A-Za-z0-9_-]{11})(?:[^A-Za-z0-9_-]|$)/)
        return match ? "https://i.ytimg.com/vi/"+match[1]+"/mqdefault.jpg" : ""
    }
    readonly property string trackId: !player ? "" : JSON.stringify([playerId,
        player.uniqueId ?? (String((player.metadata || {})["mpris:trackid"] || "") || [url,artist,title])])
    onTrackIdChanged: ++epoch
    readonly property string visualizationMode: "system-output"
    readonly property var snapshot: ({playerId,trackId,epoch,state:playback,playing,title,artist,url,artUrl,mode:visualizationMode})
    readonly property bool volumeAvailable: !!player && !!player.volumeSupported
    function togglePlaying() {if(player && player.canTogglePlaying)player.togglePlaying()}
    function next() {if(player && player.canGoNext)player.next()}
    function previous() {if(player && player.canGoPrevious)player.previous()}
    function changeVolume(direction) {
        if(player && player.volumeSupported && player.canControl)
            player.volume=Math.max(0,Math.min(1,player.volume+direction*.05))
    }
    property Instantiator observers: Instantiator {
        model: root.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPlaybackStateChanged() {
                if(modelData && modelData.playbackState===MprisPlaybackState.Playing)root.lastStartedId=root.idFor(modelData)
            }
        }
    }
}
