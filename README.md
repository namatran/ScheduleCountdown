# ScheduleCountdown

A menu bar app for Klein High that counts down to the next bell. It knows the normal bell schedule, alternate schedules (Jamboree, Pep Rally, …), and A / B / C lunch.

- The menu bar shows the countdown (`12:03`); before school, after school and on days off it shows a bell.
- Click it for the current period (or Passing), today's blocks for your lunch, the lunch picker, and today's schedule name.
- Settings (⌘,) has your lunch, launch at login, "Show countdown outside school hours", your app version and What's New.

## Install

1. Download `ScheduleCountdown.dmg` from the [latest release](https://github.com/namatran/ScheduleCountdown/releases/latest) and open it.
2. Drag ScheduleCountdown onto the Applications folder next to it.
3. Open it from Applications. The first time, macOS says it can't verify the developer: open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. You only do this once.

Requires macOS 14 or later.

After that the app updates itself. It checks when it opens and once a day, and asks before installing; until you do, the menu shows **Update Available**. Updates don't need "Open Anyway" again.

It has to run from Applications to update: macOS runs apps opened from a disk image or Downloads from a read-only copy. If you open it from anywhere else, it offers to move itself.

## How schedules work

Everything lives in one file, [`ScheduleCountdown/Resources/schedule.json`](ScheduleCountdown/Resources/schedule.json):

- **schedules**: reusable named schedules. Each has one-off `bells` (like the 7:09 release) and `blocks` with `start`, `end`, an optional early `dismiss` bell, and the `groups` (lunches) it applies to. A block without `groups` is for everyone.
- **calendar**: days (or date ranges) that use an alternate schedule, or `"scheduleID": null` for no school.
- Weekdays not in the calendar use `defaultScheduleID`; weekends are off.

The app ships with this file built in. If `ScheduleRemoteURL` in `project.yml` is set, every copy also downloads the file on launch and every 6 hours, so everyone gets schedule changes without reinstalling. It keeps the last good copy for when it's offline.

### Editing (editor mode)

1. Hold **⌥ Option** while clicking **Settings…** and turn on **Editor mode**. The Schedules and Calendar tabs appear, and this Mac follows your draft.
2. Edit schedules (Duplicate is handy for a new alternate schedule) and assign days in Calendar.
3. Click **Export Master File…** and save over `ScheduleCountdown/Resources/schedule.json`.
4. Commit and push. Everyone's app picks it up within 6 hours (or on **Check for Schedule Updates**).

## Development

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and isn't checked in.

```sh
xcodegen generate && open ScheduleCountdown.xcodeproj   # work in Xcode
scripts/test.sh                                         # run the unit tests
scripts/package.sh                                      # build dist/ScheduleCountdown.zip and .dmg
```

Add new files on disk (not through Xcode's "New File"), then rerun `xcodegen generate`.

Debugging helpers (environment variables, set in the Xcode scheme or on the command line):

- `SC_FAKE_NOW="2026-10-09 11:45"`: run as if it were that moment (the clock keeps ticking from there).
- `SC_REMOTE_URL=file:///path/to/schedule.json`: test downloading without GitHub.

## Releasing

App updates use [Sparkle](https://sparkle-project.org). Each GitHub Release carries the dmg (for new installs), the zip (what updates download) and `appcast.xml`, and the app reads the feed from the latest release. Ad-hoc signing is enough: Sparkle checks each update against the EdDSA public key in `project.yml` (`SUPublicEDKey`) and clears the quarantine flag, so Gatekeeper doesn't prompt.

**Signing key.** The private key lives in the login Keychain of the Mac you release from (created once with `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`). Never commit it. Keep a backup in a password manager: export it with `generate_keys -x sparkle_private_key`, store it, delete the file, and on a new Mac import it with `generate_keys -f sparkle_private_key`. If the key is lost, installed copies can't update anymore.

**Release.**

```sh
scripts/release.sh 1.2.0             # first run: drafts a 1.2.0 section in CHANGELOG.md, then stops
                                     # rewrite it for students, then run it again:
scripts/release.sh 1.2.0             # dates the changelog, bumps, packages, signs, writes dist/appcast.xml, commits
git push
scripts/release.sh --publish 1.2.0   # asks, then creates the GitHub Release
```

The notes come from the version's section in [`CHANGELOG.md`](CHANGELOG.md): they show in the update window, on the GitHub Release, and in the app's What's New. Keep them short and about what students will notice. Add `--critical` for a fix everyone must get: Sparkle then hides "Skip This Version" and "Remind Me Later". The bump increases `CURRENT_PROJECT_VERSION`, which is the number Sparkle compares.

`package.sh` asks Finder to lay out the disk image window (icon positions and the arrow background), so the first run may ask to let Terminal control Finder. Without that permission the dmg still works, just without the layout.
