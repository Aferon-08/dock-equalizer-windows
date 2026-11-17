import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "." as Plugin
ShellRoot {
 id:root;settings.watchFiles:false
 property bool paletteTest:Quickshell.env("TEST_PALETTE")==="1"
 property int phase:0
 property int rememberedEpoch:0
 QtObject {id:players;property var values:[a,b]}
 QtObject {
  id:a
  property string dbusName:"org.mpris.MediaPlayer2.alpha"
  property string identity:"Alpha"
  property string trackTitle:"Song A"
  property string trackArtist:"Singer A"
  property string trackArtUrl:Quickshell.env("TEST_COVER_A") || "file:///a.png"
  property int uniqueId:1
  property int playbackState:MprisPlaybackState.Paused
  property var metadata:({"xesam:url":"spotify:track:a"})
  property bool lengthSupported:true
  property real length:120
  property bool positionSupported:false
  property bool canSeek:false
  property bool canControl:true
  property bool volumeSupported:true
  property bool canTogglePlaying:true
  property bool canGoNext:true
  property bool canGoPrevious:true
  property real volume:.5
  property int toggles:0
  function togglePlaying(){++toggles;playbackState=playbackState===MprisPlaybackState.Playing ? MprisPlaybackState.Paused : MprisPlaybackState.Playing}
  function next(){}
  function previous(){}
 }
 QtObject {
  id:b
  property string dbusName:"org.mpris.MediaPlayer2.browser"
  property string identity:"Browser"
  property string trackTitle:"Song B"
  property string trackArtist:"Singer B"
  property string trackArtUrl:Quickshell.env("TEST_COVER_B") || ""
  property int uniqueId:1
  property bool lengthSupported:true
  property real length:120
  property bool positionSupported:false
  property bool canSeek:false
  property bool canControl:false
  property bool canTogglePlaying:false
  property bool canGoNext:false
  property bool canGoPrevious:false
  property bool volumeSupported:false
  property real volume:1
  property int playbackState:MprisPlaybackState.Paused
  property var metadata:({"xesam:url":"https://www.youtube.com/watch?v=abc123def45"})
 }
 QtObject {
  id:host
  property var capabilities:root.paletteTest ? ["native-dock-v1","native-media-v1","transient-palette-v1"] : ["native-dock-v1","native-media-v1"]
  property int apiVersion:1
  property bool working:true
  property var service:pluginService
  property var settings:({enabled:true,width:200,height:38,gap:12,style:"wave",sensitivity:1.25,lyricsWidth:560,expandLyrics:true,lyrics:true,autoSpotify:false,proceduralWallpaper:false,musicPalette:root.paletteTest})
  property var theme:({fontFamily:"sans-serif",iconFont:"sans-serif"})
  property QtObject dock:QtObject {
   property var item:dockItem
   property string screenName:"fixture"
   property bool vertical:false
   property bool capsule:true
   property string look:"capsule"
   property real radius:30
   property real shadow:4
   property bool asleep:false
   property bool hovered:false
   property bool editing:false
   property bool desktopEmpty:true
   property real baseWidth:432
   property real baseCapHeight:69
   property real stageWidth:1100
   property var mediaSource:pluginService.mediaContext
   property var lyrics:null
   property var palette:({fill:Qt.color("#101b18"),rim:Qt.color("#284a3d"),shadow:Qt.color("#060d0a"),ink:Qt.color("#e8f4ee"),accent:Qt.color("#96dcc0"),border:3,ringWidth:3,ring:Qt.color("#101b18")})
  }
  function path(rel){return Quickshell.env("MEDIA_FIXTURE")+"/"+rel}
 }
 Plugin.Service {id:pluginService;host:host}
 Window {
  width:1100;height:360;visible:true
  Item {id:dockItem;x:334;y:55;width:432+wings.lyricsWidthExtra;height:73+wings.lyricsHeightExtra
   property real capWidth:width
   property real capHeight:height
  }
  Plugin.DockWings {id:wings;anchors.fill:parent;host:host}
 }
 Component.onCompleted:{pluginService.tap.command=["python3",host.path("fake-spectrum.py")];pluginService.mediaContext.playerModel=players}
 function check(ok,msg){if(!ok){console.error("FAIL "+msg+" "+JSON.stringify(pluginService.mediaContext.snapshot));Qt.quit();return false}return true}
 Timer {interval:80;repeat:true;running:true;onTriggered:{
  const c=pluginService.mediaContext
  const palette=pluginService.musicPalette
  if(root.phase===0 && c.player===a){b.playbackState=MprisPlaybackState.Playing;root.phase=1;return}
  if(root.phase===1 && c.player===b && pluginService.wanted && pluginService.tap.ready && pluginService.frames>=3 && (!root.paletteTest || (palette.contextMatches && palette.active))){
   if(!root.check((c.artUrl===Quickshell.env("TEST_COVER_B")) && pluginService.moduleStatus().audio.playerId===b.dbusName,"one browser identity and artwork"))return
   if(!root.check(c.present && c.playback==="playing" && wings.visible && wings.expanded && wings.suppressMediaKey && !pluginService.audible && pluginService.moduleStatus().audio.signal==="silence","digital silence keeps the selected player and audio stream alive"))return
   a.playbackState=MprisPlaybackState.Playing;root.phase=2;return
  }
  if(root.phase===2 && c.player===a && (!root.paletteTest || (palette.contextMatches && palette.active))){
   a.playbackState=MprisPlaybackState.Paused;root.phase=3;return
  }
  if(root.phase===3 && !pluginService.wanted && !pluginService.running && (!root.paletteTest || (palette.contextMatches && !palette.active))){
   if(!root.check(c.player===a && c.playback==="paused" && wings.suppressMediaKey && b.playbackState===MprisPlaybackState.Playing,"pause must retain selected player and stop audio despite background browser"))return
   if(!root.check(pluginService.moduleStatus().audio.signal==="released","pause releases the audio stream"))return
   a.playbackState=MprisPlaybackState.Stopped;root.phase=31;return
  }
  if(root.phase===31){
   if(!root.check(c.playback==="stopped" && pluginService.moduleStatus().media.state==="stopped" && !pluginService.wanted,"stopped is distinct from silence and pause"))return
   root.rememberedEpoch=c.epoch;a.trackArtUrl="";root.phase=4;return
  }
  if(root.phase===4){
   if(!root.check(c.epoch===root.rememberedEpoch,"artwork churn must not change track epoch"))return
   ++a.uniqueId;root.phase=5;return
  }
  if(root.phase===5 && c.epoch>root.rememberedEpoch){
   c.togglePlaying();c.changeVolume(1)
   if(!root.check(a.toggles===1 && Math.abs(a.volume-.55)<.001,"controls target selected player"))return
   a.canControl=false;c.changeVolume(1)
   if(!root.check(Math.abs(a.volume-.55)<.001,"unsupported controls ignored"))return
   players.values=[b];root.phase=6;return
  }
  if(root.phase===6 && c.player===b && pluginService.wanted){players.values=[];root.phase=7;return}
  if(root.phase===7 && c.playback==="absent" && !pluginService.running && (!root.paletteTest || (palette.contextMatches && !palette.active))){
   if(!root.check(!pluginService.wanted && pluginService.moduleStatus().media.playerId==="" && c.visualizationMode==="system-output","player removal clears the shared context"))return
   console.log("PASS shared selection, two playing players, pause audio release, artwork churn, epoch, controls and player disappearance")
   if(root.paletteTest)console.log("PASS controlled QML palette worker agrees with selected player and pause/disappearance")
   Qt.quit()
  }
 }}
 Timer {interval:10000;running:true;onTriggered:{console.error("FAIL media timeout phase="+root.phase);Qt.quit()}}
}
