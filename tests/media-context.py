#!/usr/bin/env python3
"""Two model players drive the actual Service and a silent fake spectrum process."""
import os
import sys
from pathlib import Path
import shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='media-context-') as folder:
 stage=Path(folder)
 for src in ROOT.iterdir():
  if src.suffix in {'.qml','.js','.mjs','.qsb'}:shutil.copy2(src,stage/src.name)
 shutil.copytree(ROOT/'assets',stage/'assets')
 (stage/'shell.qml').write_text((ROOT/'tests/media-context.qml').read_text())
 (stage/'wordtime-engine.py').write_text('print(\'{"ready":false}\')')
 (stage/'spotify-capture.py').write_text('pass')
 (stage/'wordtime.py').write_text('print(\'{"status":"missing"}\')')
 (stage/'fake-spectrum.py').write_text('import time\nwhile True:\n print("0;"*64,flush=True)\n time.sleep(.05)\n')
 from PIL import Image
 for name,color in [('a','red'),('b','blue')]:Image.new('RGB',(10,10),color).save(stage/(name+'.png'))
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',TEST_COVER_A=(stage/'a.png').as_uri(),TEST_COVER_B=(stage/'b.png').as_uri(),MEDIA_FIXTURE=str(stage),XDG_DATA_HOME=str(stage/'data'));env.pop('WAYLAND_DISPLAY',None)
 if '--palette' in sys.argv:
  shutil.copy2(ROOT/'music-palette.py',stage/'music-palette.py')
  fake=stage/'qs';fake.write_text('#!/usr/bin/env python3\nprint("ok")\n');fake.chmod(0o755)
  env.update(TEST_PALETTE='1',TEST_COVER_A=(stage/'a.png').as_uri(),TEST_COVER_B=(stage/'b.png').as_uri(),PATH=str(stage)+os.pathsep+os.environ['PATH'])
 config=stage/'bus.conf'
 config.write_text('<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen><auth>EXTERNAL</auth><policy context="default"><allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/></policy></busconfig>')
 p=subprocess.run(['dbus-run-session','--config-file='+str(config),'--',shutil.which('qs'),'-p',str(stage),'-n'],env=env,text=True,capture_output=True,timeout=14)
 log=p.stdout+p.stderr;print(log,end='')
 if p.returncode or 'FAIL ' in log or 'Error:' in log or 'Binding loop' in log or 'PASS shared selection' not in log:raise SystemExit('Media context test failed')
