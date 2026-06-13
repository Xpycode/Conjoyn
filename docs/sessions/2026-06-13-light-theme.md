# Session: 2026-06-13 — Light theme (Auto/Light/Dark)

## Goal
Add a user-selectable appearance (Auto/Light/Dark). The app was hard-pinned to dark; user wanted a
toggle, and — with no Settings scene — the main menu as its home.

## Key finding
`.preferredColorScheme(.dark)` (`ConjoynApp.swift`) was **not** what made the app dark — the colors
live in `Theme.swift` as fixed sRGB hex literals that don't adapt. Flipping the scheme alone would
give a light titlebar over near-black content with invisible text. A real light mode = a second
palette + making every token adaptive. **The win:** all 136 `Theme.` usages funnel through one struct
(dark-mode discipline held — zero stray `NSColor`/`.gray`/`.secondary` in views), so colors change in
one file, not 136 call sites.

## Decisions (user-chosen)
- **Default = Dark** — preserve the FCP-style charcoal out-of-box; Light/Auto are opt-in. Fresh install
  looks identical to today's shipped build.
- **Menu = top-level "Appearance"** (not `View › Appearance` submenu). Note: macOS already provides a
  system `View` menu (Show Tab Bar / Enter Full Screen), so a separate top-level menu avoids confusion.
- **Light palette = soft neutral gray** (light gray surfaces, not pure white — matches the dark theme's
  restraint). Accents (amber/orange/green/red) unchanged in both modes.
- **`.auto` label = "Match System"** — widens the (correctly content-sized) dropdown so it reads as
  intentional under the longer title.

## Implementation
- **`Theme.swift`** — 13 tokens now adaptive via dynamic `NSColor(name:dynamicProvider:)` resolving
  against the window's live `NSAppearance`. New light palette (`bg #F4F4F4` … `txt #1E1E1E`, hairlines
  flip white→black). Two chrome helpers: `Theme.raised(α)` (white↔black overlays — hovers, raised
  fills, borders) and `Theme.recessed(α)` (wells — scaled to 45% alpha in light so insets aren't heavy
  gray blocks). New `Color(light:dark:)` initializer; `Color(hex:)` kept for mode-independent accents.
- **`DesignControls` / `RenamePopover` / `RecordingsList`** — 18 inline `.white/.black.opacity()` chrome
  colors swapped to the helpers; 2 stray hardcoded hex made adaptive (thumbnail placeholder,
  empty-state glyph → `txt3`). Left the glossy button top-sheen as white (intentional highlight).
- **`ConjoynApp.swift`** — `AppearancePreference` enum (raw `auto`/`light`/`dark`, `@AppStorage`
  persisted, default `.dark`) + `AppearanceCommands` (top-level `CommandMenu("Appearance")`, inline
  Picker, `EmptyView` label to suppress a redundant header). `.preferredColorScheme(appearance.colorScheme)`
  (`nil` = follow system).

## Result
- Build clean (Swift 6, dynamic NSColor providers compile under strict concurrency). Light mode
  live-confirmed by user ("looks really good" / "much better").
- **Divergence from the App Shell Standard** (which mandates `.preferredColorScheme(.dark)`, dark-only)
  — flagged to user; Conjoyn is the first app in the family to offer light mode.

## Git
- Isolated on **`feature/light-theme`** (rebased onto `feature/sparkle-update` tip `94477be`), one
  commit (theme code) + this doc commit. Based on sparkle-update because the `ConjoynApp.swift` theme
  edits sit alongside the Sparkle `UpdaterCommands` code; natural merge order is Sparkle → `main` first,
  then light-theme.

## Owed / next
- Light-mode accent eyeball: flip a recording to done/warning in Light, check the green seal / red chip
  aren't too pale on the light surface (trivial per-mode darkening if so).
- Decide whether to merge to `main` independently or after Sparkle Wave 4.
