#!/usr/bin/env python3
"""The worker consumes the selected QML context even without a working session bus."""
import json,os
from pathlib import Path
import queue,subprocess,sys,tempfile,threading,time
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='palette-context-') as folder:
 stage=Path(folder);qs=stage/'qs'
 qs.write_text('#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["IPC_LOG"],"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nprint("ok")\n');qs.chmod(0o755)
 log=stage/'ipc.jsonl'
 red=stage/'red.png';blue=stage/'blue.png'
 Image.new('RGB',(12,12),'red').save(red);Image.new('RGB',(12,12),'blue').save(blue)
 env=dict(os.environ,PATH=str(stage)+os.pathsep+os.environ['PATH'],IPC_LOG=str(log),DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent')
 proc=subprocess.Popen([sys.executable,str(ROOT/'music-palette.py'),'--context-stdin'],env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
 events=queue.Queue()
 def reader():
  for line in proc.stdout:events.put(json.loads(line))
 threading.Thread(target=reader,daemon=True).start()
 def feed(state):proc.stdin.write(json.dumps(state)+'\n');proc.stdin.flush()
 def wait(predicate):
  end=time.monotonic()+6
  while time.monotonic()<end:
   try:d=events.get(timeout=.1)
   except queue.Empty:continue
   if predicate(d):return d
  raise AssertionError('Missing worker status; exit='+str(proc.poll()))
 def calls():return [json.loads(line)[5:] for line in log.read_text().splitlines()] if log.exists() else []
 try:
  feed({'playerId':'alpha','trackId':'a','playing':True,'artUrl':red.as_uri()})
  wait(lambda d:d['active'] and d['playerId']=='alpha')
  first_owner=next(c[1] for c in calls() if c[0]=='musicSet')
  encoded=json.dumps({'playerId':'browser','trackId':'b','playing':True,'artUrl':blue.as_uri()})
  proc.stdin.write(encoded[:20]);proc.stdin.flush();time.sleep(.25)
  assert proc.poll() is None
  proc.stdin.write(encoded[20:]+'\n');proc.stdin.flush()
  wait(lambda d:d['active'] and d['playerId']=='browser')
  deadline=time.monotonic()+5
  while not any(c[0]=='musicSet' and c[2].startswith('#0000ff') for c in calls()) and time.monotonic()<deadline:time.sleep(.1)
  assert any(c[0]=='musicSet' and c[2].startswith('#0000ff') for c in calls()),calls()
  assert not any(c[0]=='musicClear' for c in calls()),'player switch ended music session'
  assert all(c[1]==first_owner for c in calls()),'player switch replaced session owner'
  feed({'playerId':'alpha','trackId':'a','playing':False,'artUrl':red.as_uri()})
  wait(lambda d:not d['playing'] and d['playerId']=='alpha')
  wait(lambda d:not d['active'])
  assert calls()[-1]==['musicClear',first_owner]
  feed({'playerId':'browser','trackId':'b','playing':True,'artUrl':blue.as_uri()})
  wait(lambda d:d['active'])
  proc.stdin.close();proc.wait(timeout=5)
  assert proc.returncode==0 and calls()[-1]==['musicClear',first_owner]
  print('PASS authoritative selected player, partial pipe writes, shared lease across players, selected pause and EOF cleanup')
 finally:
  if proc.poll() is None:proc.terminate();proc.wait(timeout=6)
