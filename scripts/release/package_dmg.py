"""Package an already signed/notarized app without importing a signing identity."""
import hashlib
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

from common import OUTPUT, read_manifest, write_manifest


def check_archive(path):
    with zipfile.ZipFile(path) as archive:
        symlinks = {PurePosixPath(entry.filename) for entry in archive.infolist()
                    if stat.S_ISLNK(entry.external_attr >> 16)}
        for entry in archive.infolist():
            name = PurePosixPath(entry.filename)
            if name.is_absolute() or ".." in name.parts or "\\" in entry.filename:
                raise RuntimeError("Unsafe path in downloaded archive.")
            if any(parent in symlinks for parent in name.parents):
                raise RuntimeError("Archive writes through a symlink directory.")
            if stat.S_ISLNK(entry.external_attr >> 16):
                target = archive.read(entry).decode()
                resolved = os.path.normpath(str(name.parent / target))
                if target.startswith("/") or resolved == ".." or resolved.startswith("../"):
                    raise RuntimeError("Archive contains an external symlink.")


def app_info(app, manifest):
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    expected = {
        "CFBundleIdentifier": "com.lollipush.MagicTouch",
        "CFBundleShortVersionString": manifest["version"],
        "MagicTouchSourceCommit": manifest["commit"],
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise RuntimeError(f"App {key} does not match the requested release.")
    if not info.get("MagicTouchCloudBuildNumber"):
        raise RuntimeError("App is missing Xcode Cloud build provenance.")
    if not info.get("CFBundleVersion"):
        raise RuntimeError("App is missing its build version.")
    return info


def verify_app(app, manifest):
    info = app_info(app, manifest)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    result = subprocess.run(["codesign", "--display", "--verbose=4", str(app)],
                            capture_output=True, text=True, check=True)
    signature = result.stdout + result.stderr
    team = re.search(r"^TeamIdentifier=(.+)$", signature, re.MULTILINE)
    if not team or team.group(1) != manifest["apple_team_id"]:
        raise RuntimeError("App was signed by an unexpected Apple team.")
    if not re.search(r"^Authority=Developer ID Application:", signature, re.MULTILINE):
        raise RuntimeError("App must use Developer ID Application signing, not development or ad-hoc signing.")
    subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], check=True)
    return info


def create_dmg(app, output, manifest):
    with tempfile.TemporaryDirectory(prefix="magictouch-dmg-") as directory:
        staging = Path(directory) / "contents"
        staging.mkdir()
        copied = staging / "MagicTouch.app"
        # ditto preserves bundle permissions, symlinks and extended attributes.
        subprocess.run(["ditto", str(app), str(copied)], check=True)
        (staging / "Applications").symlink_to("/Applications")
        verify_app(copied, manifest)
        subprocess.run(["hdiutil", "create", "-volname", "MagicTouch", "-srcfolder", str(staging),
                        "-format", "UDZO", "-fs", "HFS+", str(output.resolve())], check=True)
        subprocess.run(["hdiutil", "verify", str(output)], check=True)
        mount = Path(directory) / "mounted"
        mount.mkdir()
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(output)], check=True)
        try:
            verify_app(mount / "MagicTouch.app", manifest)
            if os.readlink(mount / "Applications") != "/Applications":
                raise RuntimeError("DMG is missing the Applications shortcut.")
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True)


def main():
    manifest = read_manifest()
    archive = OUTPUT / "notarized.zip"
    check_archive(archive)
    with tempfile.TemporaryDirectory(prefix="magictouch-notarized-") as directory:
        extracted = Path(directory)
        subprocess.run(["ditto", "-x", "-k", str(archive), str(extracted)], check=True)
        for item in extracted.rglob("*"):
            if item.is_symlink() and not item.resolve().is_relative_to(extracted.resolve()):
                raise RuntimeError("Extracted archive contains an external symlink.")
        apps = list(extracted.rglob("MagicTouch.app"))
        if len(apps) != 1:
            raise RuntimeError("Expected exactly one MagicTouch.app in the notarized artifact.")
        info = verify_app(apps[0], manifest)
        output = OUTPUT / f"MagicTouch-{manifest['version']}.dmg"
        if output.exists():
            raise RuntimeError("DMG already exists; refusing to overwrite it.")
        create_dmg(apps[0], output, manifest)
    with output.open("rb") as handle:
        digest = hashlib.sha256()
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
        checksum = digest.hexdigest()
    (OUTPUT / "SHA256SUMS").write_text(f"{checksum}  {output.name}\n")
    manifest.update(app_build_version=info["CFBundleVersion"],
                    xcode_cloud_build_number=info["MagicTouchCloudBuildNumber"],
                    dmg_sha256=checksum, dmg_signed=False, app_notarized=True)
    write_manifest(manifest)
    print(f"Verified and packaged {output.name}.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        sys.exit(f"Packaging failed: {error}")
