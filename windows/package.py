"""Package a deployed Windows x64 runtime as a portable ZIP and an NSIS setup."""

import argparse
import hashlib
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
import xml.etree.ElementTree as ET
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


def make_notification_identity(stage: Path, work: Path, version: str, makeappx: str) -> tuple[Path, dict]:
    assets = HERE / "msix"
    payload = work / "identity"
    shutil.copytree(assets / "PackageAssets", payload / "PackageAssets")
    manifest = (assets / "AppxManifest.xml.in").read_text(encoding="utf-8").replace("@VERSION@", version)
    (payload / "AppxManifest.xml").write_text(manifest, encoding="utf-8")

    package_manifest = ET.fromstring(manifest)
    identity = package_manifest.find("{*}Identity").attrib
    app = package_manifest.find("{*}Applications/{*}Application").attrib
    exe_manifest = (assets / "Executable.manifest").read_bytes()
    exe_identity = ET.fromstring(exe_manifest).find("{urn:schemas-microsoft-com:msix.v1}msix").attrib
    if exe_identity != {"publisher": identity["Publisher"], "packageName": identity["Name"], "applicationId": app["Id"]}:
        raise ValueError("Executable and package identities differ")
    if exe_manifest.replace(b"\r\n", b"\n") not in (stage / app["Executable"]).read_bytes().replace(b"\r\n", b"\n"):
        raise ValueError("The staged executable is missing its notification identity manifest")

    package = work / "notification-identity.msix"
    if Path(makeappx).stem.lower() == "makeappx":
        subprocess.run([makeappx, "pack", "/d", str(payload), "/p", str(package), "/nv"], check=True)
    else:
        subprocess.run([makeappx, "pack", "-d", str(payload), "-p", str(package)], check=True)
    with zipfile.ZipFile(package) as archive:
        if archive.testzip() or archive.read("AppxManifest.xml") != (payload / "AppxManifest.xml").read_bytes():
            raise ValueError("Invalid notification identity package")
    return package, identity


def package(stage: Path, out: Path, makensis: str, makeappx: str) -> None:
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

    with tempfile.TemporaryDirectory(prefix="soundbar-identity-") as temp:
        identity_package, identity = make_notification_identity(stage, Path(temp), version, makeappx)
        subprocess.run([
            makensis, "-V2", "-INPUTCHARSET", "UTF8", f"-DVERSION={version}",
            f"-DPAYLOAD_LICENSE={stage / 'LICENSE'}", f"-DPAYLOAD_FILES={stage / '*'}",
            f"-DIDENTITY_PACKAGE={identity_package}", f"-DIDENTITY_SCRIPT={HERE / 'msix/RegisterIdentity.ps1'}",
            f"-DIDENTITY_NAME={identity['Name']}", f"-DIDENTITY_PUBLISHER={identity['Publisher']}",
            f"-DSETUP={setup}", str(HERE / "installer.nsi"),
        ], check=True)
    for file in (portable, setup):
        print(f"{checksum(file)}  {file.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--makensis", default="makensis")
    parser.add_argument("--makeappx", default="MakeAppx.exe")
    parser.add_argument("--qt-archives", type=Path)
    parser.add_argument("--qt-version", default="6.8.2")
    args = parser.parse_args()
    stage = args.stage.resolve()
    out = args.out.resolve()
    if out == stage or out.is_relative_to(stage):
        parser.error("--out must be outside --stage")
    if args.qt_archives:
        stage_qt_notices(args.qt_archives, stage, args.qt_version)
    package(stage, out, args.makensis, args.makeappx)


if __name__ == "__main__":
    main()
