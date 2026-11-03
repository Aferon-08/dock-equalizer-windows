pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
Item {
 id:root
 property string screenName:""
 property rect viewport:Qt.rect(0,0,width,height)
 property bool active:false
 property bool intersectOnly:false
 property int refreshInterval:83
 property string diagnosticTarget:""
 readonly property var monitor:Hyprland.monitors.values.find(m=>m.name===screenName) || null
 readonly property var windows:{
  if(!monitor || !active)return []
  const ws=monitor.activeWorkspace?.id
  return Hyprland.toplevels.values.filter(t=>{
   const i=t.lastIpcObject || {}
   const x=(i.at?.[0] || 0)-(monitor.lastIpcObject?.x || 0)
   const y=(i.at?.[1] || 0)-(monitor.lastIpcObject?.y || 0)
   const intersects=!intersectOnly || (x+(i.size?.[0] || 0)>viewport.x && x<viewport.x+viewport.width
       && y+(i.size?.[1] || 0)>viewport.y && y<viewport.y+viewport.height)
   return intersects && !!t.wayland && i.mapped!==false && i.hidden!==true && i.visible!==false && !t.wayland.minimized
     && i.monitor===monitor.id && (i.workspace?.id===ws || i.pinned===true)
  }).slice().sort((a,b)=>(b.lastIpcObject?.focusHistoryID ?? 100)-(a.lastIpcObject?.focusHistoryID ?? 100))
 }
 function status() {
  const result={state:active ? "idle" : "disabled", windows:previews.count,
    ready:0, waiting:0, recovering:0, attempts:0}
  for(let i=0;i<previews.count;++i) {
   const preview=previews.itemAt(i)
   if(!preview) continue
   if(preview.hasContent) ++result.ready
   else if(preview.retrying) ++result.recovering
   else ++result.waiting
   result.attempts+=preview.attempts
  }
  if(result.recovering) result.state=result.ready ? "degraded" : "recovering"
  else if(result.waiting) result.state="starting"
  else if(result.ready) result.state="running"
  return result
 }
 IpcHandler {
  target:root.diagnosticTarget
  enabled:root.diagnosticTarget!==""
  function status():string {return JSON.stringify(root.status())}
 }
 Repeater {
  id:previews
  model:root.windows
  ScreencopyView {
   id:preview;required property var modelData
   readonly property var info:modelData.lastIpcObject || {}
   readonly property var sourceWindow:modelData.wayland || null
   property bool connected:true
   property bool hadContent:false
   property bool retrying:false
   property int failures:0
   property int attempts:1
   x:(info.at?.[0] || 0)-(root.monitor?.lastIpcObject?.x || 0)-root.viewport.x
   y:(info.at?.[1] || 0)-(root.monitor?.lastIpcObject?.y || 0)-root.viewport.y
   width:info.size?.[0] || 1;height:info.size?.[1] || 1
   captureSource:root.active && connected ? sourceWindow : null
   live:false;paintCursor:false
   visible:hasContent

   // Assigning a source already requests the first frame. hasContent is
   // observable on this Quickshell build; there is no context-ready property.
   function reconnect() {
    if(!root.active || !sourceWindow || retrying || hasContent) return
    hadContent=false
    retrying=true
    connected=false
    failures=Math.min(8,failures+1)
    retry.interval=Math.min(30000,1000*Math.pow(2,failures-1))
    retry.start()
   }
   onHasContentChanged: {
    if(hasContent) {hadContent=true;failures=0}
    else if(hadContent) Qt.callLater(reconnect)
   }
   onStopped:Qt.callLater(reconnect)
   Timer {
    interval:1600
    running:root.active && !!preview.captureSource && !preview.hasContent && !preview.retrying
    onTriggered:preview.reconnect()
   }
   Timer {
    id:retry
    onTriggered:{
     preview.retrying=false
     ++preview.attempts
     preview.connected=true
    }
   }
   Timer {
    interval:root.refreshInterval
    repeat:true
    running:root.active && !!preview.captureSource && preview.hasContent
    onTriggered:if(preview.hasContent && preview.captureSource)preview.captureFrame()
   }
  }
 }
}
