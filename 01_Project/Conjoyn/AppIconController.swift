import AppKit
import SwiftUI

/// User preference for the Dock / running-app icon, persisted via `@AppStorage`. Deliberately
/// **independent** of the UI theme (`AppearancePreference`) — they're separate sections of the
/// Appearance menu, so a user can run a Light UI with a Dark Dock icon or vice-versa.
enum IconPreference: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:  return "Match System"
        case .light: return "Light"
        case .dark:  return "Dark"
        }
    }
}

/// Swaps the **running app's** Dock icon (`NSApplication.shared.applicationIconImage`) between a
/// light and a dark variant.
///
/// macOS does NOT honor an appearance-variant *bundle* icon: actool drops the dark renditions of an
/// asset-catalog app icon as "unassigned children" and compiles a single appearance-agnostic
/// `AppIcon.icns` (verified against the built `Assets.car`). So the only way to get an
/// appearance-aware Dock tile is to set `applicationIconImage` at runtime. The static bundle icon
/// (shown in Finder and when the app isn't running) stays the dark catalog icon.
///
/// `.auto` tracks `NSApp.effectiveAppearance` — which the theme picker also drives — observed via
/// KVO, so both a live System dark-mode flip *and* an in-app theme switch re-skin the tile. The two
/// `.icns` are bundled resources (`Resources/ConjoynIcon-{Dark,Light}.icns`), loaded lazily.
@MainActor
final class AppIconController: ObservableObject {
    private var preference: IconPreference = .auto
    private var appearanceObserver: NSKeyValueObservation?

    private lazy var darkIcon: NSImage? = Self.load("ConjoynIcon-Dark")
    private lazy var lightIcon: NSImage? = Self.load("ConjoynIcon-Light")

    /// Begin driving the Dock icon and observing the effective appearance. Call once at launch.
    func start(with preference: IconPreference) {
        self.preference = preference
        // KVO fires on the main thread when the resolved appearance changes (System flip or the
        // theme picker mutating `NSApp.appearance`); `assumeIsolated` bridges the non-isolated
        // closure to this @MainActor type (same pattern as the FeedbackKit log provider).
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.apply() }
        }
        apply()
    }

    /// React to a menu change.
    func update(_ preference: IconPreference) {
        self.preference = preference
        apply()
    }

    private func apply() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let icon: NSImage?
        switch preference {
        case .auto:  icon = isDark ? darkIcon : lightIcon
        case .light: icon = lightIcon
        case .dark:  icon = darkIcon
        }
        // Guard the load: a nil would reset to the bundle icon, but we always intend an explicit one.
        if let icon { NSApp.applicationIconImage = icon }
    }

    private static func load(_ name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }
}
