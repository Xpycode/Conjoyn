# Eyeball-Session Fixes — 2026-06-11e

> 6 items found during the first full live test (2 jobs, real 2CULL card).
> Wave 1 = bug fixes (4 tasks, all independent).
> Wave 2 = new UI features (2 tasks).
> ETA-includes-verification scoped but deferred — see note at bottom.

---

## Wave 1 — Bug fixes (run in parallel)

### Task 1 · "Processing…" label for single-file jobs

**Problem:** `statusText` in `QueueRow` always says "Joining…" for active jobs, even for single-file
export (which is a bitstream copy, not a join).

**Target:** `01_Project/Conjoyn/Views/QueuePanel.swift` line 382

**Change:**
```swift
// BEFORE
case .active:
    return job.verificationStatus == .verifying ? "Verifying…" : "Joining…"

// AFTER
case .active:
    if job.verificationStatus == .verifying { return "Verifying…" }
    return job.clips.count == 1 ? "Processing…" : "Joining…"
```

**Done when:** Build green. `statusText` for a 1-clip active job returns "Processing…"; for 2+ clips
returns "Joining…". Add 2 unit tests in `QueuePanelTests` (or `ConversionJobTests` if the property
moves there).

---

### Task 2 · Chip filter: suppress `.info` severity

**Problem:** `verificationSection` filters chips with `severity > .pass`, which includes `.info` (a
normal within-1-frame duration delta from `-fflags +genpts`). The orange ⚠ Duration chip appears on
every successful join, looking like an error when it's just a known artefact.

**Root cause confirmed:** `compareDuration` returns `.info("Δ Nms (within ±1 frame)")` when the
delta is ≤ 1 frame (40 ms at 25 fps). The current filter `severity > .pass` catches `.info`
(severity = 1). Only `.warning` (2) and `.fail` (3) should be chipified.

**Target:** `01_Project/Conjoyn/Views/QueuePanel.swift` line 601

**Change:**
```swift
// BEFORE
let flagged = (job.sourceTargetResult?.checks ?? []).filter { $0.severity > .pass }

// AFTER
let flagged = (job.sourceTargetResult?.checks ?? []).filter { $0.severity >= .warning }
```

**Done when:** Build green. A completed job whose only non-pass check is a `.info` Duration delta
shows no chips and "No issues flagged." text (not the orange ⚠ Duration chip). Add 1 unit test.

---

### Task 3 · mapStatus: thorough hash pass → `.verified`

**Problem:** When Tier 1 flags a `.warning` (e.g. A/V drift or duration > 1 frame) and auto-escalates
to Tier 2, a passing byte-exact hash proves the data is intact — but `mapStatus` still returns
`.warning` (orange seal) because it uses `result.passed` which is worst-wins across ALL checks
(Tier 1 warnings are still in the check list). The seal stays orange even after the hash confirms
lossless integrity.

**Target:** `01_Project/Conjoyn/Services/QueueManager+Verification.swift` lines 268-276

**Change:**
```swift
func mapStatus(_ result: SourceTargetResult) -> VerificationStatus {
    // Tier 2 byte-exact hash: if the hash check exists and passed,
    // the join is lossless regardless of Tier 1 container-metadata discrepancies.
    if result.tier == .thorough {
        let hashPassed = result.checks.first { $0.kind == .hashMatch }?.severity == .pass
        if hashPassed { return .verified }
    }
    if result.passed { return .verified }
    if result.hasWarning { return .warning(result.summary) }
    return .failed(result.firstFailureReason ?? result.summary)
}
```

**Done when:** Build green. After a thorough verify where the hash passes, seal is green
`checkmark.seal.fill`. Add 1 unit test: mock a `SourceTargetResult` with `.thorough` tier,
a `.warning` Duration check, and a `.pass` hashMatch check → `mapStatus` returns `.verified`.

---

### Task 4 · Seal animation: immediate stop on terminal state

**Problem:** `VerificationSeal` uses `@State var spin` with `.linear.repeatForever()`. When the
status transitions from `.verifying` to a terminal state (`onChange` sets `spin = false`), SwiftUI
applies `.default` (spring) animation to the rotation snapping back to 0°, which can appear as a
brief continued spin. The `onAppear` path is also fragile: if the view mounts after the status is
already terminal (queue restored from disk), spin stays false but could be mis-set.

**Target:** `01_Project/Conjoyn/Views/QueuePanel.swift` lines 661-677 (`VerificationSeal`)

**Change:** Use explicit `withAnimation(nil)` to immediately cancel the rotation:
```swift
.onAppear {
    spin = (status == .verifying)
}
.onChange(of: status) { _, new in
    if new == .verifying {
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
    } else {
        withAnimation(nil) { spin = false }  // immediate — no spring snap-back
    }
}
```

Remove the animation modifier on the view (it's now driven by the explicit `withAnimation` calls):
```swift
.rotationEffect(.degrees(spin ? 360 : 0))
// .animation(...) modifier removed — animation is controlled by withAnimation in handlers
```

**Done when:** Build green. Manual test: watch a join complete — the rotating arrow should stop
cleanly (no snap-back spin). Verify the seal still rotates during verification.

---

## Wave 2 — New UI features (independent, run after Wave 1 passes)

### Task 5 · Queue restore banner

**Problem:** `queue.json` reloads silently on every launch. Users who cleared their card and quit
the app properly are surprised to find old jobs still in the queue.

**Approach:**
1. Track restored count in `QueueManager.loadQueue()` — already computed at line 267/269 but only
   logged to console. Expose it as `@Published var restoredJobCount: Int = 0`.
2. Surface a dismissable banner in the queue section header (`QueuePanel`) when
   `restoredJobCount > 0`:
   - Text: "Restored N job(s) from last session"
   - **Dismiss** button: sets a local `@State var bannerDismissed = true`
   - **Clear pending** button: calls `queue.clearPending()` (existing or add if missing) + dismisses

**Target files:**
- `01_Project/Conjoyn/Services/QueueManager.swift` — add `@Published var restoredJobCount: Int = 0`;
  set it in `loadQueue()` where the restoration count is already computed.
- `01_Project/Conjoyn/Views/QueuePanel.swift` — add `RestoreBanner` sub-view; render it above the
  job list when `queue.restoredJobCount > 0 && !bannerDismissed`.

**Done when:** Build green. On first launch after a prior session, the banner appears. Dismiss hides
it for that session. Clear Pending removes pending jobs and hides the banner. No banner if queue was
empty on restore.

---

### Task 6 · Queue row: job type + duration + expected size

**Problem:** Once a recording is added to the queue, the row shows filename, TC, and output path —
but loses the SINGLE/SPLIT badge, duration, and file size that are visible in the recordings list
above. Users can't confirm what they queued without scrolling back up.

**Approach:**
1. Add `var totalSourceBytes: Int64` to `ConversionJob` (computed):
   ```swift
   var totalSourceBytes: Int64 {
       clips.reduce(0) { $0 + $1.totalFileSize }
   }
   ```
2. In `QueueRow.liveMetrics`, add a **static summary** branch that shows when the job is NOT active:
   ```swift
   // Pending / completed (not active): show type · duration · size
   HStack(spacing: 6) {
       Text(job.clips.count == 1 ? "SINGLE" : "\(job.clips.count) files")
           .font(.system(size: 10, weight: .semibold))
       Text("·")
       Text(CJFormat.duration(job.totalContentDurationSeconds))
       Text("·")
       Text(CJFormat.size(job.totalSourceBytes))
   }
   .font(.system(size: 11))
   .foregroundStyle(Theme.txt3)
   ```
   The 140 pt `liveMetrics` frame is currently empty for pending and completed rows — this fills it.

**Target files:**
- `01_Project/Conjoyn/Models/ConversionJob.swift` — add `totalSourceBytes`.
- `01_Project/Conjoyn/Views/QueuePanel.swift` — extend `liveMetrics` with static branch.

**Done when:** Build green. A pending queue row shows e.g. `SINGLE · 5:14 · 1.4 GB` or
`4 files · 51:39 · 13.7 GB` in the 140 pt column. During active joining the column shows the live
speed/ETA as before. After Done it reverts to the static summary.

---

## Deferred: ETA includes verification time

**Observation:** The footer ETA shows "~3 min left" and then hits "< 1 min left" while verification
adds untracked wall-clock time (Tier 2 hash at ~340 MB/s can take 30–60 s on a 13 GB job).

**Why deferred:** Estimating verification time needs output file size + a stored read-speed baseline.
Output file size is available after join (`actualOutputURLs.first` via `FileManager`), but read speed
isn't currently tracked separately. Scoping as a separate plan item once the Wave 1 bugs are clean.

**Potential approach (for next plan):**
- After join completes, `stat()` the output file to get its size.
- Estimate Tier 2 time as `outputBytes / observedReadSpeed`. For the observed read speed, reuse the
  ffmpeg write speed (join phase write ≈ read during Tier 2).
- Add an estimated `+N s (verification)` to `remainingQueueSeconds(at:)` while verification is pending.

---

## Backpressure for all tasks

```bash
xcodebuild -scheme Conjoyn -destination 'platform=macOS' build 2>&1 | tail -3
xcodebuild test -scheme Conjoyn -destination 'platform=macOS' 2>&1 | grep -E 'passed|failed|error'
```

All tasks: build green + existing test count doesn't drop.
Tasks 1–3: add the unit tests called out above (expect ~+4 tests → 319/319).
Tasks 5–6: UI-only, no new unit tests required (manual eyeball is the gate).
