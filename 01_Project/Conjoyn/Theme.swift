import SwiftUI
import AppKit

// MARK: - Theme (design tokens)

/// Design tokens from the 2026-06-10 design handoff (`02_Design/design_handoff_conjoyn/`).
/// The dark palette mirrors `conjoyn/styles.css` `:root` 1:1; the light palette is the
/// "soft neutral gray" variant (light gray surfaces, not pure white — keeps the dark theme's
/// restrained, low-glare FCP character). Tokens are **adaptive**: a single `Color` resolves
/// its value against the window's live `NSAppearance`, so the appearance toggle (View ›
/// Appearance) flips the whole UI by setting `.preferredColorScheme`. The four accents are
/// mode-independent.
///
/// Use `Theme.xxx` everywhere for surfaces, hairlines, text, and accent — never `Color.gray`,
/// `.secondary` for chrome, or raw `.white.opacity`/`.black.opacity` in view code. For chrome
/// overlays use `Theme.raised(_:)` (hover tints, raised fills, borders) and `Theme.recessed(_:)`
/// (input/console wells) so they adapt too.
struct Theme {
    // MARK: Surfaces

    /// `--bg` — window/content background.
    static let bg = Color(light: 0xF4F4F4, dark: 0x1D1D1D)
    /// `--panel` — output bar, footer.
    static let panel = Color(light: 0xECECEC, dark: 0x232323)
    /// `--panel-2` — raised panel surface.
    static let panel2 = Color(light: 0xE2E2E2, dark: 0x2A2A2A)
    /// Console well background (deepest surface).
    static let consoleBG = Color(light: 0xDCDCDC, dark: 0x151515)

    // MARK: Hairlines

    /// `--line` — hairline separators.
    static let line = raised(0.07)
    /// `--line-strong` — footer top border.
    static let lineStrong = raised(0.12)

    // MARK: Text

    /// `--txt` — primary text.
    static let txt = Color(light: 0x1E1E1E, dark: 0xE8E8E8)
    /// `--txt-2` — secondary text.
    static let txt2 = Color(light: 0x5A5A5A, dark: 0x9F9F9F)
    /// `--txt-3` — tertiary text / section labels.
    static let txt3 = Color(light: 0x8A8A8A, dark: 0x6E6E6E)

    // MARK: Accents (mode-independent)

    /// `--acc1` — light accent: Split badge, "Joining…" status, spinner.
    static let acc1 = Color(hex: 0xFFB23E)
    /// `--acc2` — control accent: primary buttons, checks, switches, progress, selection tint.
    static let acc2 = Color(hex: 0xF0622A)
    /// `--ok` — success.
    static let ok = Color(hex: 0x3FD68A)
    /// `--bad` — failure.
    static let bad = Color(hex: 0xFF6B6B)

    // MARK: Adaptive chrome overlays

    /// A subtle overlay that **lightens on dark** surfaces and **darkens on light** surfaces.
    /// Replaces `.white.opacity(α)` chrome: hover tints, raised fills, hairline borders.
    static func raised(_ alpha: Double) -> Color {
        adaptive(light: .black, lightAlpha: alpha, dark: .white, darkAlpha: alpha)
    }

    /// A recessed well. Replaces `.black.opacity(α)` (input / console / token-field wells).
    /// In light mode the inset is scaled down so wells don't read as heavy gray blocks.
    static func recessed(_ alpha: Double) -> Color {
        adaptive(light: .black, lightAlpha: alpha * 0.45, dark: .black, darkAlpha: alpha)
    }

    private static func adaptive(light: NSColor, lightAlpha: Double,
                                 dark: NSColor, darkAlpha: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.isLight
                ? light.withAlphaComponent(lightAlpha)
                : dark.withAlphaComponent(darkAlpha)
        })
    }
}

extension Color {
    /// Build a Color from a 24-bit RGB hex literal (e.g. `0xF0622A`). Mode-independent.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Adaptive opaque color from two sRGB hex literals — resolves `light` in a light
    /// appearance, `dark` otherwise (against the window's live `NSAppearance`).
    init(light: UInt32, dark: UInt32) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(srgbHex: appearance.isLight ? light : dark)
        })
    }
}

private extension NSColor {
    /// Opaque sRGB color from a 24-bit hex literal.
    convenience init(srgbHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension NSAppearance {
    /// True for the Aqua (light) family; treats an unresolved best-match as light.
    var isLight: Bool {
        bestMatch(from: [.aqua, .darkAqua]) != .darkAqua
    }
}
