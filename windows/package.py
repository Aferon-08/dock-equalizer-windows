"""Package a deployed Windows x64 runtime as a portable ZIP and an NSIS setup."""

import argparse
import hashlib
import re
import shutil
import struct
import subprocess
import tarfile
import zipfile
from pathlib import Path, PurePosixPath


HERE = Path(__file__).resolve().parent
QT_MODULES = ("qtbase", "qtdeclarative", "qtsvg")
REQUIRED = (
    "SekaiSoundbar.exe", "Qt6Core.dll", "Qt6Quick.dll", "Qt6Qml.dll",
    "LICENSE", "VERSION.txt", "qt.conf", "plugins/platforms/qwindows.dll",
    "plugins/imageformats/qsvg.dll", "qml/QtQuick/qmldir", "qml/QtQuick/Controls/qmldir",
    "qml/QtQuick/Effects/qmldir", "qml/QtQuick/Layouts/qmldir",
)


def stage_qt_notices(archives: Path, stage: Path, version: str) -> None:
    for module in QT_MODULES:
        with tarfile.open(archives / f"{module}-{version}.tar.gz") as archive:
            for member in archive:
                _, *parts = PurePosixPath(member.name).parts
                if not parts or ".." in parts or not member.isfile():
                    continue
                name = parts[-1].lower()
                notice = name.startswith(("license", "copying", "copyright", "notice")) or name == "qt_attribution.json"
                if parts[0] == "LICENSES" or (parts[0] == "src" and notice and member.size < 1_000_000):
                    target = stage / "licenses" / "Qt" / f"{module}-{version}" / Path(*parts)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with archive.extractfile(member) as source, target.open("wb") as output:
                        shutil.copyfileobj(source, output)


def require_x64(exe: Path) -> None:
    with exe.open("rb") as binary:
        header = binary.read(64)
        if header.startswith(b"MZ") and len(header) == 64:
            binary.seek(struct.unpack_from("<I", header, 60)[0])
            if binary.read(6) == b"PE\0\0\x64\x86":
                return
    raise ValueError(f"Expected a Windows x64 executable: {exe}")


def checksum(path: Path) -> str:
    with path.open("rb") as binary:
        return hashlib.file_digest(binary, "sha256").hexdigest()


def package(stage: Path, out: Path, makensis: str) -> None:
    for name in REQUIRED:
        if not (stage / name).is_file():
            raise ValueError(f"Incomplete runtime: {name}")
    require_x64(stage / "SekaiSoundbar.exe")
    version = (stage / "VERSION.txt").read_text(encoding="ascii").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"Invalid package version: {version}")
    for module in QT_MODULES:
        if not list((stage / "licenses" / "Qt").glob(f"{module}-*/LICENSES/LGPL-3.0-only.txt")):
            raise ValueError(f"Missing LGPL license text for {module}")
    if (stage / "alignment" / "python").is_dir() and not (stage / "alignment/python/LICENSE.txt").is_file():
        raise ValueError("Missing Python license text")

    shutil.copyfile(HERE / "THIRD-PARTY.md", stage / "THIRD-PARTY-WINDOWS.md")
    (stage / "ЗАПУСК.txt").write_text((HERE / "ЗАПУСК.txt").read_text(encoding="utf-8"), encoding="utf-8-sig")
    manifest = stage / "SHA256SUMS"
    files = [file for file in stage.rglob("*") if file.is_file() and file != manifest]
    manifest.write_text("".join(f"{checksum(file)}  {file.relative_to(stage).as_posix()}\n"
                                for file in sorted(files)), encoding="utf-8")
    out.mkdir(parents=True, exist_ok=True)
    stem = "SekaiSoundbar-Windows11-x64"
    portable = out / f"{stem}.zip"
    setup = out / f"{stem}-Setup.exe"
    with zipfile.ZipFile(portable, "w", zipfile.ZIP_DEFLATED) as archive:
        for file in sorted([*files, manifest]):
            archive.write(file, f"{stem}/{file.relative_to(stage).as_posix()}")
    with zipfile.ZipFile(portable) as archive:
        bad = archive.testzip()
        if bad:
            raise ValueError(f"Corrupt ZIP entry: {bad}")

    subprocess.run([makensis, "-V2", "-INPUTCHARSET", "UTF8", f"-DVERSION={version}", f"-DPAYLOAD={stage}",
                    f"-DSETUP={setup}", str(HERE / "installer.nsi")], check=True)
    for file in (portable, setup):
        print(f"{checksum(file)}  {file.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--makensis", default="makensis")
    parser.add_argument("--qt-archives", type=Path)
    parser.add_argument("--qt-version", default="6.8.2")
    args = parser.parse_args()
    stage = args.stage.resolve()
    out = args.out.resolve()
    if out == stage or out.is_relative_to(stage):
        parser.error("--out must be outside --stage")
    if args.qt_archives:
        stage_qt_notices(args.qt_archives, stage, args.qt_version)
    package(stage, out, args.makensis)


if __name__ == "__main__":
    main()
