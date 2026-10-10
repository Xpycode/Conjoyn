# Release-blocker Wave 3 — 2026-10-10

Selected scope complete: W3. Active repair plan continues; no release readiness claimed.

## Scope and ownership

User's “next” following the proposed Review placement authorized W3 and accepted D4. Fresh-context
`wave3` implemented the coupled queue/watch/reader/UI patch serially. Coordinator owned generated
project membership, build/test processes, local Git checkpoint, launch and documentation. Independent
`wave3_review` performed read-only fault review. Local scoped source commit: `4760ace`.

- Generation-bound metadata uses size/mtime and session-local device/inode observations around each
  probe. Grouping and recording identity use captured video sizes. Invalid reads remain candidates
  for settled re-probe; unchanged groups can proceed during a stalled refresh.
- V2 snapshots and conservative old-job matching prevent live duplicates, including a new entry ID.
  Weak/legacy ambiguity requires explicit Already processed or Process once, bound to the exact
  descriptor and rechecked through normal readiness, destination and file-generation checks.
- Queue save precedes history admission; persisted pending markers gate every processing entry point.
  Failed final marker save restores the gate. Manager recovery uses the saved namespace independently
  of a live watch. Disable/remove holds persist until explicit Start after repair.
- Cancelling an uncommitted admission retains a cancelled record across relaunch without sealing
  history. Retry is explicit. Remove/Clear invalidate the existing job's recovery; no permanent
  deleted-recording tombstones were introduced. Failed cancellation/removal saves stay visible.
- AppKit Review controls live below each watch output path; sheet presents recording/date/count and
  both decisions. Pending storage recovery/explicit-start holds appear on queued jobs.

## Review and corrections

Independent review identified and verified fixes for:
1. Cancelled pending admissions recreated by rediscovery/relaunch.
2. A sole clip changed during probing disappearing from future retry work.
3. Failed review history writes becoming unrecoverable without a pending queue job.
4. Production event refresh discarding all stamps and blocking unaffected groups.

Self-review also fixed same-descriptor approval invalidation during direct rediscovery and grouping
using live sizes. Regression cases enter production sourceDidChange and actual folder-reader paths,
with injected probes/storage and disposable filesystem/defaults. Final independent review clear.

## Automated validation

- First focused run compiled: 103 tests, five assertions failed in two cases. One fixture used a
  defaults key overridden by isolated test launch arguments; corrected to a dedicated key. Recovery
  observer lifetime now follows enabled watches or pending admissions. No failures were ignored.
- Second run: 112 tests / 0 failures, before review corrections.
- Final expanded run: **227 tests / 0 failures**, 11 classes: DJIFolderGroupingTests (29),
  ProcessedGroupLedgerTests (20), QueueManagerTests (72), QueuePersistenceCompatTests (18),
  QueueRecoveryTests (8), WatchAdmissionTests (10), WatchFolderCoordinatorTests (11),
  WatchFolderManagerTests (15), WatchFolderReconcilerTests (21), WatchMetadataTests (14),
  WatchRecordingIdentityTests (9).
- Controlled negative check removed only the final-save pending-marker rollback. The exact regression
  failed (one assertion); source then restored byte-for-byte in a finally block. All **24 new tests**
  passed on restored source. This is mutation evidence, not a pre-implementation red run claim.
- Logs/result bundles: `01_Project/build/ReleaseBlockers-Wave3-{First,Second,Third,Negative,Restored}`
  with `.log` / `.xcresult` suffixes. Commands match active-plan T with the listed class filters;
  Negative selects `WatchAdmissionTests/testFinalQueueWriteFailureKeepsGateAndAlreadyCommittedLedgerRecoversIdempotently`.
- Standalone plan B passed; final explicit MainActor annotation on the new AppKit coordinator was
  followed by another successful B (`ReleaseBlockers-Wave3-App-Final.log`). No behavior changes after
  the test run. Generated ignored project regenerated for new test membership; TestAction isolation
  preserved. No concurrent build/test jobs. No full-suite rerun (V2 remains later).
- `git diff --check` passed. All pre-existing dirty source SHA256 values equal the saved baseline.

## Artifact and limits

Fresh Debug **1.0.6 (106)**:
`01_Project/build/ReleaseBlockers-App-DD/Build/Products/Debug/Conjoyn.app`.
Old PID 79905 exited gracefully; fresh PID 95006 exact executable verified. Launch evidence:
`ReleaseBlockers-Wave3-Launch.log`. Left running per standing user instruction. Source/dirty patch and
binary hashes: `release-blockers-wave3-source.json`; source patch in the build directory.

No foreground UI automation, physical-device check, live review/upgrade acceptance, signed artifact
validation, packaging, push, merge or deployment. Existing source/UI dirty work remains outside this
commit; E2 still controls release inclusion. Identity is a descriptor, not a video content hash:
identical descriptors cannot distinguish different bytes. W4 trailing refresh, timeout and shared
worker-budget accounting remain incomplete; W3's lifecycle checks do not establish W4 completion.
V1/V2 final integrated review/full suite and E1–E3 live/source-freeze/signed-artifact gates remain.
