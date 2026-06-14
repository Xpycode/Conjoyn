import SwiftUI
import AppKit
import HelpMenu
import FeedbackKit

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

    private let helpContent: HelpContent = {
        let content = (try? HelpContent(manifest: "help-manifest", in: .main))
            ?? HelpContent(topics: [], windowTitle: "Conjoyn Help")
        HelpWindowController.register(content: content)
        return content
    }()

    /// Configuration for the in-app feedback sheet (Help › Send Feedback…). Posts to the shared
    /// multi-app endpoint (`feedback-submit.php`, cookbook #49), keyed by `appID` — the server gates
    /// on its own `ALLOWED_APPS`, which already allow-lists `conjoyn` (App-Websites repo, deployed +
    /// gate-verified live). Accent + recent-log tail are injected; FeedbackKit has no
    /// coupling to Conjoyn's `Theme` or `DiagnosticLogger`. The `logProvider` reads on the main actor
    /// (FeedbackKit only invokes it from its SwiftUI view body), so `assumeIsolated` is safe here.
    private let feedbackConfig = FeedbackConfig(
        appID: "conjoyn",
        endpoint: URL(string: "https://apps.lucesumbrarum.com/feedback-submit.php")!,
        accent: Theme.acc2,
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
                .preferredColorScheme(appearance.colorScheme)
        }
        // Native titlebar toolbar (App Shell Standard): `.hiddenTitleBar` + the `.toolbar` /
        // `.toolbarRole(.editor)` in ContentView put the source well + Scan in the system titlebar.
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 800)
        .commands {
            FileCommands(viewModel: viewModel)
            HelpMenuCommands(content: helpContent, appName: "Conjoyn")
            // Separator between "Conjoyn Help" and "Send Feedback…". FeedbackCommands is a package
            // type we can't edit, so the divider is its own after-`.help` group, declared between the
            // two so it lands between their items (same-anchor groups order by declaration order).
            CommandGroup(after: .help) { Divider() }
            FeedbackCommands(config: feedbackConfig)
            DonateCommands()
            UpdaterCommands(updater: updaterController)
            AppearanceCommands(appearance: $appearance)
        }
    }
}

/// User appearance preference, persisted via `@AppStorage`. `.auto` follows the system
/// (`colorScheme == nil`); `.light`/`.dark` pin the window via `.preferredColorScheme`.
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

    /// `nil` = follow the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto:  return nil
        case .light: return .light
        case .dark:  return .dark
        }
    }
}

/// Adds a top-level **Appearance** menu with Match System / Light / Dark radio items directly under it
/// (`.inline` picker, no nested submenu). A `Commands` struct (not an inline closure) bound to
/// the App's `@AppStorage` so the checkmark + `.preferredColorScheme` stay in sync — same
/// pattern as `UpdaterCommands` (closures let the binding go stale). The `EmptyView` label
/// suppresses a redundant "Appearance" section header inside the same-named menu.
struct AppearanceCommands: Commands {
    @Binding var appearance: AppearancePreference

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
        }
    }
}

/// Adds **File › Choose Folder…** (⌘O), right after "New Window". Calls the same
/// `chooseSourceFolder()` path the toolbar Scan button uses — opens the media-folder picker and
/// scans. A `Commands` struct bound to the App's `@StateObject` view model (same pattern as
/// `UpdaterCommands`) so the action always targets the live view model.
struct FileCommands: Commands {
    @ObservedObject var viewModel: ConversionViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose Folder\u{2026}") { viewModel.chooseSourceFolder() }
                .keyboardShortcut("o", modifiers: [.command])
        }
    }
}

/// Adds **Help › Donate** after "Send Feedback…", opening the support page in the default browser.
/// The same page is also a Help-window topic (`help-donate.md`); this is the menu-bar shortcut for it.
/// No ellipsis: per the HIG that marks a command needing further in-app input (as "Send Feedback…"
/// does), whereas this just hands off to the browser. The URL is the shared apps-portal donate page —
/// live now, independent of the not-yet-deployed Conjoyn site — app-tagged so the page can show
/// Conjoyn-specific context, matching the link the Conjoyn website itself uses.
struct DonateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .help) {
            Divider()
            Button("Donate") {
                if let url = URL(string: "https://apps.lucesumbrarum.com/donate.html?app=conjoyn") {
                    NSWorkspace.shared.open(url)
                }
            }
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
