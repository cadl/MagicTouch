# Repository Guidelines

## Project Structure & Module Organization

- `MagicTouch/`: App source code.
  - `Core/`: Input/tap detection and click simulation (includes bridging headers).
  - `Services/`: Settings, permissions, and launch-at-login helpers.
  - `MenuBar/`: Menu bar UI/controller.
  - `Views/`: SwiftUI views for Settings/Status window.
  - `Assets.xcassets/`: App icons and colors.
- `MagicTouchTests/`: Unit tests (Swift Testing).
- `MagicTouchUITests/`: UI tests (XCTest).
- `MagicTouch.xcodeproj/`: Xcode project configuration.

## Build, Test, and Development Commands

- `open MagicTouch.xcodeproj`: Open the project in Xcode.
- `xcodebuild -project MagicTouch.xcodeproj -scheme MagicTouch build`: Build the app from the CLI.
- `xcodebuild test -project MagicTouch.xcodeproj -scheme MagicTouch -destination 'platform=macOS'`: Run unit + UI tests.
- `xcodebuild test -project MagicTouch.xcodeproj -scheme MagicTouch -destination 'platform=macOS' -only-testing:MagicTouchTests`: Run unit tests only.

## Coding Style & Naming Conventions

- Swift: 4-space indentation, use Xcode’s default formatting.
- Types/files: `PascalCase` (e.g., `PermissionManager.swift`); methods/vars: `lowerCamelCase`.
- Keep code in the closest folder to its responsibility (`Core`, `Services`, `Views`, `MenuBar`) and prefer `private` by default.

## Testing Guidelines

- Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect(...)`) in `MagicTouchTests/`.
- UI tests use XCTest (`XCTestCase`, `test…` methods) in `MagicTouchUITests/`.
- Name tests for behavior (e.g., `@Test func startsMonitoringWhenPermissionGranted() async throws`).

## Commit & Pull Request Guidelines

- Use short, imperative English subjects (e.g., `Fix menu refresh on permission change`).
- PRs should include: purpose/summary, steps to verify, and screenshots for UI/menu bar changes.
- Before opening a PR: run `xcodebuild test …` and avoid committing generated files (e.g., `DerivedData/`).

## Security & Configuration Tips

- This app relies on macOS Accessibility permission for click simulation; document any new permission requirements and keep prompts user-friendly.

- Keep personal signing configuration and credentials out of Git; see `BUILD_GUIDE.md`.
