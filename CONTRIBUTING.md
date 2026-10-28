# Working on Octo

Octo is a Swift package: an AppKit menu bar app with SwiftUI screens. Only the Xcode Command Line
Tools are needed (`xcode-select --install`).

## Everyday commands

```bash
scripts/install.sh    # tests, builds, installs into /Applications and restarts Octo
scripts/test.sh       # gesture and settings tests only
scripts/build.sh      # builds build/Octo.app (add --universal for Apple Silicon + Intel)
scripts/release.sh    # a release: checks, universal build, dist/Octo-<version>.dmg
```

`release.sh` lays out the disk image window (Finder needs to be allowed to be controlled the first
time) with a background picture drawn by `scripts/make-dmg-background.swift`: drag Octo to
Applications, and what to do when macOS blocks the first launch. `install.sh` at the top of the
repository is the one-line install from the README: it downloads the latest release with curl,
checks the signing certificate and copies Octo into Applications. Test it on a local build with
`OCTO_DMG_URL=file://$PWD/dist/Octo-<version>.dmg zsh install.sh`.

Compiler files go to `~/Library/Caches/Octo/build`, outside the project folder.

## Signing

`scripts/make-signing-identity.sh` creates a self-signed certificate in `~/.octo-signing` (once per
Mac). Builds signed with the same certificate keep their Accessibility and Screen Recording
permissions across updates. Without it, `build.sh` signs ad-hoc, and permissions have to be turned
on again after each build. Keep a private backup of `~/.octo-signing`.

## Checks without clicking around

- `build/Octo.app/Contents/MacOS/Octo --snapshot <folder>` renders every screen, the menu bar panel
  and the icons to PNG (light and dark).
- `open -n -a /Applications/Octo.app --args --self-test-keyboard-lock` checks that Clean Keyboard
  blocks a test key and scroll and frees them again; the result goes to `~/Library/Logs/Octo.log`.
- `build/Octo.app/Contents/MacOS/Octo --self-test-copy-text` checks text recognition on a drawn
  test image (no permission needed).
- `open -n -a /Applications/Octo.app --args --screenshots "$PWD/docs"` captures the real menu bar
  panel and Settings window (light and dark) for the README. It needs Octo's Screen Recording
  permission; the windows show for a few seconds.

## How it fits together

- `Sources/OctoCore` is pure logic with tests: gestures, actions, settings, and the
  `GestureRecognizer` state machine that turns finger frames into gestures.
- `Sources/Octo/Multitouch.swift` reads raw finger positions from Apple's private
  MultitouchSupport framework (the one every trackpad gesture app uses). It's loaded at runtime,
  so if macOS changes it, gestures stop instead of the app crashing.
- `Engine` feeds frames to the recognizer and runs actions. `ClickGuard` (an event tap) turns
  multi-finger clicks into actions and removes the extra click Tap to click adds to gesture taps.
  `ActionPerformer` sends shortcuts, matched to the keyboard layout, and clicks.
- `KeepAwake` holds a macOS power assertion. `KeyboardLock` blocks input with an event tap on its
  own thread. `TextGrabber` captures the selected box with ScreenCaptureKit and reads it with
  Vision.
- `AppModel` holds the state shared by the menu bar panel and the Settings window, and saves
  settings to `~/Library/Application Support/Octo/config.json`.

## Adding things

- **A tool** (like a clipboard history): add a `ToolTile` in `Sources/Octo/Views/MenuPanel.swift`,
  a case in `SettingsPage` (its own sidebar tab) in `AppModel.swift`, its page in `SettingsRoot`,
  and a card in the Guide (`GuidePage.swift`).
- **An action**: add a case to `ActionKind` in `Sources/OctoCore/Actions.swift`, give it a title,
  symbol and group, and say what it sends in `ActionResolver`.
- **A gesture**: add a case to `GestureKind` in `Sources/OctoCore/Gestures.swift` and to its
  `catalog`, detect it in `GestureRecognizer` (taps) or `ClickGuard` (clicks), draw it in
  `Sources/Octo/Views/GestureDiagram.swift`, and add a test in `Tests/OctoCoreTests`.

## Icon

`scripts/make-icon.sh` draws the app icon (`scripts/make-icon.swift`) and builds
`Resources/AppIcon.icns`.
