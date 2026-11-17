#!/usr/bin/env python3
"""Run an expanded dock with broken QSBs and with Qt's software backend."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
for scenario in ('shader','software'):
 with tempfile.TemporaryDirectory(prefix='dock-render-recovery-') as folder:
  stage=Path(folder)
  for src in ROOT.iterdir():
   if src.suffix in {'.qml','.js','.mjs','.qsb'}:shutil.copy2(src,stage/src.name)
  shutil.copytree(ROOT/'assets',stage/'assets')
  if scenario=='shader':
   for name in ('liquid.frag.qsb','spectrum-ribbon.frag.qsb'):(stage/name).write_bytes(b'invalid shader')
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
  (stage/'shell.qml').write_text(scene.rsplit('}',1)[0]+injected+'}\n')
  dest=ROOT/'.agents/reports'/('fallback-'+scenario+'.png')
  dest.parent.mkdir(parents=True,exist_ok=True)
  env=dict(os.environ,QT_QPA_PLATFORM='wayland',QSG_RHI_BACKEND='opengl',RECOVERY_PNG=str(dest))
  if scenario=='software':env['QT_QUICK_BACKEND']='software'
  else:env.pop('QT_QUICK_BACKEND',None)
  p=subprocess.run(['qs','-p',str(stage),'-n'],env=env,text=True,capture_output=True,timeout=14)
  log=p.stdout+p.stderr;print(log,end='')
  if p.returncode or 'FAIL ' in log or 'PASS dock fallback' not in log or not dest.exists():raise SystemExit('Dock renderer recovery failed: '+scenario)
