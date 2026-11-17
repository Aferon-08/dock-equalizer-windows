#!/usr/bin/env python3
"""Exercise the real settings panel without touching the user's shell or settings."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
for scenario in ('timeout','missing','software','shader'):
 with tempfile.TemporaryDirectory(prefix='settings-recovery-') as folder:
  stage=Path(folder)
  for src in ROOT.iterdir():
   if src.suffix in {'.qml','.js','.mjs','.qsb'}:shutil.copy2(src,stage/src.name)
  shutil.copytree(ROOT/'assets',stage/'assets')
  (stage/'shell.qml').write_text((ROOT/'tests/settings-recovery.qml').read_text())
  if scenario=='shader':(stage/'settings-morph.frag.qsb').write_bytes(b'invalid shader')
  env=dict(os.environ,QT_QPA_PLATFORM='wayland',QSG_RHI_BACKEND='opengl',RECOVERY_SCENARIO=scenario)
  if scenario=='software':env['QT_QUICK_BACKEND']='software'
  else:env.pop('QT_QUICK_BACKEND',None)
  proc=subprocess.run(['qs','-p',str(stage),'-n'],env=env,capture_output=True,text=True,timeout=10)
  log=proc.stdout+proc.stderr
  print(log,end='')
  if proc.returncode or 'FAIL ' in log or 'PASS settings recovery '+scenario not in log:
   raise SystemExit('Settings recovery failed: '+scenario)
