pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "SettingsMotion.js" as Motion
Item {
 id:root
 required property var pst
 required property var theme
 property var extensionHost:null
 property Item phone:null
 property rect phoneRect:Qt.rect((width-1120)/2,(height-600)/2,1120,600)
 property rect backgroundRect:Qt.rect(0,0,width,height)
 property string screenName:"demo"
 property bool opened:pst && pst.service && pst.service.settingsPanelOpen
 property string mode:"closed"
 property real phase:0
 readonly property bool ownsPhone:mode==="opening" || mode==="open" || mode==="closing"
 readonly property bool showing:mode!=="closed"
 readonly property bool closing:mode==="closing"
 readonly property var pose:Motion.frame(closing,mode==="open"?1:phase,phoneRect,Qt.rect((width-card.width)/2,(height-card.height)/2,card.width,card.height))
 visible:showing
 focus:opened
 readonly property var prefs:pst ? pst.settings : ({})
 readonly property var manifest:pst ? pst.plugin : ({settings:{},settingsInfo:{}})
 readonly property color ink:theme.ink || "#e4f4f2"
 readonly property color accent:theme.accentCyan || "#9cddd2"
 readonly property color surface:theme.surface || "#152322"
 property string query:""
 property int captureEpoch:0
 property var phoneGrab:null
 property string fallbackReason:""
 readonly property int graphicsApi:GraphicsInfo.api
 readonly property bool shaderBackend:GraphicsInfo.api!==GraphicsInfo.Software && GraphicsInfo.api!==GraphicsInfo.Null
 function close(){if(extensionHost)extensionHost.close();else pst.service.settingsPanelOpen=false}
 function endCapture(){
  ++captureEpoch
  captureRetry.stop()
  captureDeadline.stop()
 }
 function showPlain(reason){
  if(!opened){endCapture();mode="closed";return}
  endCapture()
  morph.stop()
  fallbackReason=reason
  phoneGrab=null
  phase=1
  mode="open"
  forceActiveFocus()
 }
 function beginWhenReady(){
  if(mode!=="capturing" || !opened)return
  if(phoneImage.status===Image.Error){showPlain("snapshot-invalid");return}
  if(!phoneGrab || phoneImage.status!==Image.Ready)return
  endCapture()
  phase=0
  mode="opening"
  forceActiveFocus()
  morph.start()
 }
 function openPanel(){
  if(!opened || mode!=="closed")return
  endCapture()
  fallbackReason=""
  phoneGrab=null
  if(!shaderBackend || morphSurface.status===ShaderEffect.Error){showPlain("renderer");return}
  mode="capturing"
  captureDeadline.start()
  capturePhone()
 }
 function capturePhone(){
  if(mode!=="capturing" || !opened)return
  if(phone && phone.captureReady===false){captureRetry.restart();return}
  if(!phone || phone.width<=0 || phone.height<=0){showPlain("phone-unavailable");return}
  const epoch=captureEpoch
  const ok=phone.grabToImage(result=>deliverPhone(epoch,result),Qt.size(Math.round(width),Math.round(height)))
  if(!ok)showPlain("snapshot-rejected")
 }
 function deliverPhone(epoch,result){
  if(mode!=="capturing" || !opened || epoch!==captureEpoch)return
  phoneGrab=result
  beginWhenReady()
 }
 Timer {id:captureRetry;interval:50;onTriggered:root.capturePhone()}
 Timer {id:captureDeadline;interval:1600;onTriggered:root.showPlain("snapshot-timeout")}
 function startClosing(){
  if(fallbackReason){mode="closed";return}
  phase=0;mode="closing";morph.start()
 }
 Keys.onEscapePressed:event=>{close();event.accepted=true}
 onOpenedChanged:{
  if(opened && mode==="closed")Qt.callLater(openPanel)
  else if(!opened && mode==="capturing"){endCapture();mode="closed"}
  else if(!opened && mode==="open")startClosing()
 }
 Component.onCompleted:if(opened)Qt.callLater(openPanel)
 NumberAnimation {id:morph;target:root;property:"phase";from:0;to:1;duration:Math.max(2600,(root.prefs.settingsDuration ?? 1100)*3)*(root.closing?.9:1)
  onFinished:{if(root.mode==="opening"){root.mode="open";if(!root.opened)root.startClosing()}else{root.mode="closed";if(root.opened)Qt.callLater(root.openPanel)}}
 }
 // ShaderEffectSource owns the normal handoff; a plain panel covers the phone.
 ShaderEffectSource {sourceItem:root.phone;hideSource:root.ownsPhone && root.shaderBackend;visible:false;live:false}
 Rectangle {anchors.fill:parent;color:root.surface;opacity:.82;visible:root.ownsPhone && !!root.fallbackReason}
 Image {id:phoneImage;visible:false;source:root.phoneGrab?root.phoneGrab.url:"";onStatusChanged:Qt.callLater(root.beginWhenReady)}
 SettingsUnderlay {id:underlay;anchors.fill:parent;screenName:root.screenName;viewport:root.backgroundRect;active:root.ownsPhone && !root.fallbackReason && root.shaderBackend}
 Connections {
  target:underlay
  function onHealthChanged(){
   if(underlay.health.unavailable>0 && root.showing && !root.fallbackReason)root.showPlain("background-capture")
  }
 }
 ShaderEffectSource {id:backdrop;anchors.fill:parent;sourceItem:underlay;hideSource:true;live:underlay.active;visible:false}
 MouseArea {anchors.fill:parent;enabled:root.ownsPhone;onClicked:root.close()}
 ShaderEffect {
  id:morphSurface
  anchors.fill:parent
  visible:root.ownsPhone && !root.fallbackReason && root.shaderBackend
  onStatusChanged:if(status===ShaderEffect.Error && root.showing){
   if(root.opened)root.showPlain("shader-error")
   else {morph.stop();root.mode="closed"}
  }
  property var source:phoneImage
  property var background:backdrop
  property vector2d resolution:Qt.vector2d(width,height)
  property vector4d phoneBox:Qt.vector4d(root.phoneRect.x,root.phoneRect.y,root.phoneRect.width,root.phoneRect.height)
  property vector4d shapeBox:Qt.vector4d(root.pose.x,root.pose.y,root.pose.w,root.pose.h)
  property vector4d backdropBox:Qt.vector4d(0,0,width,height)
  property real radius:root.pose.r
  property real water:root.pose.water
  property real photo:root.pose.photo
  property real clock:root.phase
  property real hasBackground:1
  property color tint:root.surface
  property color accent:root.accent
  fragmentShader:Qt.resolvedUrl("settings-morph.frag.qsb")
 }
 IpcHandler {
  target:"docksettings-"+root.screenName
  function status():string{return JSON.stringify({mode:root.mode,phase:root.phase,phoneReady:phoneImage.status===Image.Ready,fallback:root.fallbackReason,graphicsApi:root.graphicsApi,backgroundWindows:underlay.windows.length,capture:underlay.status(),pose:root.pose})}
  function snapshot(path:string):void{root.grabToImage(r=>r.saveToFile(path))}
 }
 Item {
  id:card
  objectName:"settings-card"
  width:Math.min(root.width-40,root.prefs.settingsWidth ?? 1100)
  height:Math.min(root.height-48,root.prefs.settingsHeight ?? 900)
  anchors.centerIn:parent
  opacity:root.ownsPhone?root.pose.content:0
  transform: [Translate {x:root.pose.x-root.width/2;y:root.pose.y-root.height/2},Scale {origin.x:card.width/2;origin.y:card.height/2;xScale:root.pose.w/card.width;yScale:root.pose.h/card.height}]
  enabled:root.opened && root.mode==="open"
  Rectangle {
   anchors.fill:parent
   visible:root.fallbackReason!==""
   radius:28
   color:root.surface
   border.color:Qt.tint(root.surface,Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.45))
  }
  MouseArea {anchors.fill:parent}
  ColumnLayout {
   anchors.fill:parent;anchors.margins:28;spacing:14
   RowLayout {
    Layout.fillWidth:true
    ColumnLayout {Layout.fillWidth:true
     Label {text:"Dock Equalizer";color:root.ink;font.pixelSize:26;font.bold:true}
     Label {text:Object.keys(root.manifest.settings).length+" настроек · сохраняются сразу";color:root.accent}
    }
    Button {font.pixelSize:14;leftPadding:16;rightPadding:16;topPadding:12;bottomPadding:12;palette.button:Qt.darker(root.surface,1.15);palette.buttonText:root.ink;text:"Сбросить всё";onClicked:resetDialog.open()}
    Button {font.pixelSize:14;leftPadding:16;rightPadding:16;topPadding:12;bottomPadding:12;palette.button:Qt.darker(root.surface,1.15);palette.buttonText:root.ink;text:"Вернуться  ×";onClicked:root.close()}
   }
   TextField {font.pixelSize:15;implicitHeight:46;Layout.fillWidth:true;background:Rectangle{radius:14;color:Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.08);border.color:Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.2)} placeholderText:"Поиск настроек…";onTextChanged:root.query=text.toLowerCase();color:root.ink}
   ScrollView {
    id:scroll;Layout.fillWidth:true;Layout.fillHeight:true;clip:true
    ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
    contentWidth:availableWidth
    Flickable {id:flick;contentWidth:width;contentHeight:sections.height;boundsBehavior:Flickable.DragOverBounds;flickDeceleration:1400;maximumFlickVelocity:2200
     WheelHandler {onWheel:event=>{flick.cancelFlick();wheelAnim.stop();wheelAnim.from=flick.contentY;wheelAnim.to=Math.max(0,Math.min(flick.contentHeight-flick.height,flick.contentY-event.angleDelta.y*(root.prefs.settingsScroll ?? .8)));wheelAnim.start();event.accepted=true}}
     NumberAnimation {id:wheelAnim;target:flick;property:"contentY";duration:200;easing.type:Easing.OutCubic}
     Column {
      id:sections;width:flick.width;spacing:14
      Repeater {model:root.manifest.groups || []
       Column {
        id:group;required property string modelData;width:sections.width;spacing:8
        readonly property var keys:Object.keys(root.manifest.settings).filter(k=>(root.manifest.settingsInfo[k]?.group || "")===modelData)
        readonly property var matching:keys.filter(k=>root.query==="" || (root.manifest.settingsInfo[k]?.label+" "+k+" "+modelData).toLowerCase().includes(root.query))
        visible:matching.length>0
        Label {text:group.modelData;color:root.accent;font.pixelSize:18;font.bold:true;topPadding:14}
        Repeater {model:group.keys
         SettingsControl {required property string modelData;width:group.width;pst:root.pst;settingKey:modelData;ink:root.ink;accent:root.accent;visible:group.matching.includes(modelData)}
        }
       }
      }
     }
    }
   }
  }
 }
 Dialog {id:resetDialog;anchors.centerIn:parent;title:"Сбросить все настройки?";modal:true;standardButtons:Dialog.Ok|Dialog.Cancel
  Label {text:"Все параметры вернутся к значениям по умолчанию.\nЗаписи музыки и разметки сохранятся."}
  onAccepted:root.pst.resetAll()
 }
}
