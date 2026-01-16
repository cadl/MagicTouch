# Build and distribution guide

## Local development

Install Xcode and open `MagicTouch.xcodeproj`. Select your own development team
under Signing & Capabilities when running a signed build. Keep personal signing
configuration out of commits. The app requires macOS 14 or later and Accessibility
permission for click simulation. It uses the private MultitouchSupport framework;
compatibility should be checked on each supported macOS release.

The project builds directly with Xcode; no additional build automation tool is required.
For a compile-only check without a signing identity:

```sh
xcodebuild -project MagicTouch.xcodeproj -scheme MagicTouch \
  -configuration Debug -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build
```

For local signed builds, provide your own team through the `DEVELOPMENT_TEAM`
build setting, or configure it in Xcode. To run unit tests after configuring signing:

```sh
xcodebuild test -project MagicTouch.xcodeproj -scheme MagicTouch \
  -destination 'platform=macOS' -only-testing:MagicTouchTests
```

Debug and Release builds use different bundle identifiers. Accessibility permission
may need to be granted separately for each application.

## Public distribution

Use a Developer ID Application certificate for distribution outside the Mac App
Store. A personal Apple Developer account can be used; the signed application
exposes the certificate's developer identity. Removing a name from source files
does not anonymize the application signature.

The release process must archive the Release configuration, export with Developer
ID signing, notarize with Apple, staple the ticket, verify the final artifact, and
package it for distribution. Signing alone does not complete notarization.
Use Xcode's archive/distribution workflow or automate the equivalent steps in CI.
There is currently no automated DMG, notarization, or GitHub Release workflow in
this repository.

Keep certificates with private keys, certificate passwords, Apple credentials,
and Sparkle private keys outside Git. For CI, use GitHub Actions Secrets and a
temporary keychain. Supply the team and signing identity through build settings.
Do not expose release credentials to untrusted pull requests.

See [docs/UPDATES.md](docs/UPDATES.md) for Sparkle release requirements, and
[Apple's distribution documentation](https://developer.apple.com/documentation/xcode/distributing-your-app-outside-the-mac-app-store)
for signing and notarization.
