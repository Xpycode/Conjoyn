# E2 release-source review — 2026-10-10

**Disposition:** user approved all eight paths unchanged; E2 complete at local source commit
`c6a1b23`. See [source freeze](release-source-freeze.md) and its manifest. The proposal/review
history below is preserved; E3 exact signed-artifact acceptance remains required.

Review complete; recommended inclusion is all eight dirty source/test paths unchanged. Release
scope is proposed, not yet finalized. E1 live/device and E3 signed-artifact gates remain open.
No application edits, commit, merge, push, packaging or publication in this review.

## Exact inclusion proposal

Base: `ff18f37edfa59a6a343cb3288c4534ab203d06ea` on `fix/queued-output-reservations`.
Include these whole files at the SHA256 values in `release-source-candidate.json`:

| Path under `01_Project/` | Scope |
|---|---|
| `Conjoyn/ConversionViewModel.swift` | S1 request ownership, search, and September Apply fix; explicitly all three |
| `Conjoyn/ContentView.swift` | Synchronous scan request entry |
| `ConjoynTests/ConversionScanTests.swift` | Four request/cache/enqueue ownership regressions; currently untracked |
| `Conjoyn/ConjoynApp.swift` | Find command and Edit-menu preservation |
| `Conjoyn/Views/DesignControls.swift` | AppKit-backed search field, focus and Escape |
| `Conjoyn/Views/RecordingsList.swift` | Search header, result count and no-match presentation |
| `ConjoynTests/RecordingSearchTests.swift` | Seven search matching/state tests; currently untracked |
| `ConjoynTests/QueueManagerTests.swift` | Three restored/reselected-output Apply regressions |

No reviewed source is recommended for deferral on correctness grounds. The source includes the
already committed queue/watch/publication repairs. Other dirty documentation, historical reviews,
screenshots and session logs are preserved; they are not silently bundled into a source commit.
No blanket stash/reset or source rewrite is needed. Selecting a different scope changes the tested
source and requires renewed review and relevant validation before packaging.

## Review and verification

Coordinator reviewed the diffs and provenance; fresh-context `e2_review` independently reviewed
all eight paths read-only. Neither review found a concrete correctness blocker.

- All **170/170** Wave 5 source hashes match, including the two untracked tests.
- HEAD still matches the Wave 5 base; the original Wave 5 source patch is retained and hash-matches.
- Candidate patch includes all six modified tracked files **and both untracked tests**. Applied
  to copies of the base files in a temporary directory, all eight reconstructed files match the
  tested SHA256 values. `release-source-candidate.patch` plus the base identifies the source.
- Reused Wave 5 full-suite evidence: **721/0**, including ConversionScan **4/0**, RecordingSearch
  **7/0**, QueueManager **72/0**. No tests rerun merely for unchanged source in this review.
- `git diff --check` passed before evidence updates.
- Exact running standalone Debug executable PID 21473 matched the Wave 5 SHA256 and version
  **1.0.6 (106)** at preflight. Initial E1 checks used that original app; later watch checks used a copied,
  re-signed bundle with identical compiled code and a separate preference identity. See the
  E1 report for artifact limitations and restoration of the original app.

S1 invalidates ownership before scheduling, guards both discovery and date warming, and gates
actual enqueue. Search narrows display without changing selection; hidden selections still count
and enqueue. This is the established behavior, with broader selection redesign deferred as R3.
Apply compares pending job destinations, preserves them until explicit Apply, and rejects a delayed
prompt for a different newly selected output.

## Coverage limits and disposition

- Search tests primarily exercise string helpers and empty-model state. Populated filter/sort
  interaction, hidden-selection enqueue, Find surviving menu opening, focus, Escape, clear and
  layout need live evidence; E1 records actual coverage separately.
- Apply tests call the model directly. Picker Cancel/Keep, popover presentation and ViewBridge
  timing need live checks. If the queue becomes empty during the 400 ms delay, a stale prompt can
  still appear; Apply targets only current pending jobs. Minor presentation follow-up under R12,
  not a data-loss finding or a reason to discard the restored-queue fix.
- No claim of a physical mount, clean install, upgrade, or signed Release check follows from the
  suite or Debug artifact. E3 must exercise the exact newly built signed artifact after E1/E2.

## Build inputs and release notes

The manifest records current generated project/scheme, package lockfile and helper hashes in addition
to source hashes. These are present-time inputs, not proof that every ignored input matched a prior
build. The Xcode project, Package.resolved and helpers are gitignored. Regeneration can discard the
TestAction's isolated HOME/CFFIXED_USER_HOME and empty-watch arguments; restore/verify isolation
before any later test run. Preserve the recorded package revisions and helper inputs, then verify
actual E3 build inputs again. Do not silently accept dependency resolution drift.

Draft release notes, pending scope disposition and acceptance:

> Conjoyn 1.0.6 improves source-scan ownership, watch-folder discovery and reconnection, and queue
> recovery. Watch history uses recording-aware identities and holds ambiguous older history for
> review. Output collision safeguards keep queued videos and telemetry sidecars paired without
> replacing existing files. Recordings search includes Edit → Find. Choosing a destination after
> restoring a queue offers Apply for pending jobs that still target another folder.
>
> Search filters the visible list and preserves selection. If watch discovery remains stalled
> because both workers do not return, relaunch Conjoyn. Recording identity uses metadata and file
> descriptors; it does not distinguish every possible replacement with identical descriptors.

These notes are a draft, not a published claim that release acceptance has passed. Stage the final
`Conjoyn-1.0.6.html` before appcast generation only under E3 release authorization. Public release
remains 1.0.5. E2 can close after the inclusion disposition is recorded with final commit/patch
provenance; E3 remains dependent on both E1 and E2.
