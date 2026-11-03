#!/usr/bin/env python3
"""Start an isolated QML Service + DockLyrics; no network, models or recordings."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="dock-service-test-") as folder:
    stage = Path(folder)
    for path in ROOT.iterdir():
        if path.suffix in {".qml", ".js", ".mjs", ".qsb"}:
            shutil.copy2(path, stage)
    shutil.copytree(ROOT / "assets", stage / "assets")
    (stage / "shell.qml").write_text((ROOT / "tests/service-recovery.qml").read_text().replace('import ".."', 'import "."'))
    (stage / "wordtime.py").write_text('print(\'{"ok": true, "status": "missing"}\')')
    (stage / "wordtime-engine.py").write_text("""
import sys
if sys.argv[1:] == ['probe']:
    print('{"ready":true,"voicesReady":true}')
else:
    sys.stdin.readline()
    print('{"type":"result","ok":false,"message":"fixture analysis failed"}')
""")
    (stage / "spotify-capture.py").write_text('pass')
    (stage / "wallpaper-seed.py").write_text("""
import sys
from pathlib import Path
p = Path(__file__).with_name('wallpaper-attempted')
if not p.exists() or '--new' in sys.argv:
    p.touch()
    raise SystemExit('fixture seed unavailable')
print('{"seed":"feed00112233445566778899"}')
""")
    (stage / "youtube-duration.py").write_text("""
import json
import sys
from pathlib import Path
p = Path(__file__).with_name('duration-attempted')
seconds = 231 if p.exists() else 0
p.touch()
print(json.dumps({"id": sys.argv[1], "seconds": seconds}))
""")
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", DOCK_FIXTURE_DIR=str(stage), XDG_DATA_HOME=str(stage / "data"))
    env.pop("WAYLAND_DISPLAY", None)
    proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(stage), "-n"],
        env=env, text=True, capture_output=True, timeout=32)
    log = proc.stdout + proc.stderr
    print(log, end="")
    if proc.returncode or "FAIL " in log or "PASS duration retried" not in log or "PASS partial analysis" not in log:
        raise SystemExit("The runtime service did not recover independently")
