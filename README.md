# utc-clock

A tiny macOS menu bar clock that shows UTC with seconds.

- **Click** copies the current time as an ISO-8601 timestamp (`2026-10-11T04:56:40Z`) and flashes `Copied ✓`.
- **Right-click** (or Control-click) opens a menu with **Quit UTC Clock**.

## Install

Needs macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh
```

This compiles `UTCClock.app` into `~/Applications` and installs a LaunchAgent (`~/Library/LaunchAgents/local.utcclock.plist`) that starts it at login and restarts it if it crashes. Re-run `./build.sh` after editing `main.swift`; it rebuilds, swaps the app, and restarts it.

Menu bar items only exist inside a logged-in session, so login is the earliest it can start.

If you quit it from the menu, it stays quit until your next login, or until you run:

```bash
launchctl kickstart gui/$(id -u)/local.utcclock
```

## Not showing up?

- **System Settings → Menu Bar → Allow in the Menu Bar**: make sure **UTC Clock** is on.
- On a MacBook with a notch, a crowded menu bar hides the leftmost items. ⌘-drag icons to make room, or hide some.

## Why not SwiftBar or xbar?

They'd be the obvious choice, but on macOS 26 SwiftBar rebuilds its menu bar item on every update, so a once-a-second clock visibly flashes. A native `NSStatusItem` that only changes its title gets redrawn in place. The title uses monospaced digits so the width doesn't wobble every second.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/local.utcclock
rm -rf ~/Applications/UTCClock.app ~/Library/LaunchAgents/local.utcclock.plist
```
