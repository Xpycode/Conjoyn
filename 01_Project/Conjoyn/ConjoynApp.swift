import SwiftUI
import AppKit
import HelpMenu

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI maps "?" + .command to keyEquivalent="/" + .shift in the NSMenuItem,
        // which displays as ⌘⇧/. Patch it to "?" so the menu shows ⌘? and AppKit
        // fires it on Cmd+? (AppKit handles the implicit Shift on US keyboards correctly).
        if let helpMenu = NSApp.helpMenu {
            for item in helpMenu.items where item.keyEquivalent == "/" {
                item.keyEquivalent = "?"
                item.keyEquivalentModifierMask = [.command]
            }
        }
    }
}

@main
struct ConjoynApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Owns the front-end state and the shared `QueueManager`. Both are injected into the view tree
    /// so any view can observe queue/console/progress changes.
    @StateObject private var viewModel = ConversionViewModel()
    /// Owns the Sparkle updater (starts a daily background check on init) and drives the
    /// "Check for Updates…" menu item's enabled state.
    @StateObject private var updaterController = UpdaterController()

    private let helpContent: HelpContent = {
        let content = (try? HelpContent(manifest: "help-manifest", in: .main))
            ?? HelpContent(topics: [], windowTitle: "Conjoyn Help")
        HelpWindowController.register(content: content)
        return content
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.queue)
                .preferredColorScheme(.dark)
        }
        // Native titlebar toolbar (App Shell Standard): `.hiddenTitleBar` + the `.toolbar` /
        // `.toolbarRole(.editor)` in ContentView put the source well + Scan in the system titlebar.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 800)
        .commands {
            HelpMenuCommands(content: helpContent, appName: "Conjoyn")
            UpdaterCommands(updater: updaterController)
        }
    }
}

/// Adds "Check for Updates…" under the app menu (after the About item). A `Commands` struct —
/// not an inline `CommandGroup` closure — so the `@ObservedObject` reliably refreshes the item's
/// disabled state while a check is in flight (the closure form lets that binding go stale;
/// documented in the P2toMXF port). `.appInfo` placement avoids the ⌘W/`.saveItem` overrides.
struct UpdaterCommands: Commands {
    @ObservedObject var updater: UpdaterController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
