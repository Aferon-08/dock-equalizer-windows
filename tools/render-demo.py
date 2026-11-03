#!/usr/bin/env python3
"""Render and verify actual QML scenes in an isolated Quickshell instance."""
import argparse
from collections import defaultdict
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from PIL import Image, ImageChops, ImageDraw, ImageOps, ImageStat

ROOT = Path(__file__).resolve().parent.parent
SPECS = {
    "dock": ((1100, 360), 240, {"idle": 8, "compact": 8, "expanded": 25, "paused": 8},
             [("idle", "compact"), ("compact", "expanded"), ("expanded", "paused")]),
    "wallpaper": ((1280, 720), 180, {"black": 1, "entrance": 8, "settled": 15, "music": 15, "recolored": 15},
                  [("black", "entrance"), ("entrance", "settled"), ("settled", "recolored")]),
    "voices": ((1000, 260), 240, {"solo": 8, "split": 8, "unison": 8, "finale": 8},
               [("solo", "split"), ("split", "unison"), ("unison", "finale")]),
    "settings": ((1280, 960), 120, {"phone": 8, "opening": 12, "open": 12, "closing": 12, "returned": 8},
                 [("phone", "opening"), ("opening", "open"), ("open", "closing"), ("closing", "returned")]),
}


def difference(left, right):
    return sum(ImageStat.Stat(ImageChops.difference(left, right)).mean) / (3 * 255)


def validate(scene, frames, log, against=None):
    size, minimum, phases, distinct = SPECS[scene]
    done = re.findall(r"DEMO_DONE (\d+)", log)
    events = [(int(i), phase) for i, phase in re.findall(r"DEMO_FRAME (\d+) (\w+)", log)]
    if "Loading backend software" in log:
        raise ValueError("Qt Quick selected software rendering; this does not exercise the glass shaders.")
    if "DEMO_FAIL " in log or done != [str(len(events))] or len(events) < minimum:
        raise ValueError(f"Incomplete {scene} run: {len(events)} frames, expected at least {minimum} and an end marker.")
    if [i for i, _ in events] != list(range(len(events))):
        raise ValueError("Missing, duplicate or out-of-order frame.")
    names = [f"{i:05d}.png" for i, _ in events]
    if sorted(p.name for p in frames.glob("*.png")) != names:
        raise ValueError("PNG files do not match the recorded frame sequence.")
    grouped = defaultdict(list)
    for name, (_, phase) in zip(names, events):
        with Image.open(frames / name) as im:
            if im.format != "PNG" or im.size != size:
                raise ValueError(f"{name}: expected a {size[0]}×{size[1]} PNG.")
            im.verify()
        grouped[phase].append(name)
    for phase, count in phases.items():
        if len(grouped[phase]) < count:
            raise ValueError(f"{scene} never reached {phase} for {count} frames; found {len(grouped[phase])}.")

    samples = {phase: grouped[phase][len(grouped[phase]) // 2] for phase in phases}

    def sample(path):
        with Image.open(path) as im:
            return im.convert("RGB").resize((256, 144), Image.Resampling.LANCZOS)

    images = {phase: sample(frames / name) for phase, name in samples.items()}
    for phase, image in images.items():
        stat = ImageStat.Stat(image)
        if phase == "black":
            if max(stat.mean) > 5:
                raise ValueError("The wallpaper must start black.")
        elif max(stat.stddev) < 3:
            raise ValueError(f"{phase} is blank or has no visible scene content.")
    deltas = {f"{left}:{right}": difference(images[left], images[right]) for left, right in distinct}
    for pair, delta in deltas.items():
        if delta < .002:
            raise ValueError(f"No visible change for {pair} ({delta:.4f}).")
    if against:
        prior = json.loads((against / "verification.json").read_text())
        if prior["scene"] != scene or prior["size"] != list(size):
            raise ValueError("Golden sequence belongs to a different scene or resolution.")
        for phase in phases:
            baseline = sample(against / prior["samples"][phase])
            delta = difference(images[phase], baseline)
            if delta > .045:
                raise ValueError(f"{phase} differs from the reference by {delta:.1%} (limit 4.5%).")

    sheet = Image.new("RGB", (256 * min(3, len(samples)), 166 * ((len(samples) + 2) // 3)), "#111820")
    draw = ImageDraw.Draw(sheet)
    for idx, phase in enumerate(images):
        x, y = idx % 3 * 256, idx // 3 * 166
        with Image.open(frames / samples[phase]) as im:
            thumbnail = ImageOps.contain(im.convert("RGB"), (256, 144), Image.Resampling.LANCZOS)
        sheet.paste(thumbnail, (x + (256 - thumbnail.width) // 2, y + 22 + (144 - thumbnail.height) // 2))
        draw.text((x + 8, y + 4), f"{phase} ({samples[phase]})", fill="white")
    sheet.save(frames / "contact-sheet.jpg", quality=92)
    report = {"scene": scene, "size": list(size), "frameCount": len(events),
        "phaseCounts": {phase: len(rows) for phase, rows in grouped.items()},
        "samples": samples, "phasePixelDeltas": deltas}
    (frames / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("scene", choices=SPECS)
    parser.add_argument("output", type=Path)
    parser.add_argument("--against", type=Path, help="compare with a reviewed render of the same scene")
    parser.add_argument("--keep-failed", type=Path, help="save rejected frames to this new directory for inspection")
    args = parser.parse_args()
    if args.output.exists() and (not args.output.is_dir() or any(args.output.iterdir())):
        parser.error("use a new or empty output directory")
    if args.keep_failed and args.keep_failed.exists():
        parser.error("diagnostic directory already exists")
    try:
        with tempfile.TemporaryDirectory(prefix="sekaipop-demo-") as folder:
            stage = Path(folder)
            frames = stage / "frames"
            frames.mkdir()
            for p in ROOT.iterdir():
                if p.suffix in (".qml", ".js", ".mjs", ".qsb") or p.name in ("assets", "plugin.json"):
                    if p.is_dir():
                        shutil.copytree(p, stage / p.name)
                    else:
                        shutil.copy2(p, stage / p.name)
            shutil.copy2(ROOT / "tools/DemoRecorder.qml", stage)
            scene = (ROOT / "tools" / f"demo-{args.scene}.qml").read_text()
            (stage / "shell.qml").write_text(scene.replace('import ".." as Plugin', 'import "." as Plugin')
                .replace('import "../WallpaperPet.js"', 'import "WallpaperPet.js"'))
            proc = subprocess.run(["qs", "-p", str(stage), "-n"],
                env=dict(os.environ, DEMO_OUT=str(frames), QSG_INFO="1"), text=True, capture_output=True, timeout=65)
            log = proc.stdout + proc.stderr
            if proc.returncode:
                raise ValueError(f"Quickshell exited with {proc.returncode}:\n{log[-3000:]}")
            try:
                report = validate(args.scene, frames, log, args.against)
            except ValueError as error:
                # Keep failures actionable without dumping hundreds of frame markers.
                if args.keep_failed:
                    shutil.copytree(frames, args.keep_failed)
                    (args.keep_failed / "render.log").write_text(log)
                diagnostics = "\n".join(line for line in log.splitlines() if "DEMO_FRAME " not in line)
                raise ValueError(f"{error}\n{diagnostics[-3000:]}") from error
            shutil.copytree(frames, args.output, dirs_exist_ok=True)
        print(json.dumps(report, ensure_ascii=False))
    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
