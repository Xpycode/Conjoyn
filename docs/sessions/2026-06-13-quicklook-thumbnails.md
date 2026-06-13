# 2026-06-13 (g) — QL thumbnail fix: QuickLook-first row thumbnails with FFmpeg fallback

**Backlog item (3).** Shipped to `main` + pushed (`ab6d140`).

## What & why
The recordings list drew each row's poster frame by shelling out to **FFmpeg per clip**
(`-ss -i -frames:v 1 -f image2pipe`). Costs: a heavyweight subprocess in-process per visible row
(throttled to 3 via a hand-rolled semaphore), contention for the same disk-read budget as the
post-scan metadata/SRT work, and a full re-decode on every scan (no cache).

Switched to a **hybrid**: `QLThumbnailGenerator` primary, FFmpeg fallback.

- **QuickLook decodes out-of-process** in the system Thumbnails agent
  (`com.apple.quicklook.ThumbnailsAgent`) → the decode load leaves the app, easing the contention.
- **System-cached** on file + mtime + size → a re-scan of the same card returns **instantly**.
- **FFmpeg first-frame kept as a fallback** for any file QuickLook can't read → the throttle
  semaphore / kill-poll / `ContinuationGuard` machinery is *demoted* to the rare-miss path, not
  deleted. No blank tiles ever.
- **Dropped the unused last-frame extraction** — the row only ever displayed `first ?? last`, so the
  last frame was a second subprocess per clip for a frame shown only if the first failed. `last` is
  now always nil; the struct field is kept so call sites / `ClipThumbnails` don't churn.

## Load-bearing details
- **`representationTypes: .thumbnail` only.** `.icon`/`.all` may "succeed" with the generic
  movie-file icon, which returns without throwing → would suppress the fallback and show the same
  glyph on every row. The catch→`nil` is the fallback control flow, not error-swallowing.
- **`import QuickLookThumbnailing` auto-links** — no `project.yml`/xcodegen/`.framework` change.
  SourceKit's "Cannot find type `FFmpegWrapper`/`DJIClip`" and "No such module 'XCTest'" were false
  (whole-module index not loaded); the real `xcodebuild` build was clean.
- **size/scale = 320×180 @ scale 2** — matches the FFmpeg path's old `maxWidth: 320`, keeps the
  ~67×38 pt `.aspectRatio(.fill)` Retina tile crisp without over-rendering.

## Files
- `01_Project/Conjoyn/Services/ThumbnailManager.swift` — `import QuickLookThumbnailing`;
  `extractThumbnails` now QL-first → FFmpeg fallback, no last frame; new `generateQuickLookThumbnail`.
- `01_Project/ConjoynTests/ThumbnailManagerTests.swift` — integration test renamed + flipped to the
  new contract (`first` non-nil via QL-or-fallback, `last` intentionally nil). The "missing source →
  empty but still cached" test unchanged (QL throws → FFmpeg nil → both nil, result cached).

## Verification
- Clean build cycle (killed app → wiped DerivedData → xcodegen → build). **BUILD SUCCEEDED.**
- **330 pass / 1 skip / 0 fail.**
- Launched on a real card — **user-confirmed "definitely faster"** (the system-cache re-scan win).

## Caveat
QuickLook picks its *own* representative poster frame (≠ exact frame 0). For DJI footage that's
usually a feature (avoids black leader frames) and matches what Finder shows, but it is a behavior
change. Tune via the FFmpeg fallback timestamp if a specific clip ever looks wrong.

## Captured
Pattern → **cookbook #94** `94-macos-quicklook-thumbnail-hybrid.md` (+ index entry).

## Gotcha logged
`main` had no upstream branch → the first `git push` **silently no-op'd** (exit 0, no transfer). Tell:
`git status -sb` showed `## main`, not `## main...origin/main`. Fixed with `git push -u origin main`
(`b9089bd..ab6d140`). Matters here because history travels **only** via `origin` (Syncthing excludes
`.git`) — a silent no-push means other Macs never see the work.

## Next
Only **Sparkle Wave 4** (website standup + appcast/DMG publish) gates 1.0-public. Optional polish:
custom DMG background; nil-date sort policy (`.distantPast` vs Finder "undated always last").
