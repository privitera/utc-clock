// UTCClock: menu bar clock showing UTC with seconds.
// Click copies an ISO-8601 timestamp and flashes the Seneca owl; right-click
// (or Control-click) for Uninstall and Quit.
// Uses a plain NSStatusItem title update, which macOS 26 redraws in place
// (SwiftBar rebuilds its item on each update, which flashes at 1 Hz).
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()  // right-click only
    private var timer: Timer?
    private var restoreTitle: DispatchWorkItem?  // pending while the owl shows

    private let titleFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm:ss 'UTC'"
        return f
    }()

    // The font goes on each title: the menu bar ignores button.font, and
    // proportional digits make the item's width wobble every second.
    private let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
    ]

    // The Seneca owl ("Seneca Owl Logo Black.svg", verbatim), flashed in place
    // of the time after a copy.
    private static let owlSVG = """
        <svg width="1146" height="556" viewBox="0 0 1146 556" fill="none" xmlns="http://www.w3.org/2000/svg">
        <path d="M1145.23 116.802L1108.18 205.164L634.07 233.449C633.213 233.488 632.356 233.527 631.498 233.527C620.005 233.527 608.941 228.93 600.837 220.67C592.11 211.787 587.668 199.593 588.642 187.203L601.188 24.9734L688.302 13.9088L678.173 144.62L1145.23 116.764V116.802ZM689.393 0H689.315L689.354 0.428561V0H689.393ZM514.501 233.566C525.994 233.566 537.059 228.969 545.163 220.709C553.89 211.826 558.331 199.632 557.357 187.242L544.812 25.0124L457.697 13.9477L467.827 144.659L0.772949 116.802L37.824 205.164L511.93 233.449C512.787 233.488 513.644 233.527 514.501 233.527V233.566ZM402.88 554.286L497.32 536.793L555.799 332.486C559.305 320.252 557.202 307.084 550.072 296.565C542.942 286.006 531.488 279.188 518.826 277.903L48.1874 229.943L86.0177 320.252L458.983 358.238L402.841 554.325L402.88 554.286ZM595.538 297.11C588.448 307.98 586.616 321.46 590.59 333.81L656.433 538.195L752.509 556L688.731 358.044L1059.98 320.252L1097.81 229.943L627.135 277.864C614.239 279.188 602.59 286.24 595.499 297.11H595.538Z" fill="#232527"/>
        </svg>
        """
    private let owl = NSImageView()

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.autosaveName = "UTCClock"  // remember menu bar position across launches
        menu.addItem(withTitle: "Uninstall UTC Clock…", action: #selector(confirmUninstall), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit UTC Clock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])

            // The owl covers the button, centered and hidden until a copy. As a
            // template image, the menu bar tints it for light and dark mode.
            if let image = NSImage(data: Data(Self.owlSVG.utf8)) {
                image.size = NSSize(width: image.size.width * 13 / image.size.height, height: 13)
                image.isTemplate = true
                owl.image = image
                owl.frame = button.bounds
                owl.autoresizingMask = [.width, .height]
                owl.isHidden = true
                button.addSubview(owl)
            }
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
        guard restoreTitle == nil else { return }
        setTitle(titleFormat.string(from: Date()))
    }

    private func setTitle(_ text: String, color: NSColor? = nil) {
        var attrs = titleAttrs
        attrs[.foregroundColor] = color
        item.button?.attributedTitle = NSAttributedString(string: text, attributes: attrs)
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
        NSPasteboard.general.setString(Date().formatted(.iso8601), forType: .string)

        // Briefly swap the time for the owl. The time stays as invisible text,
        // so the item keeps its width. "Copied ✓" if the owl didn't load.
        if owl.image != nil, let text = item.button?.attributedTitle.string {
            setTitle(text, color: .clear)
            owl.isHidden = false
        } else {
            setTitle("Copied ✓")
        }
        restoreTitle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.restoreTitle = nil
            self?.owl.isHidden = true
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
