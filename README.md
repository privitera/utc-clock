# utc-clock

A tiny macOS menu bar clock that shows UTC with seconds.

- **Click** copies the current time as an ISO-8601 timestamp (`2026-10-11T04:56:40Z`) and briefly shows the Seneca owl in its place.
- **Right-click** (or Control-click) opens a menu with **Uninstall UTC Clock…** and **Quit UTC Clock**.

## Install

Needs macOS 13 or later. Either way it builds from source on your Mac, so there are no Gatekeeper warnings.

### Homebrew

```bash
brew install privitera/tap/utc-clock
brew services start utc-clock    # start now and at every login
```

Keep the full `privitera/tap/utc-clock` name: Homebrew only loads formulae from third-party taps you've trusted, and installing by full name trusts this one.

If you quit it from the menu, `brew services restart utc-clock` brings it back. To update: `brew update && brew upgrade utc-clock && brew services restart utc-clock`. Homebrew only refreshes taps once a day on its own, and upgrading doesn't restart a running service.

### From source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/privitera/utc-clock.git && cd utc-clock
./build.sh
```

This compiles `UTCClock.app` into `~/Applications` and installs a LaunchAgent (`~/Library/LaunchAgents/local.utcclock.plist`) that starts it at login and restarts it if it crashes. Re-run `./build.sh` after editing `main.swift`; it rebuilds, swaps the app, and restarts it.

If you quit it from the menu, it stays quit until your next login, or until you run:

```bash
launchctl kickstart gui/$(id -u)/local.utcclock
```

Menu bar items only exist inside a logged-in session, so login is the earliest either method can start it.

## Not showing up?

- **System Settings → Menu Bar → Allow in the Menu Bar**: make sure **UTC Clock** is on.
- On a MacBook with a notch, a crowded menu bar hides the leftmost items. ⌘-drag icons to make room, or hide some.

## Why not SwiftBar or xbar?

They'd be the obvious choice, but on macOS 26 SwiftBar rebuilds its menu bar item on every update, so a once-a-second clock visibly flashes. A native `NSStatusItem` that only changes its title gets redrawn in place. The title uses monospaced digits so the width doesn't wobble every second.

## Uninstall

Right-click the clock and choose **Uninstall UTC Clock…**. It works for either install method: it quits the clock, removes it from login, and then runs `brew uninstall utc-clock` and `brew untap privitera/tap` (Homebrew) or deletes the app and its LaunchAgent (from source). If something fails, an alert points to the log.

By hand, Homebrew:

```bash
brew services stop utc-clock && brew uninstall utc-clock && brew untap privitera/tap
```

From source:

```bash
launchctl bootout gui/$(id -u)/local.utcclock
rm -rf ~/Applications/UTCClock.app ~/Library/LaunchAgents/local.utcclock.plist
```

## Bugs and ideas

[Open an issue](https://github.com/privitera/utc-clock/issues).

## Releasing

1. Tag and publish: `git tag -a vX.Y.Z -m "utc-clock X.Y.Z" && git push origin vX.Y.Z && gh release create vX.Y.Z --generate-notes`
2. In [privitera/homebrew-tap](https://github.com/privitera/homebrew-tap), point `Formula/utc-clock.rb` at the new tag's tarball, update `sha256` (`curl -sL <url> | shasum -a 256`), run `brew audit --strict privitera/tap/utc-clock`, and push.

Users pick it up with `brew update && brew upgrade utc-clock && brew services restart utc-clock`.

## License

[MIT](./LICENSE)
