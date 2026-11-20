"""Package the deployed runtime as an unsigned Windows 11 notification preview."""

import argparse
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

from package import HERE, REQUIRED, require_x64


def make_preview(stage: Path, output: Path, packer: str) -> None:
    for name in REQUIRED:
        if not (stage / name).is_file():
            raise ValueError(f"Incomplete runtime: {name}")
    require_x64(stage / "SekaiSoundbar.exe")
    version = (stage / "VERSION.txt").read_text(encoding="ascii").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"Invalid package version: {version}")

    manifest_root = HERE / "msix"
    manifest = (manifest_root / "AppxManifest.xml.in").read_text(encoding="utf-8")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="soundbar-msix-") as temp:
        payload = Path(temp) / "payload"
        shutil.copytree(stage, payload)
        shutil.copytree(manifest_root / "PackageAssets", payload / "PackageAssets")
        (payload / "AppxManifest.xml").write_text(manifest.replace("@VERSION@", version), encoding="utf-8")
        prefix = "/" if Path(packer).stem.lower() == "makeappx" else "-"
        packed = Path(temp) / "Soundbar.msix"
        subprocess.run([packer, "pack", f"{prefix}d", str(payload), f"{prefix}p", str(packed)], check=True)
        with zipfile.ZipFile(packed) as package:
            if package.testzip() or package.read("SekaiSoundbar.exe") != (stage / "SekaiSoundbar.exe").read_bytes():
                raise ValueError("Invalid packaged runtime")
        shutil.copyfile(packed, output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--packer", default="makemsix")
    args = parser.parse_args()
    stage = args.stage.resolve()
    output = args.out.resolve()
    if output.is_relative_to(stage):
        parser.error("--out must be outside --stage")
    make_preview(stage, output, args.packer)


if __name__ == "__main__":
    main()
