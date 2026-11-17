#!/usr/bin/env python3
"""Recover the real ScreencopyView from a failed source to a live fixture window."""
import os
from pathlib import Path
import subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='capture-recovery-') as folder:
 stage=Path(folder)
 source=(ROOT/'SettingsUnderlay.qml').read_text().replace('import QtQuick','import QtQuick\nimport Quickshell')
 a=source.index(' readonly property var windows:');b=source.index(' function status(',a)
 source=source[:a]+''' property bool useValid:false
 QtObject {id:invalid}
 property QtObject chosen:QtObject {
  property var wayland:root.useValid ? ToplevelManager.toplevels.values.find(t=>t.title===Quickshell.env("CAPTURE_TEST_TITLE")) || null : invalid
  property var lastIpcObject:({at:[0,0],size:[400,300]})
 }
 readonly property var windows:root.active ? [chosen] : []
'''+source[b:]
 (stage/'SettingsUnderlay.qml').write_text(source)
 (stage/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Wayland
ShellRoot {
 id:root;settings.watchFiles:false
 property int phase:0
 property double since:0
 Window {width:400;height:300;visible:true;title:Quickshell.env("CAPTURE_TEST_TITLE");color:"#ee2255"}
 property var underlay:underlayLoader.item
 Window {width:400;height:300;visible:true;Loader {id:underlayLoader;anchors.fill:parent;active:false;sourceComponent:SettingsUnderlay {active:true}}}
 Timer {interval:700;running:true;onTriggered:underlayLoader.active=true}
 function check(ok,msg){if(!ok){console.error("FAIL "+msg);Qt.quit();return false}return true}
 Timer {interval:100;repeat:true;running:true;onTriggered:{
  if(!underlay)return
  const s=underlay.health
  if(root.phase===0 && s.state==="unavailable"){
   if(!root.check(s.attempts===4,"bounded attempts"))return
   if(!root.check(underlay.retryUnavailable()===1 && underlay.retryUnavailable()===0,"throttled explicit retry"))return
   root.phase=1;return
  }
  if(root.phase===1 && s.attempts===1){
   underlay.useValid=true;root.phase=2;return
  }
  if(root.phase===2 && s.ready===1){
   if(!root.check(s.attempts===1 && s.unavailable===0,"new source resets failures"))return
   root.since=Date.now();root.phase=3;return
  }
  if(root.phase===3 && Date.now()-root.since>600){
   if(!root.check(s.state==="running" && s.attempts===1,"live capture remains healthy"))return
   underlay.active=false;root.phase=4;return
  }
  if(root.phase===4 && s.windows===0){underlay.active=true;root.phase=5;return}
  if(root.phase===5 && s.ready===1){console.log("PASS explicit retry throttled; live replacement source recovers; release and reactivation work");Qt.quit()}
 }}
 Timer {interval:25000;running:true;onTriggered:{console.error("FAIL timeout "+root.phase+" "+JSON.stringify(underlay.status()));Qt.quit()}}
}''')
 env=dict(os.environ,QT_QPA_PLATFORM='wayland',CAPTURE_TEST_TITLE=stage.name)
 p=subprocess.run(['qs','-p',str(stage),'-n'],env=env,text=True,capture_output=True,timeout=29)
 log=p.stdout+p.stderr;print(log,end='')
 if p.returncode or 'FAIL ' in log or 'Binding loop' in log or 'PASS explicit retry' not in log:raise SystemExit('Live capture recovery failed')
