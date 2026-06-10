# Ideas & Task Flow

> **miniPM-style progression:** ideas/ -> specs/ -> doing/ -> done/
> Move items through phases as they progress.

---

## Ideas (Undeveloped)
<!-- Raw concepts, brainstorms, "what if" thoughts -->
<!-- Format: Brief description, date added, any initial notes -->

### Single-file export (stamp TC/date on lone clips)
**Added:** 2026-06-10 (user request during live test of the new UI)
**Type:** Feature

While we're a joiner, a **single-segment recording** should still be exportable: a copy/remux of
the lone clip that stamps the resolved recording date + start timecode (same
`RecordingStartResolver` chain as joins) and carries its `.SRT` over. Today the queue *accepts*
a 1-segment job but the engine fails it with `Invalid input: Need at least two segments to join
(got 1)` — observed live on the real card. Likely small: relax the ≥2-segment guard into a
single-input `-c copy` path with the identical metadata stamp + sidecar handling; decide how the
queue row/Add button should present it (it's an "export", not a "join").

---

### Tagline candidate: "Stitch Split Segments"
**Added:** 2026-06-09
**Type:** Branding

Alternative slogan for the **Conjoyn** rebrand, floated during the real-card GUI validation.
Imperative + alliterative; describes the literal verb. Sits alongside the current decision-log
tagline *"Split recordings, made whole."* — decide between them (or keep both: one as App Store
subtitle, one as marketing line) when the rebrand is actually executed.

---

### Revisit the GUI (design pass) — ✅ RESOLVED 2026-06-10
**Added:** 2026-06-09 · **Resolved:** 2026-06-10b — the design handoff
(`02_Design/design_handoff_conjoyn/`) was ported to SwiftUI and live-validated on the real card
(session `2026-06-10b.md`). Remaining: a sizing/position polish pass vs the prototype (queued in
PROJECT_STATE → Next).

---

### GoPro joining + app rebrand
**Added:** 2026-06-09
**Type:** Feature
**Gate:** Only after DJI joining works on the user's real files.

Extend the joiner beyond DJI to **GoPro** split recordings. GoPro chapters its long clips
(e.g. `GH011234.MP4`, `GH021234.MP4`, … — the `GHnn` chapter index sits *before* the shared file
number), which is a different naming scheme but the same underlying job: lossless concat-demuxer
re-join of self-contained MP4s. With a second camera family the app outgrows the "DJI" name —
candidate rebrand: **Fly Action Joiner** / **Join Action Fly (JAF)** (or something better TBD).

**Initial thoughts:**
- Engine is already camera-agnostic (concat `-c copy` + param guard + SRT stitch). Main new work is
  a **GoPro filename parser** + grouping rule alongside `DJIFilenameParser`/`DJIFolderReader.group`.
- GoPro telemetry is **GPMF embedded in the MP4 stream**, not a sidecar `.SRT` — different from DJI;
  the SRT-stitch path won't apply directly (separate handling or skip for v1 GoPro).
- Rebrand touches bundle id, app name, signing, icon, copy — do it as a deliberate step, not ad hoc.

**Next step:** once DJI join is validated on real footage, `/interview` a GoPro spec (naming schemes,
chapter ordering, GPMF handling) → `specs/`.

---

### Research: which camera systems split recordings (and how) ✅ DONE
**Added:** 2026-06-09 · **Completed:** 2026-06-09
**Type:** Exploration

**Findings → `docs/camera-split-research.md`** (brand-by-brand tables + sources; session log s3).
Headlines: universal cause = FAT32 4 GB cap (DJI/Autel/Canon split even on exFAT; 29:59 is a separate
*stop*, not a split). **Two families: GoPro alone encodes continuity in the filename; everyone else
increments a counter → must group by metadata** (validates our core decision). Pluggable seam is
small (per-brand filename parser + optional AVCHD `.MPL` reader; everything else shared). AVCHD is
legacy → defer. **Product gap confirmed:** nobody does auto-detect + multi-brand + lossless +
telemetry + watch-folder ingest.

---

### App name-finding session (rebrand off "DJIjoiner") ✅ NAME CHOSEN
**Added:** 2026-06-09 · **Resolved:** 2026-06-09
**Type:** Branding / chore
**Priority:** Before first public release (not gated on multi-camera).

The research made the case: "DJIjoiner" locks in the one brand we've proven we'll outgrow, **and**
shipping a notarized/distributed app with "DJI" in the name is a trademark risk regardless of the
multi-camera plan. Two issues: (a) renaming costs more every release (bundle id, signing identity,
muscle-memory, docs/landing); (b) the trademark exposure is independent of the multi-camera roadmap.

**Outcome:** Name-finding session run 2026-06-09. Scope = fully camera-agnostic; style = coined/
evocative; full availability vetting (web + App Store + domain). **Chosen: `Conjoyn`** (coined
conjoin+join; zero collisions; trademark-strong). Runners-up: Unsplit (descriptive), Reelm
(domain likely taken). Killed in vetting: Weldr, Onecut, Splyce, Mendr, Continua, Spool, Seamr.
Full rationale in `docs/decisions.md` (2026-06-09 entry).

**Clearance: DONE (sufficient for a free app).** USPTO exact-match search = **no results** for
"Conjoyn" (2026-06-09); web + App Store + user's Kagi/Google also clean. A free app's realistic risk
is a rename-demand, not damages, so a coined name no software product uses is adequate — no paid
search / EUIPO / self-registration needed.

**Remaining (rebrand chore — promote to a task when ready):** execute the rename as one deliberate
step. The project is **confirmed xcodegen-driven** (build-verified 2026-06-09), so this is a regen,
not a hand-patch: edit `project.yml` (name + `PRODUCT_NAME` + `PRODUCT_BUNDLE_IDENTIFIER` →
`com.lucesumbrarum.conjoyn`) → `cd 01_Project && xcodegen generate`; rename the `DJIjoiner`/
`DJIjoinerTests` source folders + `.entitlements` + `*App.swift`; app icon; in-app copy; CLAUDE.md +
docs; git repo/folder name. Bundle-id change has no installed-base cost yet (pre-1.0, no shipped
Sparkle feed / Keychain / sandbox storage).

---

### Open strategic questions from the research session (2026-06-09)
**Type:** Product judgement — parked, revisit when multi-camera planning starts

Captured so we don't lose them (raised during the multi-brand research debrief):

1. **Is GoPro really the right "phase 2"?** It's the obvious pick (biggest audience, clean
   filename grouping) but the *most contested* — ReelSteady & Gyroflow already do GoPro joining +
   telemetry well. DJI/Osmo owners are comparatively *underserved*. Contrarian option: deepen
   **DJI Osmo Action/Pocket** coverage first (shares our `DJI_NNNN` scheme, reuses the engine almost
   for free, less competition) before taking on GoPro's incumbents. GoPro = headline; Osmo = cheaper,
   less-contested win.
2. **Telemetry doesn't port for free — budget for it.** Our SRT stitcher is DJI-specific (subtitle
   sidecar). GoPro = **GPMF** (binary data track *inside* the MP4, needs `-map`/tag handling);
   Walksnail = `.osd`. The *video join* is truly brand-agnostic; *telemetry* is bespoke per brand and
   is where phase-2 scope will balloon. Plan accordingly.
3. **Pull the stream-parameter hard gate into v1?** Every research angle landed on it as *the*
   correctness backbone (refuse/warn on codec/res/fps mismatch rather than emit a corrupt `-c copy`).
   It's brand-agnostic, so it pays off on DJI *today*. **Action item:** confirm `processConcatenateJob`
   actually gates on it before joining (vs. only using it during grouping). Cheap correctness
   insurance for v1.
4. **Near-free "works with anything" mode.** The grouping core needs *zero* filename knowledge (runs
   on stream params + creation_time continuity), so the app could accept footage from un-parsed
   brands via generic metadata grouping — a quiet "experimental: other cameras" path that makes us
   multi-brand *before* the rebrand. Low-cost optionality we already own.
5. **Product thesis to put atop the spec:** "auto-detect + multi-brand + lossless + telemetry +
   watch-folder, and no existing tool does all five." That one sentence is the differentiator the
   research validated.

---

## Specs (Ready to Plan)
<!-- Ideas that have been through discovery interview -->
<!-- Each should have acceptance criteria and scope defined -->

*See `specs/` folder for full spec documents*

| Spec | Status | Created |
|------|--------|---------|
| [spec-name.md] | ready | [date] |

---

## Doing (Active Work)
<!-- Currently being implemented -->
<!-- Should have IMPLEMENTATION_PLAN.md entry -->

| Feature | Plan | Started | Wave |
|---------|------|---------|------|
| [name] | IMPLEMENTATION_PLAN.md | [date] | 2/3 |

---

## Done (Completed)
<!-- Recently completed, before archiving -->

| Feature | Completed | Commits | Session |
|---------|-----------|---------|---------|
| [name] | [date] | abc123 | 2026-01-26.md |

---

## Archived
<!-- Old ideas that were dropped or superseded -->
<!-- Keep brief notes on why -->

| Idea | Reason | Date |
|------|--------|------|
| [name] | [why dropped] | [date] |

---

## Auto-Detection Triggers

When user says... | Action
------------------|--------
"I have an idea" | Create entry in Ideas section
"Let's spec this out" | Run `/interview`, create in specs/
"Let's build [X]" | Move to Doing, create/update IMPLEMENTATION_PLAN.md
"[X] is done" | Move to Done, update PROJECT_STATE.md
"Drop [X]" | Move to Archived with reason

---

## Flow Commands

| Command | Action |
|---------|--------|
| `/ideas` | List all ideas with status |
| `/ideas add [name]` | Quick-add to Ideas section |
| `/ideas promote [name]` | Run interview, move to specs/ |
| `/ideas start [name]` | Move to Doing, create plan |
| `/ideas done [name]` | Move to Done, archive |

---

*Ideas are cheap. Specs are commitment. Plans are execution.*
