#!/usr/bin/env python3
"""Exercise the Quickshell settings panel and real profile files offscreen."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="dock-profile-") as folder:
        stage = Path(folder)
        for source in ROOT.iterdir():
            if source.suffix in {".qml", ".js", ".qsb"} or source.name in {"plugin.json", "settings-profile-read.py"}:
                shutil.copy2(source, stage)
        shutil.copy2(ROOT / "tests/settings-profiles.qml", stage / "shell.qml")
        export = stage / "Личный #1.json"
        imported = stage / "newer.json"
        imported.write_text(json.dumps({
            "format": "dock-equalizer.settings", "version": 1, "name": "Future build", "scope": "glass",
            "values": {"glassOpacity": .34, "token": "secret", "unknownField": 42, "wallpaperRegenerate": True},
        }))
        env = dict(os.environ, LC_ALL="C.UTF-8", PROFILE_FIXTURE=folder, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   XDG_RUNTIME_DIR=folder, IMPORT_PROFILE_URL=imported.as_uri(), EXPORT_PROFILE_URL=export.as_uri())
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("WAYLAND_SOCKET", None)
        library = stage / "state/sekaipop/profiles.json"
        for scenario in ("exercise", "restore", "future"):
            if scenario == "future":
                expected = '{"version":99,"profiles":[{"unknown":"preserve"}]}'
                library.write_text(expected)
            proc = subprocess.run(["qs", "-p", folder, "-n"], env=dict(env, PROFILE_SCENARIO=scenario),
                                  capture_output=True, text=True, timeout=10)
            log = proc.stdout + proc.stderr
            print(log, end="")
            assert proc.returncode == 0 and "PASS profile " + scenario in log and "FAIL " not in log
            for defect in ("TypeError:", "ReferenceError:", "Binding loop detected", "Unable to assign"):
                assert defect not in log, defect
            if scenario == "future":
                assert library.read_text() == expected
            if scenario == "exercise":
                saved = json.loads(export.read_text())
                assert saved["version"] == 1 and saved["scope"] == "glass"
                assert saved["values"]["glassOpacity"] == .56 and "autoSpotify" not in saved["values"]


if __name__ == "__main__":
    main()
