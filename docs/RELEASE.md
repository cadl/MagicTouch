# Xcode Cloud → GitHub DMG release

This workflow uses Apple's cloud-managed signing and notarization. GitHub downloads
the **stapled, notarized application**, packages it into an **unsigned DMG**, and
uploads it to a **draft** Release. It never publishes a Release automatically and
never needs a Developer ID `.p12` or Apple signing private key.

The DMG includes `MagicTouch.app` and an `Applications` shortcut. The app retains
its signature and notarization ticket; the outer DMG is not signed or notarized.
Public release still requires a real download/install check on a separate Mac.

## One-time setup

### 1. Put the workflow on GitHub

The repository is `https://github.com/cadl/MagicTouch`. Commit and push this
implementation to the default branch before enabling releases. Do not use an old
tag that predates `ci_scripts/` and the shared `MagicTouch` scheme.

### 2. Enable Xcode Cloud in Xcode

Open `MagicTouch.xcodeproj`, select the shared **MagicTouch** scheme, and start
Xcode Cloud setup from Xcode. Sign in with your Apple Developer account, connect
the GitHub repository, and grant Apple access to this repository. Follow any
App Store Connect app-record setup required by Xcode. Outside-store notarization
does not require submitting the app for App Store review.

If Xcode requires a team during initial setup, select your team locally. Do not
commit the resulting personal `DEVELOPMENT_TEAM` edits. The cloud post-clone hook
will set the team in the temporary checkout instead.

Create a dedicated distribution workflow:

- Use the shared **MagicTouch** scheme and **Release** configuration.
- Configure exactly one **macOS Archive** action for distribution outside the
  App Store, and add the **Notarize** post-action. Restrict workflow editing and
  enable clean builds as required by Apple. Do not use a development-only export.
- Use a supported Xcode version that builds this project and Sparkle. Check that
  the archive includes the architectures you intend to support.
- Prefer manual/API starts only. Remove automatic branch/tag triggers from this
  release workflow to avoid duplicate builds. A separate CI workflow can test PRs.
- Set the workflow environment variable `MAGICTOUCH_TEAM_ID` to your 10-character
  Apple team ID. This is an identifier, not a signing private key.
- Ensure Xcode runs `ci_scripts/ci_post_clone.sh`. It injects the team, the source
  commit and cloud build number before compilation. It also sets
  `CURRENT_PROJECT_VERSION` from `CI_BUILD_NUMBER`; choose a starting cloud build
  number greater than every version already distributed to users.
- Run an initial build and confirm its Artifacts contain a notarized app. This
  also verifies the account's cloud-managed Developer ID signing permissions.

Record the workflow ID. It can be obtained through the App Store Connect API by
listing Xcode Cloud products and then the workflows for the product:
`GET /v1/ciProducts` and `GET /v1/ciProducts/{id}/workflows`.

### 3. Configure the GitHub `release` environment

In repository **Settings → Environments**, create an environment named `release`.
Restrict deployments to the default branch and require a trusted reviewer where
supported. The release workflow must be dispatched from that branch. Protect the
branch and version tags against unreviewed changes and force updates.

Add this **environment secret**:

| Secret | Value |
| --- | --- |
| `ASC_PRIVATE_KEY` | Full PEM text of an App Store Connect **team API key** (`.p8`) |

Add these **environment variables**:

| Variable | Value |
| --- | --- |
| `ASC_KEY_ID` | The API key identifier |
| `ASC_ISSUER_ID` | The team API issuer ID |
| `XCODE_CLOUD_WORKFLOW_ID` | Dedicated release workflow ID |
| `APPLE_TEAM_ID` | Expected application signing team; same as `MAGICTOUCH_TEAM_ID` |

Use an API key with the least role/access that permits reading the repository,
starting this workflow and reading its build artifacts. Confirm those operations
before using it for releases. The API key is sensitive even though it is **not**
your Developer ID signing key. Never commit it, print it, or put it in a build
artifact. Individual API keys use a different JWT format and are not supported by
this implementation.

The workflow uses its automatic `GITHUB_TOKEN` to create drafts and upload
attachments; no personal GitHub token is necessary. The Apple API secret is
available only to the cloud-build step. Packaging does not receive that secret.

## Prepare a version

1. Set `MARKETING_VERSION` to the intended version (for example `1.0.1`), commit
   and merge it to the default branch. The cloud build number supplies the
   monotonically increasing `CFBundleVersion`.
2. Create and push a tag that exactly matches that version, for example `v1.0.1`.
   Tags `v1.0` and `v1.0.1` are supported; prerelease suffixes are not supported yet.
3. Open **Actions → Prepare DMG release → Run workflow**. Select the default
   branch and enter the tag. Approve the protected environment if required.
4. The workflow creates/finds the draft, resolves the tag's commit, starts Xcode
   Cloud and waits up to 90 minutes for a successful notarized artifact. It may
   wait another five minutes for a new tag to become visible to Apple.
5. On the macOS runner it verifies the app's bundle ID, version, embedded source
   commit, Developer ID team, code signature, notarization ticket and Gatekeeper
   assessment. It creates the DMG, mounts it read-only and repeats the app checks.
6. The draft receives `MagicTouch-<version>.dmg`, `SHA256SUMS` and `release.json`.
   The JSON contains public provenance (commit, cloud build/artifact IDs, team,
   app version, checksum); it contains no tokens or signed download URLs.
7. Edit release notes, download and test the DMG, and only then click **Publish
   release**. Do not publish the draft while the workflow is still running.

The workflow runs trusted scripts from the default branch, not scripts checked
out from the input tag. The tag must be on that branch's history. Still review
the tagged application and its cloud build hooks: Xcode Cloud will execute those
hooks and sign that source code.

## Failure and retry behavior

- A failed/canceled cloud build stops the workflow; an ordinary archive is never
  used as a fallback for a missing notarized artifact.
- A failure leaves the Release as a draft. It never silently publishes an empty
  version or modifies an existing public Release.
- Existing assets are not overwritten. After a partially successful upload,
  inspect and remove the incomplete draft assets before rerunning.
- A moved tag or a different signed source commit causes a failure.
- Canceling the GitHub run does not cancel an already-started Apple build. Cancel
  that build in Xcode Cloud if needed. After an API timeout, inspect Apple before
  rerunning, since the initial request may have created a build.
- The workflow refreshes its short-lived Apple JWT while polling. It retries
  transient read failures, but does not automatically repeat build-creating POSTs.
- A missing artifact after successful compilation usually means notarization is
  absent, failed, still pending, or the wrong workflow/export was selected.
- A version mismatch means the tag does not match the app's `MARKETING_VERSION`.
- If Gatekeeper or ticket validation fails, investigate it rather than bypassing
  the verification step. The pipeline intentionally does not re-sign the app.

## Sparkle updates

This pipeline prepares GitHub download releases only. It does **not** publish an
appcast or hold the Sparkle private key. For automatic updates, follow
[UPDATES.md](UPDATES.md): configure the feed/public key in the Release build,
sign the final update archive, and publish the appcast only after release assets
are public and their URLs have been tested. Unconfigured builds keep updates
disabled.

## Local validation

The release-tool tests use fake API responses and a disposable signing key, not
Apple credentials:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/release/tests -v
```

On macOS, this also checks actual DMG creation/mounting with a temporary fixture;
it does not substitute for an end-to-end Apple signing/notarization run. Python
3.9 or later, OpenSSL, Git and the GitHub CLI are required; hosted macOS runners
provide these tools. No third-party Python packages are required.

## References

- [Apple: distribution and notarization workflow](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)
- [Apple: custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [Apple API: start a build](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-cibuildruns)
- [Apple API: artifact types and download URLs](https://developer.apple.com/documentation/appstoreconnectapi/ciartifact/attributes-data.dictionary)
