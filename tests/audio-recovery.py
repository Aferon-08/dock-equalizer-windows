#!/usr/bin/env python3
"""Exercise the real QML Process, including 3 exits, success and pause."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="dock-audio-test-") as folder:
    stage = Path(folder)
    shutil.copy2(ROOT / "SpectrumCapture.qml", stage)
    (stage / "shell.qml").write_text((ROOT / "tests/audio-recovery.qml").read_text().replace('import ".."', 'import "."'))
    helper = stage / "fake-cava.py"
    helper.write_text("""from pathlib import Path
import sys
import time
p = Path(sys.argv[1])
n = int(p.read_text()) + 1 if p.exists() else 1
p.write_text(str(n))
if n <= 3:
    print("fixture output unavailable", file=sys.stderr)
    sys.exit(9)
for _ in range(6):
    print("73;" * 64, flush=True)
    time.sleep(.04)
sys.exit(8)
""")
    counter = stage / "launches"
    proc = subprocess.run(["qs", "-p", str(stage), "-n"],
        env=dict(os.environ, QT_QPA_PLATFORM="offscreen", DOCK_TEST_AUDIO_HELPER=str(helper),
                 DOCK_TEST_AUDIO_COUNTER=str(counter)), text=True, capture_output=True, timeout=24)
    logs = proc.stdout + proc.stderr
    print(logs, end="")
    if (proc.returncode != 0 or "FAIL " in logs or "PASS recovered after three exits" not in logs
            or "PASS valid frames reset failures" not in logs or not counter.exists() or counter.read_text() != "4"):
        raise SystemExit("Audio recovery did not satisfy the lifecycle contract")
