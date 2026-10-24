"""Shared release validation; no third-party Python dependencies."""
import json
import os
from pathlib import Path
import re
import subprocess

OUTPUT = Path("build/release")


def required(name):
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required configuration: {name}")
    return value


def version_for_tag(tag):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+(?:\.[0-9]+)?", tag):
        raise RuntimeError("Use a release tag such as v1.0 or v1.0.1 (no prerelease suffix).")
    return tag[1:]


def validate_team(team):
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise RuntimeError("APPLE_TEAM_ID must be a 10-character Apple team identifier.")
    return team


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def read_manifest():
    return json.loads((OUTPUT / "release.json").read_text())


def write_manifest(value):
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "release.json").write_text(json.dumps(value, indent=2) + "\n")
