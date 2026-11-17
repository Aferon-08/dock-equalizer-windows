#!/usr/bin/env python3
"""Check worker JSON on a private bus and mock IPC; never changes the shell theme."""
import json,os
from pathlib import Path
import queue,subprocess,sys,tempfile,threading,time
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]

def run():
 with tempfile.TemporaryDirectory(prefix='palette-status-') as folder:
  stage=Path(folder);qs=stage/'qs';qs.write_text('#!/usr/bin/env python3\nprint("ok")\n');qs.chmod(0o755)
  image=stage/'cover.png';Image.new('RGB',(20,20),'red').save(image)
  state=stage/'player.json'
  def update(play):
   t=state.with_suffix('.tmp');t.write_text(json.dumps({'status':play,'art':image.as_uri()}));t.replace(state)
  update('Paused')
  env=dict(os.environ,PATH=str(stage)+os.pathsep+os.environ['PATH'])
  player=subprocess.Popen([sys.executable,str(ROOT/'tests/palette-player.py'),str(state)],env=env)
  worker=subprocess.Popen([sys.executable,str(ROOT/'music-palette.py')],env=env,stdout=subprocess.PIPE,text=True)
  messages=queue.Queue()
  def read():
   for line in worker.stdout:messages.put(json.loads(line))
  threading.Thread(target=read,daemon=True).start()
  def wait(pred):
   end=time.monotonic()+8;seen=[]
   while time.monotonic()<end:
    try:d=messages.get(timeout=.2)
    except queue.Empty:continue
    seen.append(d)
    if pred(d):return d
   raise AssertionError('Missing status transition: '+str(seen))
  try:
   wait(lambda d:not d['active'] and not d['playing'])
   update('Playing');wait(lambda d:d['active'])
   update('Paused')
   wait(lambda d:d['active'] and not d['playing'])
   wait(lambda d:not d['active'] and not d['playing'])
   print('PASS palette JSON follows lease expiry while the waiting message stays unchanged',flush=True)
  finally:
   worker.terminate();worker.wait(timeout=8);player.terminate();player.wait(timeout=3)
if __name__=='__main__':
 if '--inside' in sys.argv:run()
 else:subprocess.run(['dbus-run-session','--',sys.executable,__file__,'--inside'],check=True,timeout=25)
