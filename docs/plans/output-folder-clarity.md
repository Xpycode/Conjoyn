# Plan — Output-folder ↔ queue clarity (A + B)

## Context

**The trap (hit live 2026-06-10k):** `addToQueue()` (`ConversionViewModel.swift:158–192`)
**freezes** each job's `destinationURL` at enqueue time from the then-current `outputFolderURL`.
Per-job freezing is *correct* for a queue — the defect is **no feedback**: changing the Output
folder after queuing silently governs only *future* adds, and rows never show where a job will
actually land. The user changed the folder, re-pressed Start, and files went to the old place
with no warning.

**Two fixes, both approved:**
- **A — Transparency (Hybrid):** show each job's destination in the per-row timecode
  disclosure panel (always), **plus** an inline ⚠ badge + sub-line on a row **only when** that
  job's destination folder differs from the current Output-bar folder (the stale case).
- **B — Re-apply on change (themed popover):** when the Output folder changes *and* `.pending`
  jobs exist, show a dark popover anchored to the Output bar: *"Apply new output folder to N
  pending jobs? [Keep] [Apply]"*. Apply rewrites pending jobs' destinations (same filename stem,
  new folder, re-run collision resolution). Click-away = Keep (the safe no-op).

Outcome: the folder a queued job targets is never a surprise, and changing the folder mid-queue
is a one-click intentional action instead of a silent miss.

**Scope guard — "pending" = `.pending` only.** Never touch `.active`/`.preparing` (in flight) or
`.completed`/`.failed`/`.cancelled` (`status.isFinished`). Job status enum is
`ConversionJob.swift:12–47`; `isFinished` covers completed/failed/cancelled.

---

## Part B — Re-apply prompt + reassign

### 1. `ConversionViewModel.swift`
- Add `@Published var showApplyFolderPrompt = false`.
- Add `var pendingJobCount: Int { queue.jobs.filter { $0.status == .pending }.count }`.
- **`chooseOutputFolder()` (`:110–120`):** capture `let previous = outputFolderURL` *before*
  `outputFolderURL = url`. After assigning, if
  `QueueManager.directoriesDiffer(previous, url) && pendingJobCount > 0` → `showApplyFolderPrompt = true`.
  (Leave `setSourceFolder()`'s nil-default assignment at `:106` alone — it must not prompt.)
- Add `func applyOutputFolderToPendingJobs()`:
  ```swift
  guard let folder = outputFolderURL else { return }
  queue.reassignPendingDestinations(to: folder)
  showApplyFolderPrompt = false
  ```

### 2. `QueueManager.swift`
- **`static func directoriesDiffer(_ a: URL?, _ b: URL?) -> Bool`** — robust dir comparison
  (this app already learned URL directory equality is finicky → cookbook #52). Returns `false`
  if either is `nil`; else compares
  `url.resolvingSymlinksInPath().standardizedFileURL.path` **case-insensitively** (macOS default
  FS is case-insensitive, matching `RenamePatternEngine.uniqueStem`'s `caseInsensitiveCompare` at
  `RenamePatternEngine.swift:94–102`). Used by both B (change detection) and A (badge).
- **`func reassignPendingDestinations(to newFolder: URL)`:**
  - Seed a `taken: Set<String>` (lowercased full paths) from **non-pending** jobs'
    `destinationURL` + `actualOutputURLs` (those are fixed and must not be clobbered).
  - For each `.pending` job (mutate in place via `jobs.indices` / `updateJob`):
    `candidate = newFolder.appendingPathComponent(job.destinationURL.lastPathComponent)`
    (**same filename stem**, new dir). If `taken.contains(candidate.path.lowercased())` **or**
    `FileManager.default.fileExists(atPath:)`, append ` (n)` before the extension — mirror the
    existing style of `resolveFilenameConflict` (`QueueManager.swift:376–391`). Insert the
    resolved path into `taken`; set `job.destinationURL = resolved`.
  - **SRT auto-follows** — the sidecar path is derived from `destinationURL` at process time
    (`QueueManager+Processing.swift` `…deletingPathExtension().appendingPathExtension("SRT")`), so
    no separate handling.
  - **Verify `outputBookmarkData`:** check how it's populated at enqueue. With App Sandbox
    **disabled** (per CLAUDE.md) it's expected `nil`/unused in this flow — confirm; if a pending
    job carries one, refresh it for `newFolder` (or set `nil`) so it can't point at the old dir.
  - Call `saveQueue()` and `log("Re-pointed N pending job(s) to <folder>")`.

### 3. `QueuePanel.swift` — `OutputBar` (`:10–71`)
- Attach to the inner Output `HStack(spacing: 8)` (`:17–29`):
  ```swift
  .popover(isPresented: $vm.showApplyFolderPrompt, arrowEdge: .bottom) {
      ApplyFolderPopover().environmentObject(vm)
  }
  ```
- New `private struct ApplyFolderPopover` (mirror `RenamePopover`/`MoreOptionsPopover` styling —
  `.padding(16)`, fixed width ~300, `Theme.txt2`): title *"Apply new output folder to
  \(vm.pendingJobCount) pending job(s)?"*, short body naming the new folder
  (`vm.outputFolderURL?.lastPathComponent`), and a button row — **Keep** (`.cjGhost`/`.cjStandard`,
  sets `vm.showApplyFolderPrompt = false`) and **Apply** (`.cjPrimary`, calls
  `vm.applyOutputFolderToPendingJobs()`).

---

## Part A — Transparency (Hybrid)

### 4. `QueuePanel.swift` — `QueueRow` (`:177–311`)
- Add `@EnvironmentObject private var vm: ConversionViewModel` (vm is already in the environment;
  consumed by `OutputBar` etc.). This makes the row re-render when `outputFolderURL` changes, so
  badges clear/appear reactively.
- Add computed:
  ```swift
  private var folderMismatch: Bool {
      job.status == .pending &&   // only unstarted jobs can still be re-pointed
      QueueManager.directoriesDiffer(job.destinationURL.deletingLastPathComponent(), vm.outputFolderURL)
  }
  ```
- **Inline badge:** between the name (`:197–203`) and the progress bar, when `folderMismatch`,
  add `Image(systemName: "exclamationmark.triangle.fill")` in `Theme.acc1`, `.font(.system(size: 11))`,
  `.help("This job targets a different folder than the current Output setting")`. Minimal width.
- **Sub-line:** inside the outer `VStack(spacing: 0)` (after the main `HStack`, sibling to the
  `if expanded` block at `:244`), **always visible when `folderMismatch`** (not gated by the
  caret):
  ```swift
  if folderMismatch {
      Text("⚠ → \(job.destinationURL.deletingLastPathComponent().path)  (≠ current output)")
          .font(.system(size: 11)).foregroundStyle(Theme.acc1)
          .lineLimit(1).truncationMode(.middle)
          .padding(.leading, 26).padding(.bottom, 6)
  }
  ```

### 5. `QueuePanel.swift` — `TimecodeDisclosurePanel` (`:316–374`)
- Add `let destination: URL` param; pass `destination: job.destinationURL` from the call site
  (`:245`).
- Add an **"Output"** row (reusing the existing `label(_:)` 72-pt column, `:368–373`) showing
  `destination.deletingLastPathComponent().path` in `Theme.txt2`, monospaced 11,
  `.lineLimit(1).truncationMode(.middle)`. Place it last in the `VStack`, after the slow-mo note.
  Shown for every expanded row regardless of mismatch (always-on transparency half of Hybrid).

---

## Tests — `ConjoynTests` (add to an existing QueueManager test file; avoid a new file so no
xcodegen regen)

- `directoriesDiffer`: nil-safety (either nil → false); trailing-slash / `.`-segment / symlink
  normalization → same dir treated equal; case-insensitive equal; genuinely different → true.
- `reassignPendingDestinations`: (a) pending jobs move to new folder, **filename stem preserved**;
  (b) two pending jobs sharing a stem in the new folder get ` (1)` suffixing; (c) collision vs a
  **non-pending** job's destination in the new folder is suffixed (non-pending job untouched);
  (d) `.active`/`.completed`/`.failed` jobs are **never** modified; (e) `queue.json` reflects new
  paths after `saveQueue()`.

> If implementation adds any **new** `.swift` file, re-run `xcodegen` then build (cookbook #47).
> This plan is structured to need **no new files** (all additions land in existing files).

---

## Verification (end-to-end)

1. **Build + unit tests** (clean cycle per global rules): kill app → clean → build → run
   `ConjoynTests` via XcodeBuildMCP (`test_*`) or `xcodebuild test`. Expect current **229 + new
   reassign/compare tests** all green.
2. **Live A:** scan a card, queue 2 groups, then change the Output folder via *Choose…* → in the
   popover press **Keep**. Confirm the queued rows now show the ⚠ badge + `≠ current output`
   sub-line, and each row's caret panel shows the correct (old) **Output** folder.
3. **Live B:** repeat, but press **Apply** → badges/sub-lines clear, caret **Output** rows now
   show the new folder, console logs the re-point. Press **Start** → verify files actually land in
   the new folder (and the `.SRT` sidecar beside them).
4. **Scope safety:** start a join so one job is `.active`, then change the folder → confirm the
   prompt counts only `.pending` jobs and Apply leaves the active/finished jobs' destinations
   untouched.
5. **Collision:** point two pending jobs with the same stem at one folder that already contains a
   matching file → confirm ` (1)`/` (2)` suffixing, no overwrite.

---

## Files touched
- `01_Project/Conjoyn/ConversionViewModel.swift` — change-detect, prompt state, apply action.
- `01_Project/Conjoyn/Services/QueueManager.swift` — `directoriesDiffer`, `reassignPendingDestinations`.
- `01_Project/Conjoyn/Views/QueuePanel.swift` — `ApplyFolderPopover`, row badge + sub-line, disclosure Output row.
- `01_Project/ConjoynTests/…` — reassign + compare tests (existing file).

Branch: `feature/output-folder-clarity` off `main` (per solo-dev no-PR discipline).
