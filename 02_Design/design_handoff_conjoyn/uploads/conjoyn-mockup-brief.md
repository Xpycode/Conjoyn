# Conjoyn — UI Mockup Brief

> Handoff doc for a Claude Design session. Self-contained — no other files needed.
> Goal: produce macOS app UI mockups for **Conjoyn**.

---

## Summary

**Conjoyn** is a native macOS app (macOS 14+, Apple Silicon, SwiftUI) that **auto-stitches
split action/drone-camera video back into single, whole files — losslessly.**

When a camera fills a memory-card file at the ~4 GB limit, one continuous recording gets
chopped into several numbered segments. Conjoyn scans a folder, figures out which segments
belong to the same original recording, joins them back together without re-encoding (no
quality loss), repairs the recording date and timecode metadata, and re-stitches the separate
telemetry/subtitle sidecar files so they stay perfectly in sync.

**Tagline:** *"Split recordings, made whole."*

---

## Who it's for

Drone and action-camera shooters (and editors) ingesting a full memory card who want clean,
single, correctly-dated clips before they touch an editor — without manually hunting down and
concatenating fragments by hand.

---

## Core user flow (the spine of the UI)

1. **Pick a source folder** (or point at an SD card).
2. **Scan** → the app discovers all clips and **groups them by recording**, auto-detecting
   which are split sets vs. standalone clips.
3. **Review & select** → each discovered recording is a row with a checkbox; multi-segment
   (split) recordings are pre-selected, standalone single clips are not — so a full card
   doesn't queue dozens of no-op jobs.
4. **Set output** → destination folder + options (fix-date, preserve-timecode, stitch-telemetry).
5. **Add to queue → Start** → each selected recording joins in turn, with live progress.
6. **Watch the queue + console** → per-job progress, success/fail, retry, reveal-in-Finder.
7. **Done** → whole, correctly-dated files (plus stitched telemetry) in the output folder.
8. *(Secondary mode)* **Watch-folder** — point Conjoyn at an ingest folder and it
   auto-processes complete recordings as cards are copied in.

---

## Window layout

Single primary window. Top-to-bottom flow mirrors the steps above.

- **Header / source bar (top):** app identity, the chosen **source folder** path with a
  "Choose…" button, and a **Scan** action. (Steps 1–2.)
- **Discovered recordings list (upper main area — the hero region):** a scrollable list of
  grouped recordings. Each **row** shows: a checkbox; a thumbnail; the recording name/range;
  segment count (e.g. "3 segments"); total duration; total size; and a small badge
  distinguishing **Split** vs **Single**. Above the list: **All / None / Splits** quick-select
  buttons and a live "N of M selected" count.
- **Output settings (between list and queue):** destination folder picker, plus a compact set
  of toggles — *fix recording date*, *preserve/restamp timecode*, *stitch telemetry sidecar* —
  and an **Add to Queue** button.
- **Job queue (lower main area):** one row per queued/running/finished job with a **progress
  bar**, status (queued / joining / done / failed), and per-row actions: **retry**, **remove**,
  **reveal in Finder**.
- **Live console (collapsible, bottom):** scrolling technical log of what's happening (power
  users / troubleshooting); collapsed by default in the mockup.
- **Footer bar (bottom):** primary **Start / Stop** control, overall progress, and overall
  counts (e.g. "14 of 14 joined, 0 failed").

---

## States to mock (please render these)

1. **Empty / first launch** — no folder chosen; friendly "Choose a folder or drop a card to
   begin" prompt.
2. **Scanning** — progress indicator while discovering clips.
3. **Groups loaded** — populated recordings list with splits pre-selected and the select-all
   controls. **(The money shot.)**
4. **Queue running** — several jobs, one mid-progress, footer showing live totals.
5. **Done** — all jobs complete, success summary in the footer.
6. *(Optional)* **Watch-folder mode** — a calmer, monitoring-style variant.

> Prioritize **#3 (groups loaded)** and **#4 (queue running)** — they carry the product's whole
> value proposition and reveal fastest whether the layout reads at real-world clip counts.

---

## Visual style direction

- **Dark, "Final Cut Pro / pro-video tool" aesthetic** — deep charcoal-navy surfaces, layered
  panels with subtle separation, a single luminous accent.
- **Accent color:** cyan-to-blue gradient `#34E0FF → #2A6CF0`. Use it for selected rows,
  progress bars, and the primary Start button; keep everything else muted neutral so content
  (clips, progress) leads.
- **Background surfaces:** midnight blue `#10141F` → charcoal-navy `#222A3D`.
- Clear typographic hierarchy: recording names prominent; metadata (count/duration/size) as
  quiet secondary text.
- Native macOS conventions throughout — standard window chrome, list affordances, system
  controls. It should feel like a first-party macOS pro app, not a web app in a window.
- **Density:** information-dense but calm. A full card might show 70+ clips grouped into ~14
  recordings, so the list must stay scannable at volume.
