"""Inject public build metadata and team configuration into the cloud checkout."""
import os
from pathlib import Path
import plistlib
import re
import subprocess


def configure(root, team, build_number):
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise RuntimeError("Set MAGICTOUCH_TEAM_ID in the Xcode Cloud workflow environment.")
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise RuntimeError("Xcode Cloud CI_BUILD_NUMBER must be a positive integer.")
    sha = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    if not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise RuntimeError("Unable to determine the source commit.")
    project = root / "MagicTouch.xcodeproj/project.pbxproj"
    text, count = re.subn(r'DEVELOPMENT_TEAM = (?:"[^"]*"|[A-Z0-9]+);',
                          f"DEVELOPMENT_TEAM = {team};", project.read_text())
    if not count:
        raise RuntimeError("No team build settings found.")
    # This change exists only in the temporary cloud checkout. Never commit it.
    text = re.sub(r"CURRENT_PROJECT_VERSION = [^;]+;",
                  f"CURRENT_PROJECT_VERSION = {build_number};", text)
    project.write_text(text)
    info_path = root / "MagicTouch/Info.plist"
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    info["MagicTouchSourceCommit"] = sha
    info["MagicTouchCloudBuildNumber"] = build_number
    with info_path.open("wb") as handle:
        plistlib.dump(info, handle, sort_keys=False)
    print(f"Configured Xcode Cloud build {build_number} for commit {sha}.")


if __name__ == "__main__":
    configure(Path(os.environ["CI_PRIMARY_REPOSITORY_PATH"]),
              os.environ.get("MAGICTOUCH_TEAM_ID", ""), os.environ.get("CI_BUILD_NUMBER", ""))
