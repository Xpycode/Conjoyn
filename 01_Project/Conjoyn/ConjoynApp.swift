import SwiftUI
import AppKit
import HelpMenu
import AppCitizenshipKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Strips the system text extras (Writing Tools, Emoji & Symbols, Dictation, …) that AppKit
    /// injects below "Select All" in the Edit menu. Retained so its menu delegate stays alive.
    private let editMenuTrimmer = EditMenuTrimmer()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Suppress the two system items AppKit auto-adds to the bottom of the Edit menu before the
        // menu is built. (Writing Tools has no defaults switch — it's removed by the trimmer below.)
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")
    }

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

        // Remove everything below "Select All" in the Edit menu (writing tools, emoji, etc.).
        if let editMenu = NSApp.mainMenu?.items
            .compactMap(\.submenu)
            .first(where: { menu in menu.items.contains { $0.action == #selector(NSText.selectAll(_:)) } }) {
            editMenuTrimmer.attach(to: editMenu)
        }
    }
}

/// Becomes the Edit menu's delegate and, every time the menu is about to open, deletes every item
/// after "Select All". This catches AppKit's lazily-injected items (Writing Tools especially, which
/// has no `UserDefaults` opt-out) that a one-time pass at launch would miss.
@MainActor
final class EditMenuTrimmer: NSObject, NSMenuDelegate {
    func attach(to menu: NSMenu) {
        menu.delegate = self
        trim(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) { trim(menu) }

    private func trim(_ menu: NSMenu) {
        guard let selectAll = menu.items.firstIndex(where: { $0.action == #selector(NSText.selectAll(_:)) })
        else { return }
        while menu.items.count > selectAll + 1 {
            menu.removeItem(at: selectAll + 1)
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
    /// User-chosen appearance (View › Appearance). Persisted; defaults to Dark so the
    /// out-of-box look matches the dark-first FCP design. `.auto` follows the system.
    @AppStorage("appearancePreference") private var appearance: AppearancePreference = .dark
    /// User-chosen Dock icon appearance (View › Appearance › App Icon), independent of the UI
    /// theme above. Persisted; `.auto` follows the system. Driven at runtime by `iconController`
    /// because macOS can't vary the bundle icon by appearance — see `AppIconController`.
    @AppStorage("iconPreference") private var iconPreference: IconPreference = .auto
    @StateObject private var iconController = AppIconController()

    private let helpContent: HelpContent = {
        let content = (try? HelpContent(manifest: "help-manifest", in: .main))
            ?? HelpContent(topics: [], windowTitle: "Conjoyn Help")
        HelpWindowController.register(content: content)
        return content
    }()

    /// Drives all three "app citizenship" surfaces via AppCitizenshipKit: Help › Send Feedback…
    /// (FeedbackKit, posts to the shared `feedback-submit.php`, cookbook #49 — the server gates on
    /// `ALLOWED_APPS`, which already allow-lists `conjoyn`), Help › Leave a Tip (the tip-jar hub,
    /// cookbook #100, `?app=conjoyn`), and a link-rich About panel. `appID` is the single slug used
    /// for both feedback and the tip jar. The endpoint + tip-jar hub default to the shared lucesumbrarum
    /// hosts, so only `appID`/`appName`/links are supplied. The `logProvider` reads on the main actor
    /// (FeedbackKit only invokes it from its SwiftUI view body), so `assumeIsolated` is safe here.
    /// Website/Privacy point at the apps portal — live for the tip jar/feedback today; the per-app
    /// marketing page may lag, which is harmless (the About links just resolve once it ships).
    private let citizenship = CitizenshipConfig(
        appID: "conjoyn",
        appName: "Conjoyn",
        accent: Theme.acc2,
        websiteURL: URL(string: "https://apps.lucesumbrarum.com/conjoyn"),
        privacyURL: URL(string: "https://apps.lucesumbrarum.com/privacy"),
        logProvider: { MainActor.assumeIsolated { DiagnosticLogger.shared.recentTail(maxLines: 80) } }
    )

    var body: some Scene {
        // Single-instance `Window` (not `WindowGroup`): Conjoyn shares one view model + queue, so a
        // second window/tab would only mirror the same state. `Window` removes "New Window" (⌘N) and
        // the tab bar automatically. See specs/single-window-mode.md.
        Window("Conjoyn", id: "main") {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(viewModel.queue)
                // Drive appearance app-wide via `NSApp.appearance` (not `.preferredColorScheme`):
                // on macOS `.preferredColorScheme(nil)` does NOT clear a previously-forced
                // `NSWindow.appearance`, so Dark → Match System would stay dark (the Theme colors
                // resolve against the window's stale `NSAppearance`). `NSApp.appearance = nil`
                // reverts to the system cleanly. `initial: true` applies the persisted preference
                // at launch too.
                .onChange(of: appearance, initial: true) { _, pref in
                    NSApplication.shared.appearance = pref.nsAppearance
                }
                // Dock-icon swap is runtime-only (macOS ignores appearance-variant bundle icons):
                // `.task` does the initial apply + installs the effective-appearance observer once;
                // `.onChange` handles later menu picks. See `AppIconController`.
                .task { iconController.start(with: iconPreference) }
                .onChange(of: iconPreference) { _, pref in iconController.update(pref) }
        }
        // Native titlebar toolbar (App Shell Standard): `.hiddenTitleBar` + the `.toolbar` /
        // `.toolbarRole(.editor)` in ContentView put the source well + Scan in the system titlebar.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 800)
        .commands {
            FileCommands(viewModel: viewModel)
            HelpMenuCommands(content: helpContent, appName: "Conjoyn")
            // Separator between "Conjoyn Help" and "Send Feedback…". HelpMenu's items and
            // AppCitizenshipKit's FeedbackCommands are package types we can't edit, so the divider is
            // its own after-`.help` group declared between them (same-anchor groups order by
            // declaration order, cookbook #104). The Feedback↔Support divider is emitted by
            // CitizenshipCommands itself, so it is not repeated here.
            CommandGroup(after: .help) { Divider() }
            // One line for Send Feedback… + Leave a Tip + the link-rich About panel.
            CitizenshipCommands(citizenship)
            UpdaterCommands(updater: updaterController)
            AppearanceCommands(appearance: $appearance, iconPreference: $iconPreference)
        }
    }
}

/// User appearance preference, persisted via `@AppStorage`. `.auto` follows the system
/// (`nsAppearance == nil`); `.light`/`.dark` pin the app via `NSApplication.shared.appearance`.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:  return "Match System"
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }

    /// The AppKit appearance to pin app-wide via `NSApplication.shared.appearance`; `nil` follows
    /// the system. Driven through `NSApp.appearance` rather than SwiftUI's `.preferredColorScheme`
    /// because the latter's `nil` case does not clear a previously-forced window appearance on macOS.
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto:  return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark:  return NSAppearance(named: .darkAqua)
        }
    }
}

/// Adds a top-level **Appearance** menu with two `.inline` radio sections: the UI **theme**
/// (Match System / Light / Dark) and, below a divider, the **App Icon** (Match System / Light /
/// Dark). A `Commands` struct (not an inline closure) bound to the App's `@AppStorage` so the
/// checkmarks stay in sync — same pattern as `UpdaterCommands` (closures let the binding go
/// stale). The theme picker's `EmptyView` label suppresses a redundant header inside the
/// same-named menu; the icon picker keeps an "App Icon" label so the second section reads clearly.
struct AppearanceCommands: Commands {
    @Binding var appearance: AppearancePreference
    @Binding var iconPreference: IconPreference

    var body: some Commands {
        CommandMenu("Appearance") {
            Picker(selection: $appearance) {
                ForEach(AppearancePreference.allCases) { pref in
                    Text(pref.title).tag(pref)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)

            Divider()

            Picker(selection: $iconPreference) {
                ForEach(IconPreference.allCases) { pref in
                    Text(pref.title).tag(pref)
                }
            } label: {
                Text("App Icon")
            }
            .pickerStyle(.inline)
        }
    }
}

/// Adds **File › Choose Source Folder…** (⌘O) and **File › Choose Destination Folder…**, right
/// after "New Window". Each calls the same view-model path its on-screen path well uses:
/// `chooseSourceFolder()` (the source/media picker the toolbar Scan also drives) and
/// `chooseOutputFolder()` (the Output-bar picker — so the menu inherits its "re-point pending
/// jobs?" prompt for free). Source/destination match the path-well placeholders ("No source
/// selected" / "No destination"). A `Commands` struct bound to the App's `@StateObject` view model
/// (same pattern as `UpdaterCommands`) so the actions always target the live view model.
struct FileCommands: Commands {
    @ObservedObject var viewModel: ConversionViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose Source Folder\u{2026}") { viewModel.chooseSourceFolder() }
                .keyboardShortcut("o", modifiers: [.command])
            Button("Choose Destination Folder\u{2026}") { viewModel.chooseOutputFolder() }
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
