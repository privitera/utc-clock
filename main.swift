// UTCClock: menu bar clock showing UTC with seconds.
// Click copies an ISO-8601 timestamp; right-click (or Control-click) for Quit
// and Uninstall.
// Uses a plain NSStatusItem title update, which macOS 26 redraws in place
// (SwiftBar rebuilds its item on each update, which flashes at 1 Hz).
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()  // right-click only
    private var timer: Timer?
    private var showingCopied = false
    private var restoreTitle: DispatchWorkItem?

    private let titleFormat = AppDelegate.utcFormatter("HH:mm:ss 'UTC'")
    private let isoFormat = AppDelegate.utcFormatter("yyyy-MM-dd'T'HH:mm:ss'Z'")

    // The font goes on each title: the menu bar ignores button.font, and
    // proportional digits make the item's width wobble every second.
    private let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
    ]

    private static func utcFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.autosaveName = "UTCClock"  // remember menu bar position across launches
        menu.addItem(withTitle: "Uninstall UTC Clock…", action: #selector(confirmUninstall), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit UTC Clock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Timers pause during sleep, so re-align to the second boundary on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(startTimer), name: NSWorkspace.didWakeNotification, object: nil)
        startTimer()
    }

    // Fire on whole-second boundaries so the display ticks in step with real time.
    @objc private func startTimer() {
        timer?.invalidate()
        tick()
        let next = Date(timeIntervalSinceReferenceDate: Date.timeIntervalSinceReferenceDate.rounded(.down) + 1)
        let t = Timer(fireAt: next, interval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)  // .common keeps ticking while the menu is open
        timer = t
    }

    @objc private func tick() {
        guard !showingCopied else { return }
        setTitle(titleFormat.string(from: Date()))
    }

    private func setTitle(_ text: String) {
        item.button?.attributedTitle = NSAttributedString(string: text, attributes: titleAttrs)
    }

    @objc private func clicked() {
        // No current event means an accessibility press (e.g. VoiceOver): treat it as a click.
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            // Attach the menu only for this click, so a left click never opens it.
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            copyTimestamp()
        }
    }

    private func copyTimestamp() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(isoFormat.string(from: Date()), forType: .string)

        // Show a brief confirmation in place of the time.
        showingCopied = true
        setTitle("Copied ✓")
        restoreTitle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.showingCopied = false
            self?.tick()
        }
        restoreTitle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // The app can't remove itself while it runs (stopping the service kills
    // it), so it hands off to this script and quits. Exit 0 keeps both
    // LaunchAgents from restarting it.
    // $0: log file, $1: app pid, $2: brew path, or empty for a from-source install.
    private static let uninstallScript = #"""
        exec >"$0" 2>&1
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        set -x
        if [ -n "$2" ]; then
            export HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1
            "$2" services stop utc-clock && "$2" uninstall utc-clock
            ok=$?
            # Cached source tarball. Not `brew cleanup utc-clock`: uninstall revokes
            # the formula's tap trust, so brew refuses to load it after this point.
            cache=$("$2" --cache) &&
                rm -f "$cache"/utc-clock--* "$cache"/downloads/*--utc-clock-*
            "$2" untap privitera/tap  # refuses if another formula from the tap is installed
        else
            launchctl bootout "gui/$(id -u)/local.utcclock"
            rm -rf "$HOME/Applications/UTCClock.app" "$HOME/Library/LaunchAgents/local.utcclock.plist"
            ok=$?
        fi
        [ "$ok" -eq 0 ] || osascript -e 'on run argv' \
            -e 'display alert "Couldn’t uninstall UTC Clock" message "Details are in " & item 1 of argv' \
            -e 'end run' "$0"
        """#

    @objc private func confirmUninstall() {
        // A Homebrew install runs from <prefix>/opt/utc-clock, a symlink into the Cellar.
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let brew = bundle.range(of: "/Cellar/utc-clock/").map { String(bundle[..<$0.lowerBound]) + "/bin/brew" }

        let alert = NSAlert()
        alert.messageText = "Uninstall UTC Clock?"
        alert.informativeText = brew != nil
            ? "This quits the clock, removes it from login, and runs brew uninstall utc-clock and brew untap privitera/tap."
            : "This quits the clock, removes its login agent, and deletes ~/Applications/UTCClock.app."
        alert.addButton(withTitle: "Uninstall").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        // Otherwise an accessory app's alert opens behind other windows.
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let log = NSTemporaryDirectory() + "utc-clock-uninstall.log"
        let rc = spawnDetached(["/bin/sh", "-c", Self.uninstallScript, log, String(getpid()), brew ?? ""])
        if rc == 0 {
            NSApp.terminate(nil)
        } else {
            NSAlert(error: NSError(domain: NSPOSIXErrorDomain, code: Int(rc))).runModal()
        }
    }

    // launchd kills whatever is left in a job's process group when the job
    // exits, so the script gets its own session to outlive the app.
    private func spawnDetached(_ args: [String]) -> Int32 {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        let argv = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        return posix_spawn(&pid, args[0], nil, &attr, argv, environ)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
