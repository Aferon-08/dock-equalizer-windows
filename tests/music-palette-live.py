"""Run real daemon + silent fake MPRIS on a private bus against installed shell."""
import hashlib
import http.server
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
from PIL import Image

BASE = Path(__file__).resolve().parent

def ipc(*args):
    return subprocess.check_output(['qs', '-c', 'sekaipop', 'ipc', 'call', *args], text=True).strip()
def status():
    return json.loads(ipc('theme', 'musicStatus'))
def wait(predicate, timeout=10):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        value = status()
        if predicate(value):
            return value
        time.sleep(.1)
    raise AssertionError('timeout: ' + str(status()))

def inner():
    baseline = wait(lambda s: not s['active'])
    persisted = [Path.home()/'.local/state/sekaipop'/n for n in ('theme','custom-palette','dark','darker','theme-screens')]
    def hashes():
        return [hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None for p in persisted]
    persisted.append(Path.home()/'.config/sekaipop/settings.json')
    before = hashes()
    data = {}
    for key, color in [('red','#df2344'), ('blue','#2344df'), ('green','#21d042')]:
        stream = io.BytesIO()
        Image.new('RGB',(40,40),color).save(stream,format='PNG')
        data[key] = stream.getvalue()
    attempts = []
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def do_GET(self):
            if self.path.startswith('/slow'):
                time.sleep(1.5)
            if self.path == '/retry':
                attempts.append(1)
                if len(attempts) == 1:
                    self.send_error(503)
                    return
            self.send_response(200); self.end_headers()
            self.wfile.write(data['green' if self.path == '/retry' else ('blue' if self.path == '/final' else 'red')])
    server = http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    url = 'http://127.0.0.1:%s' % server.server_port
    with tempfile.TemporaryDirectory() as tmp:
        state = Path(tmp)/'state.json'
        def update(play, art):
            next_file = state.with_suffix('.next')
            next_file.write_text(json.dumps({'status': play, 'art': art}))
            next_file.replace(state)
        update('Paused','')
        player = subprocess.Popen(['python3',str(BASE/'palette-player.py'),str(state)],stdout=subprocess.DEVNULL)
        worker = subprocess.Popen(['python3',str(BASE.parent/'music-palette.py')],stdout=subprocess.DEVNULL)
        try:
            update('Playing',url+'/red')
            first = wait(lambda s:s['active'])
            for i in range(20):
                update('Playing',url+'/slow-'+str(i)); time.sleep(.12)
                update('Playing',''); time.sleep(.12)
                assert status()['active'], 'palette reset while tracks were switching'
            update('Playing',url+'/final')
            final = wait(lambda s:s['active'] and s['palette']!=first['palette'])
            assert final['owner']==first['owner']
            print('PASS: rapid switches + missing artwork -> final cover automatically',flush=True)
            update('Playing','')
            for _ in range(31):
                time.sleep(.2)
                assert status()['active'], 'lease expired during missing artwork'
            print('PASS: artwork missing for 6 seconds keeps musical palette alive',flush=True)
            update('Playing',url+'/retry')
            retry = wait(lambda s:s['active'] and s['palette']!=final['palette'])
            assert len(attempts)>=2
            assert retry['owner']==first['owner']
            print('PASS: HTTP 503 retries and applies same track without another switch',flush=True)
            update('Paused',url+'/retry')
            restored=wait(lambda s:not s['active'])
            assert restored['palette']==baseline['palette']
            assert hashes()==before
            print('PASS: actual pause restores exact baseline; persisted theme files unchanged',flush=True)
        finally:
            worker.terminate(); worker.wait(timeout=10)
            player.terminate(); player.wait(timeout=3)
            server.shutdown()
            wait(lambda s:not s['active'])

if __name__ == '__main__':
    if '--private-bus' in sys.argv:
        inner()
    else:
        settings=Path.home()/'.local/state/sekaipop/plugins/dock-equalizer.json'
        enabled=json.loads(settings.read_text())['settings'].get('musicPalette', True)
        try:
            ipc('plugins','set','dock-equalizer','musicPalette','false')
            wait(lambda s:not s['active'])
            subprocess.run(['dbus-run-session','--','python3',__file__,'--private-bus'],check=True)
        finally:
            ipc('plugins','set','dock-equalizer','musicPalette',str(enabled).lower())
