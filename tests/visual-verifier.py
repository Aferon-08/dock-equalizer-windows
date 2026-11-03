#!/usr/bin/env python3
"""A nominal process exit and fresh PNGs must not certify a broken showcase."""
import importlib.util
from pathlib import Path
import tempfile

from PIL import Image

path = Path(__file__).resolve().parents[1] / "tools/render-demo.py"
spec = importlib.util.spec_from_file_location("visual", path)
visual = importlib.util.module_from_spec(spec)
spec.loader.exec_module(visual)

def rejects(scene, frames, log, reason):
    try:
        visual.validate(scene, frames, log)
    except ValueError as error:
        assert reason in str(error), str(error)
    else:
        raise AssertionError("Invalid capture passed: " + reason)

with tempfile.TemporaryDirectory(prefix="dock-visual-test-") as folder:
    frames = Path(folder)
    rejects("dock", frames, "DEMO_FRAME 0 idle\nDEMO_FRAME 1 idle\nDEMO_DONE 2", "Incomplete")
    rejects("dock", frames, "Loading backend software", "software rendering")
    visual.SPECS["test"] = ((20, 16), 2, {"first": 1, "second": 1}, [("first", "second")])
    log = "DEMO_FRAME 0 first\nDEMO_FRAME 1 second\nDEMO_DONE 2"
    rejects("test", frames, log, "PNG files")
    for i in range(2):
        Image.new("RGB", (20, 16), "#191919").save(frames / f"{i:05d}.png")
    rejects("test", frames, log, "blank")
    for i in range(2):
        image = Image.new("RGB", (20, 16), "#191919")
        image.paste("#ddaaaa", (0, 0, 10, 16))
        image.save(frames / f"{i:05d}.png")
    rejects("test", frames, log, "No visible change")
    image.transpose(Image.Transpose.FLIP_LEFT_RIGHT).save(frames / "00001.png")
    assert visual.validate("test", frames, log)["frameCount"] == 2
print("PASS incomplete runs, software renderer, missing/blank/unchanged frames and valid sequence")
