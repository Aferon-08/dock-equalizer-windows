#!/usr/bin/env python3
"""Run an expanded dock with broken QSBs and with Qt's software backend."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
for scenario in ('shader','software','capture'):
 with tempfile.TemporaryDirectory(prefix='dock-render-recovery-') as folder:
  stage=Path(folder)
  for src in ROOT.iterdir():
   if src.suffix in {'.qml','.js','.mjs','.qsb'}:shutil.copy2(src,stage/src.name)
  shutil.copytree(ROOT/'assets',stage/'assets')
  if scenario=='shader':
   for name in ('liquid.frag.qsb','spectrum-ribbon.frag.qsb'):(stage/name).write_bytes(b'invalid shader')
  if scenario=='capture':
   source=(stage/'SettingsUnderlay.qml').read_text().replace('import QtQuick','import QtQuick\nimport Quickshell')
   a=source.index(' readonly property var windows:');b=source.index(' function status(',a)
   source=source[:a]+""" property bool useValid:false
 QtObject {id:invalid}
 property QtObject chosen:QtObject {
  property var wayland:root.useValid ? ToplevelManager.toplevels.values.find(t=>t.title===Quickshell.env("CAPTURE_TEST_TITLE")) || null : invalid
  property var lastIpcObject:({at:[0,0],size:[400,300]})
 }
 readonly property var windows:root.active ? [chosen] : []
"""+source[b:]
   (stage/'SettingsUnderlay.qml').write_text(source)
  (stage/'DemoRecorder.qml').write_text('import QtQuick\nQtObject { property Item scene; property bool finishing:false; function record(phase){} function finish(){Qt.quit()} }')
  scene=(ROOT/'tools/demo-dock.qml').read_text().replace('import ".." as Plugin','import "." as Plugin')
  injected='''
    function all(item) {let out=[item];for(const c of (item.children || []))out=out.concat(all(c));return out}
    Timer { interval:6800;running:true;onTriggered:{
        const status=wings.rendererStatus()
        const capsules=test.all(wings).filter(c=>c.ribbonAvailable!==undefined)
        const ok=!status.shader && wings.ownsHousing && wings.glassAmount===0
            && status.capture.state==="disabled" && status.capture.attempts===0
            && wings.lyricsWidthExtra>50 && capsules.length===2
            && capsules.every(c=>!c.ribbonAvailable && c.housingVisible && c.level>0)
        console.log((ok?"PASS":"FAIL")+" dock fallback "+JSON.stringify(status)+" capsules="+capsules.length)
        win.contentItem.grabToImage(r=>{r.saveToFile(Quickshell.env("RECOVERY_PNG"));Qt.quit()})
    }}
'''
  if scenario=='capture':
   scene=scene.replace('property bool working: true','property bool working: false').replace('test.elapsed+=.05','test.elapsed+=.05;demoHost.working=test.elapsed>.7')
   injected="""
    property int recoveryPhase:0
    property double fallbackAt:0
    Window {width:400;height:300;visible:true;title:Quickshell.env("CAPTURE_TEST_TITLE");color:"#aa55ee"}
    function all(item) {let out=[item];for(const c of (item.children || []))out=out.concat(all(c));return out}
    Timer {interval:100;running:true;repeat:true;onTriggered:{
     const status=wings.rendererStatus()
     const capture=test.all(wings).find(c=>c.useValid!==undefined)
     if(test.recoveryPhase===0 && status.reason==="capture-unavailable"){
      if(status.mode!=="fallback" || wings.glassAmount!==0 || status.capture.attempts!==4){console.error("FAIL fallback state");Qt.quit();return}
      test.fallbackAt=Date.now();test.recoveryPhase=1;return
     }
     if(test.recoveryPhase===1 && Date.now()-test.fallbackAt>500){
      if(status.mode!=="fallback" || status.capture.attempts!==4 || status.capture.windows!==1){console.error("FAIL fallback resets its own failure");Qt.quit();return}
      capture.useValid=true;test.recoveryPhase=2;return
     }
     if(test.recoveryPhase===2 && status.capture.ready===1){
      if(status.mode!=="glass" || wings.glassAmount<=0 || !wings.useHousingShader){console.error("FAIL restored capture does not restore glass");Qt.quit();return}
      console.log("PASS dock fallback capture and automatic recovery "+JSON.stringify(status))
      win.contentItem.grabToImage(r=>{r.saveToFile(Quickshell.env("RECOVERY_PNG"));Qt.quit()})
     }
    }}
"""
  (stage/'shell.qml').write_text(scene.rsplit('}',1)[0]+injected+'}\n')
  dest=ROOT/'.agents/reports'/('fallback-'+scenario+'.png')
  dest.parent.mkdir(parents=True,exist_ok=True)
  env=dict(os.environ,QT_QPA_PLATFORM='wayland',QSG_RHI_BACKEND='opengl',RECOVERY_PNG=str(dest),CAPTURE_TEST_TITLE=stage.name)
  if scenario=='software':env['QT_QUICK_BACKEND']='software'
  else:env.pop('QT_QUICK_BACKEND',None)
  p=subprocess.run(['qs','-p',str(stage),'-n'],env=env,text=True,capture_output=True,timeout=28)
  log=p.stdout+p.stderr;print(log,end='')
  if p.returncode or 'FAIL ' in log or 'Binding loop' in log or 'PASS dock fallback' not in log or not dest.exists():raise SystemExit('Dock renderer recovery failed: '+scenario)
