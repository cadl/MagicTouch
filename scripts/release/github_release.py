"""Create a draft and upload assets; never publish or overwrite released assets."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote

from common import OUTPUT, read_manifest, required, run, validate_team, version_for_tag, write_manifest


def api(path):
    # Parse status separately: only a real 404 means a release does not exist.
    result = subprocess.run(["gh", "api", "--include", path], capture_output=True, text=True)
    header, _, body = result.stdout.partition("\n\n")
    match = re.search(r"^HTTP/\S+ (\d+)", header)
    status = int(match.group(1)) if match else 0
    if status == 404:
        return None
    if result.returncode or status != 200:
        raise RuntimeError(f"GitHub API request failed (HTTP {status}); check repository permissions.")
    return json.loads(body)


def remote_commit(repo, tag):
    ref = api(f"repos/{repo}/git/ref/tags/{quote(tag, safe='')}")
    if ref is None:
        raise RuntimeError("The release tag must already exist on GitHub.")
    obj = ref["object"]
    # Peel annotated tags, including nested tags, with a bounded traversal.
    for _ in range(10):
        if obj["type"] == "commit":
            return obj["sha"]
        if obj["type"] != "tag":
            break
        obj = api(f"repos/{repo}/git/tags/{obj['sha']}")["object"]
    raise RuntimeError("Tag does not resolve to a commit.")


def check_release(repo, tag):
    release = api(f"repos/{repo}/releases/tags/{quote(tag, safe='')}")
    if release and not release["draft"]:
        raise RuntimeError("This release is already published; refusing to change it.")
    return release


def prepare():
    tag = required("RELEASE_TAG")
    version = version_for_tag(tag)
    team = validate_team(required("EXPECTED_APPLE_TEAM_ID"))
    repo = required("GITHUB_REPOSITORY")
    sha = remote_commit(repo, tag)
    local_sha = run("git", "rev-parse", f"refs/tags/{tag}^{{commit}}")
    if local_sha != sha:
        raise RuntimeError("The remote tag differs from the checked-out tag. Restart the workflow.")
    if subprocess.run(["git", "merge-base", "--is-ancestor", sha, "HEAD"]).returncode:
        raise RuntimeError("Release tag must point to a commit on the checked-out default branch.")
    for path in ["ci_scripts/ci_post_clone.sh", "ci_scripts/configure_build.py",
                 "MagicTouch.xcodeproj/xcshareddata/xcschemes/MagicTouch.xcscheme"]:
        subprocess.run(["git", "cat-file", "-e", f"{sha}:{path}"], check=True)
    release = check_release(repo, tag)
    if not release:
        notes = OUTPUT / "notes.md"
        OUTPUT.mkdir(parents=True, exist_ok=True)
        notes.write_text(f"MagicTouch {version}\n\nRelease preparation is in progress.\n")
        subprocess.run(["gh", "release", "create", tag, "--repo", repo, "--draft",
                        "--verify-tag", "--title", f"MagicTouch {version}",
                        "--notes-file", str(notes)], check=True)
        release = check_release(repo, tag)
    names = {asset["name"] for asset in release["assets"]}
    expected = {f"MagicTouch-{version}.dmg", "SHA256SUMS", "release.json"}
    if names & expected:
        raise RuntimeError("Draft already contains release assets. Review/remove them before retrying; nothing was overwritten.")
    write_manifest({"tag": tag, "version": version, "commit": sha, "repository": repo,
                    "release_id": release["id"], "apple_team_id": team})
    print(f"Prepared draft for {tag} at {sha}.")


def upload():
    manifest = read_manifest()
    repo, tag = manifest["repository"], manifest["tag"]
    release = check_release(repo, tag)
    if not release or release["id"] != manifest["release_id"]:
        raise RuntimeError("The original draft release was removed or replaced.")
    if remote_commit(repo, tag) != manifest["commit"]:
        raise RuntimeError("Release tag moved while building. Refusing to upload.")
    files = [OUTPUT / f"MagicTouch-{manifest['version']}.dmg", OUTPUT / "SHA256SUMS", OUTPUT / "release.json"]
    for path in files:
        if not path.is_file():
            raise RuntimeError(f"Missing release asset: {path.name}")
    if {p.name for p in files} & {a["name"] for a in release["assets"]}:
        raise RuntimeError("Assets already exist; refusing to overwrite them.")
    subprocess.run(["gh", "release", "upload", tag, "--repo", repo, *map(str, files)], check=True)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as handle:
            handle.write(f"### MagicTouch {manifest['version']} ready for review\n\n"
                         f"[Open draft release]({release['html_url']})\n\n"
                         f"Source commit: `{manifest['commit']}`\n\n"
                         "The DMG contains a signed, notarized app. The DMG itself is unsigned. "
                         "Download and test installation before publishing. Sparkle appcast publication is separate.\n")
    print("Uploaded DMG, checksums, and provenance. Release remains a draft.")


if __name__ == "__main__":
    try:
        {"prepare": prepare, "upload": upload}[sys.argv[1]]()
    except (RuntimeError, subprocess.CalledProcessError, KeyError, IndexError) as error:
        sys.exit(f"Release failed: {error}")
