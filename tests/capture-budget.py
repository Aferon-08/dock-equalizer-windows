#!/usr/bin/env python3
"""Keep the real capture delegate; inject only an unavailable source selection."""
from pathlib import Path
import os,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='capture-budget-') as folder:
 stage=Path(folder)
 source=(ROOT/'SettingsUnderlay.qml').read_text()
 a=source.index(' readonly property var windows:');b=source.index(' function status(',a)
 source=source[:a]+''' QtObject {id:invalid}
 readonly property var windows:root.active ? [{wayland:invalid,lastIpcObject:{}}] : []
'''+source[b:]
 (stage/'SettingsUnderlay.qml').write_text(source)
 (stage/'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
 id:root;settings.watchFiles:false
 property int phase:0
 property double exhaustedAt:0
 SettingsUnderlay{id:underlay;active:true}
 Timer {interval:100;repeat:true;running:true;onTriggered:{
  const s=underlay.status()
  if(root.phase===0 && s.state==="unavailable"){
   if(s.attempts!==4){console.error("FAIL attempts "+s.attempts);Qt.quit();return}
   root.exhaustedAt=Date.now();root.phase=1
  }
  if(root.phase===1 && Date.now()-root.exhaustedAt>3000){
   if(s.attempts!==4){console.error("FAIL retries continue");Qt.quit();return}
   underlay.active=false;root.phase=2;return
  }
  if(root.phase===2 && s.windows===0){underlay.active=true;root.phase=3;return}
  if(root.phase===3 && s.attempts===1){console.log("PASS capture stops after four attempts; reactivation resets budget");Qt.quit()}
 }}
 Timer{interval:22000;running:true;onTriggered:{console.error("FAIL timeout "+JSON.stringify(underlay.status()));Qt.quit()}}
}''')
 p=subprocess.run(['qs','-p',str(stage),'-n'],env=dict(os.environ,QT_QPA_PLATFORM='wayland'),text=True,capture_output=True,timeout=26)
 log=p.stdout+p.stderr;print(log,end='')
 if p.returncode or 'FAIL ' in log or 'PASS capture stops' not in log:raise SystemExit('Capture budget failed')
 if log.count('Cannot capture frame')>8:raise SystemExit('Capture warning flood')
