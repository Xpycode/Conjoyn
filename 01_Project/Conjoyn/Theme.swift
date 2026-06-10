import SwiftUI

// MARK: - Theme (design tokens)

/// Design tokens from the 2026-06-10 design handoff (`02_Design/design_handoff_conjoyn/`).
/// The authoritative source is `conjoyn/styles.css`; this file mirrors its `:root` custom
/// properties 1:1. Dark-only, neutral charcoal, Final Cut Pro-style — the app forces dark mode,
/// so there is no light-mode variant.
///
/// Use `Theme.xxx` everywhere for surfaces, hairlines, text, and accent — never `Color.gray`,
/// `.secondary` for chrome, or `NSColor.*` in view code.
struct Theme {
    // MARK: Surfaces

    /// `--bg` — window/content background.
    static let bg = Color(hex: 0x1D1D1D)
    /// `--panel` — output bar, footer.
    static let panel = Color(hex: 0x232323)
    /// `--panel-2` — raised panel surface.
    static let panel2 = Color(hex: 0x2A2A2A)
    /// Console well background.
    static let consoleBG = Color(hex: 0x151515)

    // MARK: Hairlines

    /// `--line` — hairline separators.
    static let line = Color.white.opacity(0.07)
    /// `--line-strong` — footer top border.
    static let lineStrong = Color.white.opacity(0.12)

    // MARK: Text

    /// `--txt` — primary text.
    static let txt = Color(hex: 0xE8E8E8)
    /// `--txt-2` — secondary text.
    static let txt2 = Color(hex: 0x9F9F9F)
    /// `--txt-3` — tertiary text / section labels.
    static let txt3 = Color(hex: 0x6E6E6E)

    // MARK: Accents

    /// `--acc1` — light accent: Split badge, "Joining…" status, spinner.
    static let acc1 = Color(hex: 0xFFB23E)
    /// `--acc2` — control accent: primary buttons, checks, switches, progress, selection tint.
    static let acc2 = Color(hex: 0xF0622A)
    /// `--ok` — success.
    static let ok = Color(hex: 0x3FD68A)
    /// `--bad` — failure.
    static let bad = Color(hex: 0xFF6B6B)
}

extension Color {
    /// Build a Color from a 24-bit RGB hex literal (e.g. `0xF0622A`).
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
