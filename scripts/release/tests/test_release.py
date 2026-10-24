import base64
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import common
import github_release
import package_dmg
import xcode_cloud

spec = importlib.util.spec_from_file_location("configure_build", SCRIPTS.parents[1] / "ci_scripts/configure_build.py")
configure_build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure_build)


class FakeAPI:
    def __init__(self, status="SUCCEEDED", artifacts=None, sha="a" * 40):
        self.status, self.artifacts, self.sha = status, artifacts or [], sha

    def request(self, path, payload=None):
        return {"data": {"attributes": {"executionProgress": "COMPLETE", "completionStatus": self.status,
                                       "sourceCommit": {"commitSha": self.sha}}}}

    def items(self, path):
        if "/actions?" in path:
            return iter([{"id": "archive-action", "attributes": {"actionType": "ARCHIVE"}}])
        return iter(self.artifacts)


class ReleaseTests(unittest.TestCase):
    def test_tag_rejects_shell_syntax_and_non_versions(self):
        for tag in ["main", "v1.0;echo bad", "v1.0\nother", "../v1.0", "v1.0-beta"]:
            with self.subTest(tag=tag), self.assertRaises(RuntimeError):
                common.version_for_tag(tag)
        self.assertEqual(common.version_for_tag("v1.2.3"), "1.2.3")

    def test_failed_cloud_build_never_returns_artifact(self):
        for status in ["FAILED", "CANCELED", "ERRORED", "SKIPPED"]:
            with self.subTest(status=status), self.assertRaises(RuntimeError):
                xcode_cloud.wait_for_artifact(FakeAPI(status=status), "build", "a" * 40, timeout=1)

    def test_mismatched_source_commit_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "different commit"):
            xcode_cloud.wait_for_artifact(FakeAPI(sha="b" * 40), "build", "a" * 40, timeout=1)

    def test_only_notarized_archive_is_accepted(self):
        raw = {"id": "raw", "attributes": {"fileType": "ARCHIVE"}}
        signed = {"id": "signed", "attributes": {"fileType": "STAPLED_NOTARIZED_ARCHIVE"}}
        api = FakeAPI(artifacts=[raw, signed])
        self.assertEqual(xcode_cloud.wait_for_artifact(api, "build", "a" * 40, timeout=1)["id"], "signed")

    def test_missing_notarization_times_out_without_raw_fallback(self):
        api = FakeAPI(artifacts=[{"id": "raw", "attributes": {"fileType": "ARCHIVE"}}])
        with patch.object(xcode_cloud.time, "monotonic", side_effect=[0, 0, 2]), patch.object(xcode_cloud.time, "sleep"):
            with self.assertRaisesRegex(RuntimeError, "No unnotarized fallback"):
                xcode_cloud.wait_for_artifact(api, "build", "a" * 40, timeout=1)

    def test_ambiguous_artifacts_are_rejected(self):
        artifact = {"id": "a", "attributes": {"fileType": "STAPLED_NOTARIZED_ARCHIVE"}}
        with self.assertRaisesRegex(RuntimeError, "More than one"):
            xcode_cloud.wait_for_artifact(FakeAPI(artifacts=[artifact, artifact]), "build", "a" * 40, timeout=1)

    def test_token_signature_verifies_with_openssl(self):
        # Use a fresh disposable key, never a developer credential.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key, public = root / "key.pem", root / "public.pem"
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", str(key)], check=True)
            subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(public)], check=True)
            token = xcode_cloud.AppleAPI(key, "test-key", "test-issuer").jwt()
            header, payload, signature = token.split(".")
            self.assertEqual(json.loads(base64.urlsafe_b64decode(payload + "=="))["aud"], "appstoreconnect-v1")
            raw = base64.urlsafe_b64decode(signature + "==")
            integers = []
            for value in [raw[:32], raw[32:]]:
                value = value.lstrip(b"\0") or b"\0"
                if value[0] & 0x80:
                    value = b"\0" + value
                integers.append(b"\x02" + bytes([len(value)]) + value)
            body = b"".join(integers)
            (root / "signature").write_bytes(b"\x30" + bytes([len(body)]) + body)
            result = subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(public), "-signature", str(root / "signature")],
                                    input=(header + "." + payload).encode(), capture_output=True)
            self.assertEqual(result.returncode, 0)

    def test_api_rejects_external_host_before_loading_credentials(self):
        api = xcode_cloud.AppleAPI(Path("does-not-exist"), "test", "test")
        with self.assertRaisesRegex(RuntimeError, "unexpected host"):
            api.request("https://example.com/steal")

    def test_published_release_is_never_modified(self):
        with patch.object(github_release, "api", return_value={"draft": False}):
            with self.assertRaisesRegex(RuntimeError, "already published"):
                github_release.check_release("owner/repo", "v1.0")

    def test_api_permissions_failure_is_not_treated_as_missing_release(self):
        result = subprocess.CompletedProcess([], 1, "HTTP/2.0 403 Forbidden\n\n{}", "")
        with patch.object(github_release.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "HTTP 403"):
                github_release.api("repos/owner/repo/releases/tags/v1.0")

    def test_annotated_tag_is_peeled_to_commit(self):
        with patch.object(github_release, "api", side_effect=[
            {"object": {"type": "tag", "sha": "tag-sha"}},
            {"object": {"type": "commit", "sha": "commit-sha"}}
        ]):
            self.assertEqual(github_release.remote_commit("owner/repo", "v1.0"), "commit-sha")

    def test_archive_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "bad.zip"
            with zipfile.ZipFile(archive, "w") as handle:
                handle.writestr("../../outside", "bad")
            with self.assertRaisesRegex(RuntimeError, "Unsafe path"):
                package_dmg.check_archive(archive)

    def test_archive_cannot_write_through_symlink_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "links.zip"
            with zipfile.ZipFile(archive, "w") as handle:
                link = zipfile.ZipInfo("alias")
                link.create_system = 3
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                handle.writestr(link, "real")
                handle.writestr("alias/file", "unexpected write")
            with self.assertRaisesRegex(RuntimeError, "symlink directory"):
                package_dmg.check_archive(archive)

    def test_app_requires_version_bundle_id_and_signed_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "MagicTouch.app"
            (app / "Contents").mkdir(parents=True)
            manifest = {"version": "1.2", "commit": "a" * 40}
            info = {"CFBundleIdentifier": "com.lollipush.MagicTouch", "CFBundleShortVersionString": "1.2",
                    "MagicTouchSourceCommit": "a" * 40, "MagicTouchCloudBuildNumber": "3", "CFBundleVersion": "3"}
            for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "MagicTouchSourceCommit"]:
                with self.subTest(key=key):
                    altered = {**info, key: "wrong"}
                    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(altered))
                    with self.assertRaises(RuntimeError):
                        package_dmg.app_info(app, manifest)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            self.assertEqual(package_dmg.app_info(app, manifest)["CFBundleVersion"], "3")

    @unittest.skipUnless(sys.platform == "darwin", "DMG tools require macOS")
    def test_dmg_preserves_app_contents_and_applications_shortcut(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "MagicTouch.app"
            (app / "Contents").mkdir(parents=True)
            (app / "Contents/fixture").write_bytes(b"unchanged app bytes")
            (app / "Contents/alias").symlink_to("fixture")

            def verify_fixture(copied, manifest):
                self.assertEqual((copied / "Contents/fixture").read_bytes(), b"unchanged app bytes")
                self.assertTrue((copied / "Contents/alias").is_symlink())

            # Only signature/notarization validation is mocked; real disk image
            # creation, read-only mounting, and Applications shortcut checks run.
            with patch.object(package_dmg, "verify_app", side_effect=verify_fixture) as verify:
                package_dmg.create_dmg(app, root / "test.dmg", {})
                self.assertEqual(verify.call_count, 2)
            self.assertTrue((root / "test.dmg").is_file())

    def test_cloud_config_only_changes_disposable_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "MagicTouch.xcodeproj").mkdir()
            (root / "MagicTouch").mkdir()
            project = root / "MagicTouch.xcodeproj/project.pbxproj"
            project.write_text('DEVELOPMENT_TEAM = "";\nCURRENT_PROJECT_VERSION = 1;\n')
            (root / "MagicTouch/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "com.lollipush.MagicTouch"}))
            with patch.object(configure_build.subprocess, "check_output", return_value="a" * 40):
                configure_build.configure(root, "TESTTEAM01", "42")
            self.assertIn("CURRENT_PROJECT_VERSION = 42;", project.read_text())
            self.assertIn("DEVELOPMENT_TEAM = TESTTEAM01;", project.read_text())
            info = plistlib.loads((root / "MagicTouch/Info.plist").read_bytes())
            self.assertEqual(info["MagicTouchSourceCommit"], "a" * 40)


if __name__ == "__main__":
    unittest.main()
