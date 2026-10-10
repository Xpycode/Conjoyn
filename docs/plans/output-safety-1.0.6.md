# Conjoyn — Review follow-up: output safety

Created 2026-09-05. **Complete for 1.0.6 / build 106 (5/5 tasks), 2026-10-10.** Archived execution plan. Paths in code spans are repository-relative.
Evidence: [app/code review](../reviews/2026-09-05/app-code-review.md), findings R1 and R5.
Checkbox tracking: `docs/TASKS.md`. Historical feature plans remain intact.

## Goal
Every queued recording owns a distinct output, existing files survive late collisions, and a
watch folder never changes destination because a picker was cancelled or a saved folder is unavailable.

## Scope and acceptance
- Two cards queued before Start with repeated output names produce distinct, correctly associated files.
- A destination created after enqueue is preserved byte-for-byte; the job chooses another safe name
  or fails clearly. Cover both direct writes and staged cross-volume publication.
- Video and `.SRT` outputs share a consistent stem and neither replaces an unrelated existing file.
- Cancelling the watch-output picker leaves bookmark, displayed path, and coordinator destination unchanged.
- An unavailable configured watch output pauses enqueueing with an actionable explanation; it does not
  become “next to source.” A deliberately unconfigured output retains its existing semantics.
- Existing queue persistence, camera grouping, source identity, telemetry, and verification tests pass.

## Outcome and boundaries
All five safety tasks passed implementation, review and required acceptance. User confirmed toolbar,
four-output batch and external-output unavailable/recovery. Independent video packet hashes and
SRT identity checks passed. No public release, push or merge. Assess remaining review findings and
release scope before packaging; preserve earlier unrelated working-tree changes.

## Wave 1 — Reproduce and close direct entry-point defects

- [x] **S1.1 — Reserve queued destinations through the existing resolver.**
  - Files: `Services/QueueManager+Operations.swift`, `Services/QueueManager.swift`,
    `ConjoynTests/QueueManagerTests.swift` (app paths under `01_Project/Conjoyn`).
  - First write a failing test through **addJob**, with two different source clips and the same
    initially absent destination. Existing resolver-only tests missed the caller's conditional bypass.
  - Fix the enqueue funnel shared by GUI/watch paths. Preserve bookmarks and captured source identities.
  - Done: unique destinations for pending jobs and existing on-disk files, including case-equivalent
    names on the supported filesystem; ordinary uncontested names remain predictable.
  - Backpressure: QueueManagerTests + QueuePersistenceCompatTests; demonstrate the new test fails
    against the previous caller before accepting the fix.

- [x] **S1.2 — Make watch-output picker Cancel a no-op.**
  - Files: `Views/WatchFoldersPanel.swift`, `Services/WatchFolderManager.swift`, existing manager tests.
  - Trace the current Choose callback → optional URL → setOutputFolder nil-clearing path. Guard the
    cancelled picker result; keep explicit model-level clearing separate.
  - Done: open an entry with a configured output, choose another folder, press Cancel; path/bookmark
    and live coordinator destination remain unchanged.
  - Backpressure: relevant WatchFolderManagerTests and the exact live UI interaction above.

## Wave 2 — Preserve files and unavailable destination intent

- [x] **S2.1 — Protect final output publication, including sidecars.**
  - Depends on S1.1. Files: `QueueManager+Processing.swift`, `FFmpegWrapper+Conversion.swift`,
    queue/FFmpeg integration tests.
  - Trace direct FFmpeg writes, detached staged copy, automatic retry, partial-file cleanup, and SRT
    naming. A pre-enqueue existence check alone cannot protect files created later.
  - Use a no-replacement publication operation or equivalently enforced ownership; choose the smallest
    implementation covering both write paths. Avoid another generic output-management subsystem.
  - Done: a late-arriving sentinel file survives byte-identically, failed cleanup cannot delete a file
    this job did not create, and actualOutputURLs/UI/verification/SRT agree on the final destination.
  - Backpressure: production-path integration with two distinct generated media payloads and a
    late-created sentinel; test staged/direct branches. Record a removable-volume test as unrun if
    unavailable, rather than treating same-volume coverage as equivalent.

- [x] **S2.2 — Fail safely when a configured watch destination cannot resolve.**
  - Depends on S1.2. Files: `Models/WatchFolderEntry.swift`, `Services/WatchFolderManager.swift`,
    `Services/WatchFolderCoordinator.swift`, `Views/WatchFoldersPanel.swift`.
  - Distinguish unconfigured / resolved / configured-unavailable state at resolution. Do not overload
    nil with both user intent and failure. Preserve decoding compatibility and saved destination data.
  - Proposed error location: existing watch-folder row, adjacent to its output well/status, following
    the existing rejected-folder error conventions; no new window or settings subsystem. Trace this
    wiring and follow master `36_ui-changes-protocol.md` before introducing a new UI element; use the
    AppKit conventions in `47_project-ui-conventions.md` for any new control.
  - Done: unavailable configured output enqueues nothing, preserves the saved path, explains recovery,
    and can resume after the destination is restored/reselected. Explicitly unconfigured still works.
  - Backpressure: WatchFolderManagerTests + WatchFolderCoordinatorTests with unavailable/resolved
    destination cases, plus picker/row UI verification. Do not claim unplug/replug coverage unless run.

## Wave 3 — Verify the user's workflow

- [x] **S3.1 — Close the four-job reproduction and hand off a fresh build.**
  - Depends on all preceding tasks. Repeat two-card enqueue before Start, using distinguishable
    disposable media. Assert four distinct outputs match their respective inputs; check SRT naming,
    late conflicts, cancellation of the folder picker, and unavailable watch output.
  - Independently review destination ownership, late-file races, and cleanup before closing R1/R5.
  - Run the full suite once after focused checks pass, then produce a fresh runnable build. Gracefully
    quit other Conjoyn instances, launch the exact fresh artifact, verify its executable path, and
    remove only disposable review jobs. Preserve source footage and unrelated user state.
  - Done: behavioral evidence recorded, tests/build pass, fresh app launched, R1/R5 dispositions and
    log/state updated. No automatic release; assess readiness separately after the remaining findings.

## Backpressure commands
Run from the repository root. Existing dependency cache: `01_Project/build/DD/SourcePackages`.

```sh
xcodebuild -project 01_Project/Conjoyn.xcodeproj -scheme Conjoyn -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath 01_Project/build/Review-Tests-DD -clonedSourcePackagesDirPath 01_Project/build/DD/SourcePackages -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO -only-testing:ConjoynTests/QueueManagerTests -only-testing:ConjoynTests/QueuePersistenceCompatTests test
```

For S1.2/S2.2 substitute the named watch test classes. For the final suite remove `-only-testing` and
use a **new** result-bundle path; `01_Project/build/review-2026-09-05.xcresult` already exists.
For the final user build, use `build` and `01_Project/build/Review-DD`, then launch its Debug app.
Xcode required sandbox escalation for its caches/services in the review; the initial sandboxed
attempt did not complete. Ad-hoc Debug signing is not release/notarization validation.

## Deferred
Ten review findings R2–R4 and R6–R12 are tracked separately in TASKS Backlog; do not fold them into
this safety session. Existing footage/product work remains there too. The only first-session
blocker found by review is R1; no footage is required to begin its regression test.

## Model fit
Deep capability + high reasoning for output ownership and asynchronous publication/cleanup. Use
independent fault-finding for the final safety review; model agreement does not replace tests.

## Execution log
Review baseline: fresh Debug build; 625 tests, zero failures (2026-09-05).
- **2026-09-05 — S1.1 complete:** four addJob regressions failed before the fix; focused queue and
  persistence suite then passed **80 tests / 0 failures**. Independent review found no S1.1 defects.
  Enqueue now reserves names on every call, compares queued paths case-insensitively, and preserves
  job identity/bookmarks. Evidence: `docs/reviews/2026-09-05/s11-output-reservations.md`.
  S1.2, S2.1, S2.2 and S3.1 remain open; no new full-suite/live batch or user build handoff yet.

- **2026-09-17 — S1.2 implemented, awaiting acceptance:** guarded nil picker result in WatchFoldersPanel; explicit model clearing unchanged. Serial implementation; independent review by review_cancel clear. Seven manager tests passed; fresh Debug build launched and executable verified. Live check interrupted at Add Folder picker before creating the disposable entry. User paused for log/clear; no commit or push. Keep S1.2 unchecked. Resume details: `docs/sessions/2026-09-17.md`.

- **2026-10-10 — S1.2 accepted:** live Debug app: configured temporary output, navigated picker
  to `other`, Cancel preserved visible output and exact persisted entry/bookmark. A generated blue
  one-second recording subsequently joined into the original output, proving coordinator destination.
  Removed disposable watch entry afterward. Seven manager tests passed in 114-test focused run.
- **2026-10-10 — S2.1 in progress:** fresh task agent `publication_safety`; independent reviewer
  `review_publication`. Red: two tests exposed video/SRT replacement. Initial implementation:
  114 focused tests passed; review found manual Retry after partial publication needs recovery.
  S2.2 delegated to fresh task agent `watch_destination` after S1.2 acceptance.

- **2026-10-10 — user scope addition:** fix SDK 27 toolbar capsules for 1.0.6 after user
  screenshot. Penumbra precedent `f6fe082` (2026-09-22): hide shared group backgrounds;
  keep existing button styles and guard API availability for macOS 14 deployment.
  Verify in the final live build alongside S3.1; no broad toolbar redesign.

- **2026-10-10 — S2.1 complete:** independent re-review clear after retry recovery fix. Full suite
  643/0 and focused coverage include direct/staged conflicts, source fidelity, symlinks and case
  equivalence, partial publication persistence and manual recovery. Scoped commit `0e5e51f`.
- **2026-10-10 — S2.2 implemented:** fresh `watch_destination` agent; independent review caught
  missing directory search permission, corrected and covered by 19 passing watch tests. Live
  recovery remains required; task unchecked.
- **2026-10-10 — foreground handoff:** user explicitly requested control of the app for testing.
  Stop UI automation and app-hosted test launches during that window. Fresh 1.0.6 (106) running;
  toolbar fix built/visually verified and committed `9f74284`. S3.1 exact four-recording regression
  added but not run yet because user owns the app. Live instructions supplied in conversation.
  Evidence: `docs/reviews/2026-10-10/output-safety.md`.

- **2026-10-10 — plan complete:** user reports toolbar, four-output batch and watch recovery all
  passed, with screenshots of four video/SRT pairs and unavailable → settling transition retaining
  `/Volumes/4.x - MORE/FCP-temp`. Independent hashes match all four source video packet streams;
  sidecar identities/stems match. S2.2 committed `a3816f7`; final batch regression committed
  `74b16e1`, passed after correcting the test's assumption about completed jobs being restored
  (the app intentionally restores only unfinished/failed jobs; persisted JSON checked instead).
  Production code unchanged by that test correction. Full 643/0 + final permission 19/0 + batch 1/0.
  User-controlled app and watch configuration retained; no automated cleanup of their test state.
