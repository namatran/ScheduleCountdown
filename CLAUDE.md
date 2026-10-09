# ScheduleCountdown

Menu bar countdown to the next bell, for Klein High students. @README.md covers install, the schedule file format, and the release flow.

## Stack

- SwiftUI menu bar app (`MenuBarExtra`, no Dock icon), macOS 14+, Swift 5 language mode
- XcodeGen: `project.yml` is the source of truth; the `.xcodeproj` is generated and not committed
- Sparkle 2 (SPM, pinned in `project.yml`) for app updates: EdDSA-signed, and the app is ad-hoc code signed because there's no paid Apple account
- Swift Testing (`@Test`, `#expect`) in `ScheduleCountdownTests/`
- No backend: the schedule is `schedule.json` on `main`, served by raw.githubusercontent.com; app updates are GitHub Releases

## Preferences

- The users are high school students. Anything they read (UI text, CHANGELOG.md, release notes) is short and plain, without technical words.
- Ask before publishing a release or changing anything on GitHub.

## Commands

- `xcodegen generate`: after adding or removing files. Create files on disk, not with Xcode's New File.
- `scripts/test.sh`: build and run the unit tests
- `scripts/package.sh`: build `dist/ScheduleCountdown.zip` (for updates) and `.dmg` (for installs)
- `scripts/release.sh <version>`, then `--publish <version>`: see README → Releasing

## Layout

`Model/` data types (MasterFile, Changelog) · `Engine/` pure schedule logic · `Store/` schedule download, cache and editor draft · `State/AppState` clock and settings · `Updates/` Sparkle and move-to-Applications · `Views/` menu and Settings

## Gotchas

- Pushing `ScheduleCountdown/Resources/schedule.json` to `main` reaches every installed copy within 6 hours. App code only reaches students through a release.
- The menu rebuilds, closing any open submenu, whenever state it reads changes. Only assign `AppState` properties the menu reads when the value actually changed, like `menuStatus`.
- It's a menu bar app, so macOS may ignore `NSApp.activate()`. Windows it opens (Sparkle's, alerts) need `orderFrontRegardless()` or a raised window level, or they appear behind other apps.
- Optional Sparkle delegate methods are skipped silently if the Swift name doesn't match. After changing `AppUpdater`, check that the Objective-C selectors are in the built binary.
- SourceKit errors like "Cannot find type … in scope" in single files are noise; `scripts/test.sh` is what counts.
- `release.sh --publish` reads its y/N answer from the terminal, so the user has to run it in a real terminal.
- Each ad-hoc build is a new app to Gatekeeper. A quarantined copy run outside Applications is translocated (run from a read-only path) and can't update.

## Corrections

Things the user had to correct. One line each, newest last.

- (none yet)
