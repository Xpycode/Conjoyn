import AppKit
import SwiftUI

/// Owns the single, reusable help `NSWindow`.
///
/// `showHelp(content:)` creates the window on first call and brings the
/// existing one to front on subsequent calls — clicks never spawn duplicates.
/// Works from both SwiftUI and AppKit hosts, including menu-bar apps with no
/// other windows.
@MainActor
public final class HelpWindowController: NSObject, NSWindowDelegate {
    public static let shared = HelpWindowController()

    private var window: NSWindow?
    private static var registeredContent: HelpContent?

    private override init() { super.init() }

    /// Register content once at startup so call-sites without a direct
    /// reference to `HelpContent` can call the no-argument `showHelp()`.
    public static func register(content: HelpContent) {
        registeredContent = content
    }

    /// Show the help window, creating it or focusing the existing instance.
    public static func showHelp(content: HelpContent) {
        registeredContent = content
        shared.present(content: content)
    }

    /// Show the help window using previously registered content.
    /// No-ops silently if `register(content:)` has not been called.
    public static func showHelp() {
        guard let content = registeredContent else { return }
        shared.present(content: content)
    }

    private func present(content: HelpContent) {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: HelpWindowView(content: content))
        let window = NSWindow(contentViewController: hosting)
        window.title = content.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 820, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.identifier = NSUserInterfaceItemIdentifier("HelpMenu.HelpWindow")

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        // Drop the reference so the next showHelp rebuilds with fresh content.
        if (notification.object as? NSWindow) === window {
            window = nil
        }
    }
}
