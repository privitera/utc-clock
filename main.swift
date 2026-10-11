// UTCClock: menu bar clock showing UTC with seconds.
// Click copies an ISO-8601 timestamp; right-click (or Control-click) for Quit.
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
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
