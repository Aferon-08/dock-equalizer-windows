import QtQuick
import Quickshell
import "." as Plugin
ShellRoot {
 id: root
 settings.watchFiles:false
 property int phase:0
 property double started:Date.now()
 property int oldEpoch:0
 property string scenario:Quickshell.env("RECOVERY_SCENARIO")
 QtObject {
  id:model
  property var plugin:({settings:{},settingsInfo:{},groups:[]})
  property var settings:({})
  property QtObject service:QtObject {property bool settingsPanelOpen:false}
  function resetAll(){}
 }
 Window {
  width:1000;height:800;visible:true
  Item {id:phone;anchors.fill:parent;property bool captureReady:false}
  Plugin.SettingsPanel {
   id:panel;anchors.fill:parent;pst:model;phone:root.scenario==="missing"?null:phone
   theme:({surface:Qt.color("#152322"),ink:Qt.color("#ffffff"),accentCyan:Qt.color("#90ddcd")})
  }
 }
 function child(item,name){if(item.objectName===name)return item;for(const c of (item.children || [])){const found=child(c,name);if(found)return found}return null}
 function check(ok,message){if(!ok){console.error("FAIL "+message);Qt.quit();return false}return true}
 Timer {
  interval:40;repeat:true;running:true
  onTriggered:{
   if(root.phase===0){model.service.settingsPanelOpen=true;root.started=Date.now();root.phase=1;return}
   if(root.phase===1 && panel.mode==="open"){
    if(!root.check(panel.fallbackReason!=="", "fallback reason"))return
    if(!root.check(Date.now()-root.started<2700,"bounded opening"))return
    if(root.scenario==="timeout" && !root.check(panel.fallbackReason==="snapshot-timeout","watchdog reason"))return
    if(!root.check(root.child(panel,"settings-card").enabled && root.child(panel,"settings-card").opacity===1,"usable settings card"))return
    root.oldEpoch=panel.captureEpoch
    model.service.settingsPanelOpen=false
    root.phase=2;return
   }
   if(root.phase===2 && panel.mode==="closed"){
    model.service.settingsPanelOpen=true;root.phase=3;return
   }
   if(root.phase===3 && panel.showing){
    panel.deliverPhone(root.oldEpoch,{url:"file:///stale-phone.png"})
    if(!root.check(panel.phoneGrab===null,"late callback ignored after reopen"))return
    model.service.settingsPanelOpen=false;root.started=Date.now();root.phase=4;return
   }
   if(root.phase===4 && Date.now()-root.started>250){
    if(!root.check(panel.mode==="closed","close during capture cancels pending timers"))return
    console.log("PASS settings recovery "+root.scenario+" backend="+panel.graphicsApi)
    Qt.quit()
   }
  }
 }
 Timer {interval:6000;running:true;onTriggered:{console.error("FAIL timeout "+panel.mode);Qt.quit()}}
}
