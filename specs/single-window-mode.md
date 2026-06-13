# Spec — Single-Window Mode (disable multi-window / tabs)

> Status: **proposed** · Author: session 2026-06-13 · Scope: tiny (one scene type swap)
> Related: `ConjoynApp.swift`, cookbook #50 (detachable windows — the *opposite* choice)

## Problem

`ConjoynApp` declares its UI with `WindowGroup` (`ConjoynApp.swift:80`). On macOS,
`WindowGroup` automatically grants **multi-window + native window tabbing**: a "New Window"
item in the File menu (⌘N), `View › Show Tab Bar`, and ⌘T to spawn a tab.

But Conjoyn is a **single-shared-state utility**: one `@StateObject viewModel` and one
`QueueManager` are created at the App level (`ConjoynApp.swift:25,28`) and injected into the
tree. A second window or tab therefore renders the **same** queue, scan, and selection — not an
independent document. The capability is **incidental to `WindowGroup`, not designed for**, and a
duplicate window invites confusion (two windows mutating one queue, with no visible signal they're
mirrors).

## Goal

Make the window model match the app model: **exactly one main window**, no New Window, no tab bar.

### Non-goals
- Per-window documents (that's option 3 — a real per-window view model; explicitly out of scope).
- Touching the Help window (separate AppKit `HelpWindowController` — unaffected).
- Any change to queue/scan/persistence behavior.

## Approach

Swap the single `WindowGroup` scene for a single-instance `Window` scene. `Window` is the SwiftUI
scene for "one window, one instance" — it does **not** synthesize "New Window" and has **no tab
bar**, so both come off automatically with no menu surgery.

```swift
// ConjoynApp.swift — body
Window("Conjoyn", id: "main") {              // was: WindowGroup { … }
    ContentView()
        .environmentObject(viewModel)
        .environmentObject(viewModel.queue)
        .preferredColorScheme(appearance.colorScheme)
}
.windowStyle(.hiddenTitleBar)                 // unchanged — all carry over to Window
.windowResizability(.contentMinSize)         // unchanged
.defaultSize(width: 1240, height: 800)       // unchanged
.commands {                                  // unchanged
    FileCommands(viewModel: viewModel)
    HelpMenuCommands(content: helpContent, appName: "Conjoyn")
    UpdaterCommands(updater: updaterController)
    AppearanceCommands(appearance: $appearance)
}
```

The `"Conjoyn"` title is not visible (titlebar is hidden) but labels the window in Mission Control
/ the Window menu. The `id: "main"` is required by `Window` and is otherwise inert here.

## Impact / blast radius

- **One file, one scene-type change.** Verified no other code references multi-window APIs
  (`openWindow`, `handlesExternalEvents`, second scene, `scenePhase`, `@SceneStorage`).
- All four scene modifiers (`.windowStyle`, `.windowResizability`, `.defaultSize`, `.commands`)
  are valid on `Window` exactly as on `WindowGroup`.
- The custom `FileCommands` "Choose Folder…" (⌘O) and the rest of the menus are unaffected.

## What disappears (intended)

- File › **New Window** (⌘N) — gone (no longer synthesized).
- **Show Tab Bar** / ⌘T / "Merge All Windows" — gone (single-instance window can't tab).

## Risks / watch-items

1. **⌘N now unbound.** If any future feature wants ⌘N, it's free again. (None today.)
2. **Window restoration.** `Window` restores frame/size like `WindowGroup`; verify the app reopens
   at the saved size after quit/relaunch (low risk — same persistence machinery).
3. **`.defaultSize` vs restored frame.** First launch uses 1240×800; subsequent launches restore
   the user's last frame. Unchanged from today.
4. **Reopen-on-dock-click.** With a single `Window`, clicking the Dock icon after closing the window
   should reopen it. Confirm the closed-window → Dock-click → reopen path (AppKit default; verify
   it isn't swallowed by the hidden titlebar / `LSUIElement`-style config — Conjoyn is **not**
   `LSUIElement`, so default reopen applies).

## Acceptance criteria

- [ ] File menu has **no "New Window"** item; ⌘N does nothing (or is available for rebinding).
- [ ] No **Show Tab Bar** entry in the View/Window menu; ⌘T does not create a tab.
- [ ] App launches to one 1240×800 window (first run) and restores last frame thereafter.
- [ ] Closing the window then clicking the Dock icon reopens the (single) main window with queue
      state intact.
- [ ] Existing flows unchanged: scan, Choose Folder… (⌘O), queue/join, Appearance, Help (⌘?),
      Check for Updates.
- [ ] Full test suite green (330) — this is UI-scene-only, so no test changes expected.

## Rollback

Revert the single scene line `Window("Conjoyn", id: "main")` → `WindowGroup`. One-line undo.
