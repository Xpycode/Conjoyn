# Session: 2026-06-13 (j) — Persistent diagnostic logging (closes the /minimums gap)

## Goal
Run `/minimums` against the shipped app and close any real gap before public 1.0.

## Progress
- **Ran `/minimums`** (verified against the *code*, not just the project log). Result: everything
  covered except **one** genuine gap, plus one deliberate omission:
  - **Gap — persistent diagnostic logging.** `QueueManager.log()` wrote only to an in-memory console
    buffer (`consoleLines`, trimmed to 5000); nothing on disk. A bug filed after a quit/relaunch had
    no retrievable log. (No `OSLog`/`NSLog`/`print` either.)
  - **Deliberate omission — no Preferences window (⌘,).** Confirmed with the user to keep it (the
    earlier "no Settings scene — unnecessary" decision stands; appearance lives in its own menu).
  - Everything else (auto-update, version-in-UI, signing/notarization, app icon, empty/loading/error
    states, keyboard shortcuts, About, menu bar) already present.
- **Shipped `DiagnosticLogger`** (`01_Project/Conjoyn/Services/DiagnosticLogger.swift`, commit
  `5a11fc6`):
  - File-backed log at `~/Library/Application Support/Conjoyn/diagnostic.log`.
  - `@MainActor` singleton + **injectable storage dir** (matches `SpeedTracker`/`QueueManager` so
    tests use a temp dir), ISO-8601 stamps, per-session banner with the bundle version.
  - Append via `FileHandle.seekToEnd`; **single-generation rotation** → `diagnostic.log.1` at 1 MB
    (`maxBytes`). Every `FileManager`/`FileHandle` call is `try?` — logging can never crash the app.
  - **One line** in `QueueManager.log()` mirrors every existing message to the file, so all ~56
    call sites persist for free (the one-chokepoint pattern, like the light-theme `Theme` tokens).
- **Confirmed the cheap-write assumption:** all `log()` calls are coarse, event-level (job
  start/SUCCESS/FAILED/resolution milestones). The high-frequency `speed=`/progress stream flows
  through `activeMetrics`, *not* `log()`, so synchronous main-thread file writes cost nothing.
- **`DiagnosticLoggerTests` (7):** banner+version, append, ordering, injected dir, rotation,
  `.1` replacement, no-rotate-below-threshold. Rotation tested by **pre-seeding** an oversized log
  (cheaper than writing 1 MB line-by-line) and letting the init banner trip rotation.
- **Full suite: 337 tests, 1 skip, 0 fail.** Debug build SUCCEEDED (ad-hoc signed — this is a
  release-only Mac with no *Mac Development* cert, per the 2026-06-13 (i) note).

## Decisions
- **File logging via a single chokepoint, not a new logging API.** Route through the existing
  `QueueManager.log()` rather than sprinkling new calls — zero call-site churn, and the console +
  file stay in lockstep by construction. Logged to `docs/decisions.md`.
- **Rotation = rotate-to-`.1` at 1 MB** (vs. truncate-front or reset). Best cross-session retention
  (the relaunch-bug case) for a bounded ~2 × `maxBytes` disk cost; trivial to implement. Constraint:
  `rotateIfNeeded()` must never throw (runs inside every append).
- **Keep no Preferences window.** Re-affirmed; not a gap.

## Next
- **Owed — one live eyeball:** run the app, do a real join, confirm
  `~/Library/Application Support/Conjoyn/diagnostic.log` materializes with the session banner +
  job events and the version stamp reads correctly outside the test host. (Engine path is
  unit-covered; this just checks the real bundle.)
- **DMG still lags `main`** (light-theme + menu + now logging) — re-cut before any public link.
- Only public-1.0 gate remains **Sparkle Wave 4** (website standup + appcast/DMG hosting).
