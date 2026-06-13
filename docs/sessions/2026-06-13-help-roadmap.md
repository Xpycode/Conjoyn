# Session: 2026-06-13 (k) — Roadmap help topic

## Goal
Add a **Roadmap** page to the in-app Help, at the bottom of the sidebar — a user-facing
look at where Conjoyn is headed.

## Progress
- **Audited the existing Help feature first** (the `/status` was scoped to "the app help we provide").
  Confirmed Help is fully shipped, not backlog: vendored `HelpMenu` SPM package
  (`01_Project/HelpMenu/`), 9 markdown topics in 4 groups via `help-manifest.json`, wired to both the
  `?` toolbar button (`ContentView.swift:84` → `HelpWindowController.showHelp()`) and the Help menu
  (`ConjoynApp.swift:96` `HelpMenuCommands`). The old PROJECT_STATE backlog item (7) was stale.
- **Verified what's genuinely *future* and user-facing** before drafting, so the roadmap wouldn't lie:
  - **Watch-folder ingest** — in the spec's v1 scope but **never shipped** (only a stale comment at
    `RecordGroup.swift:10`; no `FSEvents`/watch service exists). Legit roadmap item.
  - **More camera families** (GoPro / DJI Osmo) — engine is already camera-agnostic; gated in `ideas.md`.
  - **Auto-update deliberately omitted** — it ships *in* 1.0 (first public DMG = first Sparkle build),
    so a user reading the page already has it. Listing it would read as "coming soon" for a live feature.
  - Single-file export and the rebrand are **done**, not roadmap.
- **Shipped the topic** (`2655aaf`, merged `--no-ff` via `feature/help-roadmap`, pushed `main`):
  - New `01_Project/Conjoyn/Help/help-roadmap.md` — voice-matched to the other topics, framed as
    **plans not dated promises** (Planned: watch-folder, more cameras; Exploring: a metadata-grouping
    "works with anything" mode; a soft "Have a request?" close).
  - One manifest row appended, `group: "Reference"` → renders as the **last item under Reference**
    (user's chosen placement over a new bottom group).
- **Confirmed it bundles + builds.** `xcodegen generate` (recursive `Conjoyn/` source ref auto-classifies
  the `.md` as a resource — no `project.yml` edit). Clean ad-hoc-signed Debug build **SUCCEEDED**; the
  `.md` is present in the built bundle at `Contents/Resources/help-roadmap.md` (1427 B). App launched.

## Decisions
- **Placement = last item under Reference**, not its own bottom group (user pick via question).
- **Content drafted from the dev backlog, but only honest user-facing futures** — watch-folder and
  multi-camera. Auto-update excluded on purpose (ships in 1.0). No dates, no commitments.
- **Content-only change, no Swift / no build config.** The `HelpMenu` package renders whatever the host
  bundle supplies; adding a topic is `.md` + manifest row + xcodegen regen. `.xcodeproj` is gitignored,
  so the commit is just the two content files.

## Next
- **Content tuning (optional):** eyeball the live page; decide if the watch-folder / GoPro framing is
  too committal or anything's missing.
- **Feedback link:** the "Have a request?" section is intentionally link-less — wire it to a real
  channel (the `web-php-feedback-form` cookbook pattern) once the site has one. Naturally pairs with
  **Sparkle Wave 4** (website standup).
- **DMG still lags `main`** (now + Roadmap topic, on top of light-theme/menu/logging) — re-cut before
  any public link.
- Only public-1.0 gate unchanged: **Sparkle Wave 4** (website + appcast/DMG hosting).
