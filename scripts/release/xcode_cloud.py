"""Start one Xcode Cloud build and download only its notarized artifact."""
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

from common import OUTPUT, read_manifest, required, write_manifest

API_ROOT = "https://api.appstoreconnect.apple.com"


def base64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def jose_signature(der):
    """Convert OpenSSL's P-256 ASN.1 signature into JWT's fixed-width R || S."""
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2:
        raise RuntimeError("Invalid ES256 signature encoding.")
    offset, values = 2, []
    for _ in range(2):
        if der[offset] != 0x02:
            raise RuntimeError("Invalid ES256 integer encoding.")
        size = der[offset + 1]
        value = der[offset + 2:offset + 2 + size].lstrip(b"\0")
        if not value or len(value) > 32:
            raise RuntimeError("Signing key must use the P-256 curve.")
        values.append(value.rjust(32, b"\0"))
        offset += size + 2
    if offset != len(der):
        raise RuntimeError("Invalid ES256 signature length.")
    return b"".join(values)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        return None


class HTTPSRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        if urllib.parse.urlparse(newurl).scheme != "https":
            raise RuntimeError("Refusing a non-HTTPS artifact redirect.")
        return super().redirect_request(request, fp, code, message, headers, newurl)


class AppleAPI:
    def __init__(self, key_path, key_id, issuer):
        self.key_path, self.key_id, self.issuer = key_path, key_id, issuer
        self.token = None
        self.expires = 0
        self.opener = urllib.request.build_opener(NoRedirect())

    def jwt(self):
        now = int(time.time())
        if self.token and now < self.expires - 60:
            return self.token
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {"iss": self.issuer, "iat": now - 30, "exp": now + 900, "aud": "appstoreconnect-v1"}
        unsigned = ".".join(base64url(json.dumps(part, separators=(",", ":")).encode())
                            for part in (header, payload))
        result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(self.key_path)],
                                input=unsigned.encode(), capture_output=True)
        if result.returncode:
            raise RuntimeError("Unable to sign Apple API token; check ASC_PRIVATE_KEY (P-256 .p8 PEM).")
        self.token = unsigned + "." + base64url(jose_signature(result.stdout))
        self.expires = now + 900
        return self.token

    def request(self, path, payload=None):
        url = path if path.startswith("https://") else API_ROOT + path
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com":
            raise RuntimeError("Refusing to send Apple credentials to an unexpected host.")
        # GETs are safe to retry. Never automatically retry a build-creating POST.
        attempts = 1 if payload is not None else 4
        for attempt in range(attempts):
            request = urllib.request.Request(url, data=json.dumps(payload).encode() if payload is not None else None,
                headers={"Authorization": "Bearer " + self.jwt(), "Content-Type": "application/json"})
            try:
                with self.opener.open(request, timeout=60) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                retry = error.code == 429 or error.code >= 500
                if not retry or attempt == attempts - 1:
                    raise RuntimeError(f"Apple API failed (HTTP {error.code}); check access and Xcode Cloud configuration.") from None
            except (urllib.error.URLError, TimeoutError):
                if attempt == attempts - 1:
                    raise RuntimeError("Apple API network failure. Check Xcode Cloud before retrying; a build may have started.") from None
            time.sleep(min(30, 2 ** (attempt + 1)))

    def items(self, path):
        for _ in range(100):
            page = self.request(path)
            yield from page["data"]
            path = page.get("links", {}).get("next")
            if not path:
                return
        raise RuntimeError("Apple API pagination exceeded the expected limit.")


def find_tag(api, repository_id, tag, timeout=300):
    deadline = time.monotonic() + timeout
    while True:
        matches = [item for item in api.items(f"/v1/scmRepositories/{repository_id}/gitReferences?limit=200")
                   if item["attributes"].get("canonicalName") == f"refs/tags/{tag}"
                   and item["attributes"].get("kind") == "TAG"
                   and not item["attributes"].get("isDeleted")]
        if len(matches) == 1:
            return matches[0]["id"]
        if len(matches) > 1 or time.monotonic() >= deadline:
            raise RuntimeError("Xcode Cloud has not indexed a unique matching tag; check repository access and retry later.")
        time.sleep(15)


def wait_for_artifact(api, build_id, expected_commit, timeout=5400):
    deadline = time.monotonic() + timeout
    previous = None
    while time.monotonic() < deadline:
        build = api.request(f"/v1/ciBuildRuns/{build_id}")["data"]
        attrs = build["attributes"]
        # Apple may omit sourceCommit for non-PR builds. The signed app embeds
        # its checkout SHA, which is always checked during packaging as well.
        source_sha = (attrs.get("sourceCommit") or {}).get("commitSha")
        if source_sha and source_sha != expected_commit:
            raise RuntimeError("Xcode Cloud built a different commit than the requested tag.")
        state = (attrs.get("executionProgress"), attrs.get("completionStatus"))
        if state != previous:
            print(f"Xcode Cloud {build_id}: {state[0]} / {state[1]}", flush=True)
            previous = state
        if state[0] == "COMPLETE":
            if state[1] != "SUCCEEDED":
                raise RuntimeError(f"Xcode Cloud did not succeed: {state[1]}.")
            artifacts = []
            for action in api.items(f"/v1/ciBuildRuns/{build_id}/actions?limit=200"):
                if action["attributes"].get("actionType") != "ARCHIVE":
                    continue
                artifacts.extend(item for item in api.items(f"/v1/ciBuildActions/{action['id']}/artifacts?limit=200")
                                 if item["attributes"].get("fileType") == "STAPLED_NOTARIZED_ARCHIVE")
            if len(artifacts) > 1:
                raise RuntimeError("More than one notarized archive found. Configure exactly one macOS Archive action.")
            if artifacts:
                return artifacts[0]
            # Notarization artifacts may become visible after the archive completes.
        time.sleep(30)
    raise RuntimeError("Timed out waiting for notarized output. No unnotarized fallback is allowed. Check the Apple build before retrying.")


def download_artifact(artifact, destination):
    attrs = artifact["attributes"]
    url = attrs["downloadUrl"]
    if urllib.parse.urlparse(url).scheme != "https":
        raise RuntimeError("Artifact download URL must use HTTPS.")
    try:
        # Deliberately do not attach the Apple API Authorization header.
        opener = urllib.request.build_opener(HTTPSRedirect())
        with opener.open(url, timeout=120) as response, destination.open("wb") as handle:
            shutil.copyfileobj(response, handle)
    except (urllib.error.URLError, TimeoutError):
        raise RuntimeError("Artifact download failed. Its signed download URL is omitted from logs.") from None
    if attrs.get("fileSize") is not None and destination.stat().st_size != attrs["fileSize"]:
        raise RuntimeError("Downloaded artifact size does not match Apple's metadata.")


def main():
    manifest = read_manifest()
    workflow = required("XCODE_CLOUD_WORKFLOW_ID")
    key_id, issuer = required("ASC_KEY_ID"), required("ASC_ISSUER_ID")
    with tempfile.TemporaryDirectory(prefix="magictouch-asc-") as temporary:
        key_path = Path(temporary) / "AuthKey.p8"
        key_path.touch(mode=0o600)
        key_path.write_text(required("ASC_PRIVATE_KEY") + "\n")
        api = AppleAPI(key_path, key_id, issuer)
        repository = api.request(f"/v1/ciWorkflows/{urllib.parse.quote(workflow, safe='')}/repository")["data"]
        attrs = repository["attributes"]
        apple_repo = f"{attrs['ownerName']}/{attrs['repositoryName']}"
        if apple_repo.lower() != manifest["repository"].lower():
            raise RuntimeError("Xcode Cloud workflow is connected to a different repository.")
        ref_id = find_tag(api, repository["id"], manifest["tag"])
        build = api.request("/v1/ciBuildRuns", {"data": {
            "type": "ciBuildRuns", "attributes": {"clean": True},
            "relationships": {
                "workflow": {"data": {"type": "ciWorkflows", "id": workflow}},
                "sourceBranchOrTag": {"data": {"type": "scmGitReferences", "id": ref_id}}
            }}})["data"]
        manifest.update(xcode_cloud_workflow_id=workflow, xcode_cloud_build_id=build["id"])
        write_manifest(manifest)
        print(f"Started Xcode Cloud build: {build['id']}", flush=True)
        artifact = wait_for_artifact(api, build["id"], manifest["commit"])
        # Read again to obtain a fresh signed download URL.
        artifact = api.request(f"/v1/ciArtifacts/{artifact['id']}")["data"]
        if artifact["attributes"].get("fileType") != "STAPLED_NOTARIZED_ARCHIVE":
            raise RuntimeError("Unexpected artifact type.")
        download_artifact(artifact, OUTPUT / "notarized.zip")
        manifest["xcode_cloud_artifact_id"] = artifact["id"]
        write_manifest(manifest)
        print("Downloaded notarized artifact.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError, ValueError) as error:
        sys.exit(f"Xcode Cloud release failed: {error}")
