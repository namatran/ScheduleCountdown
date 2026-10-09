# ScheduleCountdown

A menu bar app for Klein High that counts down to the next bell. It knows the normal bell schedule, alternate schedules (Jamboree, Pep Rally, …), and A / B / C lunch.

- The menu bar shows the countdown (`12:03`); before school, after school and on days off it shows a bell.
- Click it for the current period (or Passing), today's blocks for your lunch, the lunch picker, and today's schedule name.
- Settings (⌘,) has your lunch, launch at login, and "Show countdown outside school hours".

## Install

1. Download `ScheduleCountdown.zip` and unzip it.
2. Drag `ScheduleCountdown.app` into Applications.
3. Open it. The first time, macOS says it can't verify the developer: open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. You only do this once.

Requires macOS 14 or later.

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
4. Commit and push. Everyone's app picks it up within 6 hours (or on **Check for Updates**).

## Development

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and isn't checked in.

```sh
xcodegen generate && open ScheduleCountdown.xcodeproj   # work in Xcode
scripts/test.sh                                         # run the unit tests
scripts/package.sh                                      # build dist/ScheduleCountdown.zip
```

Add new files on disk (not through Xcode's "New File"), then rerun `xcodegen generate`.

Debugging helpers (environment variables, set in the Xcode scheme or on the command line):

- `SC_FAKE_NOW="2026-10-09 11:45"`: run as if it were that moment (the clock keeps ticking from there).
- `SC_REMOTE_URL=file:///path/to/schedule.json`: test downloading without GitHub.
