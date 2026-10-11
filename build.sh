#!/bin/bash
# Build UTCClock.app, install it to ~/Applications, and (re)start it with a
# LaunchAgent so it runs at login. Safe to re-run after editing main.swift.
set -euo pipefail
cd "$(dirname "$0")"

LABEL="local.utcclock"
APP="$HOME/Applications/UTCClock.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

# Build first, so a compile error leaves the running clock alone.
rm -rf build
mkdir -p build/UTCClock.app/Contents/MacOS
cp Info.plist build/UTCClock.app/Contents/Info.plist
swiftc -O -o build/UTCClock.app/Contents/MacOS/UTCClock main.swift
codesign --force --sign - build/UTCClock.app

# Stop the running copy and wait for launchd to let go of the label.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
while launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; do sleep 0.2; done

mkdir -p "$HOME/Applications" "$(dirname "$AGENT")"
rm -rf "$APP"
cp -R build/UTCClock.app "$APP"

# KeepAlive restarts it after a crash; "Quit UTC Clock" (exit 0) keeps it quit
# until next login or `launchctl kickstart $DOMAIN/$LABEL`.
cat >"$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$APP/Contents/MacOS/UTCClock</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
EOF

launchctl bootstrap "$DOMAIN" "$AGENT"
echo "Installed $APP and started $LABEL"
