"""Package a deployed Windows x64 runtime as a portable ZIP and an NSIS setup."""

import argparse
import hashlib
import re
import shutil
import struct
import subprocess
import tarfile
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


def notification_identity_args(exe: Path, package: Path | None, version: str,
                               test_certificate: Path | None = None) -> list[str]:
    embedded = re.search(rb'<msix xmlns="urn:schemas-microsoft-com:msix\.v1"\s+[^<>]+/>', exe.read_bytes())
    if package is None:
        if test_certificate:
            raise ValueError("A test certificate requires a signed --notification-package")
        if embedded:
            raise ValueError("The identity-enabled EXE requires a signed --notification-package")
        return []

    with zipfile.ZipFile(package) as archive:
        signature = "AppxSignature.p7x"
        if (signature not in archive.namelist() or not archive.read(signature).startswith(b"PKCX")
                or archive.testzip()):
            raise ValueError("Expected a signed MSIX notification package")
        manifest = ET.fromstring(archive.read("AppxManifest.xml"))
        if test_certificate:
            certificate_data = test_certificate.read_bytes()
            if not certificate_data or certificate_data not in archive.read(signature)[4:]:
                raise ValueError("The test certificate must be present in the MSIX signature")
    identity = manifest.find("{*}Identity").attrib
    application = manifest.find("{*}Applications/{*}Application").attrib
    if (identity["Version"] != f"{version}.0" or application["Executable"] != exe.name
            or manifest.findtext("{*}Properties/{*}AllowExternalContent") != "true"):
        raise ValueError("The notification package must target this external executable and version")
    if not any(capability.get("Name") == "userNotificationListener"
               for capability in manifest.findall("{*}Capabilities/{*}Capability")):
        raise ValueError("The notification package does not declare notification access")

    expected = {"publisher": identity["Publisher"], "packageName": identity["Name"], "applicationId": application["Id"]}
    if not embedded or ET.fromstring(embedded.group()).attrib != expected:
        raise ValueError("Executable and package identities differ")
    args = [f"-DIDENTITY_PACKAGE={package}", f"-DIDENTITY_SCRIPT={HERE / 'msix/RegisterIdentity.ps1'}",
            f"-DIDENTITY_NAME={identity['Name']}", f"-DIDENTITY_PUBLISHER={identity['Publisher']}"]
    if test_certificate:
        if identity["Publisher"] != "CN=Sekai Soundbar Test":
            raise ValueError("Only the Sekai Soundbar test publisher can be installed by Setup")
        args.extend([f"-DTEST_CERTIFICATE={test_certificate}",
                     f"-DTEST_CERT_SHA256={hashlib.sha256(certificate_data).hexdigest().upper()}",
                     f"-DTEST_CERT_THUMBPRINT={hashlib.sha1(certificate_data).hexdigest().upper()}"])
    return args


def package(stage: Path, out: Path, makensis: str, notification_package: Path | None,
            test_certificate: Path | None = None) -> None:
    for name in REQUIRED:
        if not (stage / name).is_file():
            raise ValueError(f"Incomplete runtime: {name}")
    require_x64(stage / "SekaiSoundbar.exe")
    version = (stage / "VERSION.txt").read_text(encoding="ascii").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"Invalid package version: {version}")
    identity_args = notification_identity_args(stage / "SekaiSoundbar.exe", notification_package, version,
                                               test_certificate)
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
    if notification_package is None:
        with zipfile.ZipFile(portable, "w", zipfile.ZIP_DEFLATED) as archive:
            for file in sorted([*files, manifest]):
                archive.write(file, f"{stem}/{file.relative_to(stage).as_posix()}")
        with zipfile.ZipFile(portable) as archive:
            bad = archive.testzip()
            if bad:
                raise ValueError(f"Corrupt ZIP entry: {bad}")
        print(f"{checksum(portable)}  {portable.name}")

    subprocess.run([
        makensis, "-V2", "-INPUTCHARSET", "UTF8", f"-DVERSION={version}",
        f"-DPAYLOAD_LICENSE={stage / 'LICENSE'}", f"-DPAYLOAD_FILES={stage / '*'}",
        *identity_args, f"-DSETUP={setup}", str(HERE / "installer.nsi"),
    ], check=True)
    print(f"{checksum(setup)}  {setup.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--makensis", default="makensis")
    parser.add_argument("--notification-package", type=Path,
                        help="Signed external-location MSIX matching the staged executable")
    parser.add_argument("--test-certificate", type=Path,
                        help="Public DER certificate to offer to install in LocalMachine\\TrustedPeople")
    parser.add_argument("--qt-archives", type=Path)
    parser.add_argument("--qt-version", default="6.8.2")
    args = parser.parse_args()
    stage = args.stage.resolve()
    out = args.out.resolve()
    if out == stage or out.is_relative_to(stage):
        parser.error("--out must be outside --stage")
    if args.qt_archives:
        stage_qt_notices(args.qt_archives, stage, args.qt_version)
    identity = args.notification_package.resolve() if args.notification_package else None
    if identity and identity.is_relative_to(stage):
        parser.error("--notification-package must be outside --stage")
    certificate = args.test_certificate.resolve() if args.test_certificate else None
    if certificate and certificate.is_relative_to(stage):
        parser.error("--test-certificate must be outside --stage")
    package(stage, out, args.makensis, identity, certificate)


if __name__ == "__main__":
    main()
