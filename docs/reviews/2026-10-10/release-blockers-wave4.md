# Release-blocker Wave 4 — 2026-10-10

Selected scope complete: W4. Active repair plan continues; no release readiness claimed.
Local scoped source commit: `6f154ec`.

## Scope and ownership

User explicitly requested Wave 4. Fresh-context `wave4` owned the coupled coordinator, manager,
existing status UI and their two test files. Coordinator owned Xcode, Git, integration and docs;
`wave4_review` independently reviewed read-only. No concurrent source editing or Xcode jobs.

- Events arriving during discovery retain one coalesced trailing request. Request, event and
  lifecycle generations fence results, deferred cleanup and queued monitor/timer callbacks.
- Timeout returns without awaiting an uncooperative reader; polling schedules a bounded retry
  without another event. A manager-owned budget permits **at most two underlying discovery workers**
  per associated root (one current plus allowance for retired work). When both remain occupied,
  new scans wait. Only actual reader completion releases a slot, never timeout/cancellation.
- Entry identity, canonical root aliases and retained bookmark associations carry budget through
  settings changes, toggle, removal/re-addition, root loss and changed-path remount. This budget is
  session-local; **relaunch Conjoyn** recovers when abandoned workers never return.
- Metadata re-probes share the same budget. Cheap sampling releases its latch before an awaited
  re-probe, allowing unchanged groups to progress. Old lifecycle caches/review records are cleared.
- Existing watch status shows Discovery stalled and describes relaunch recovery. Successful empty
  discovery clears stalled status. No reset control or new user setting bypasses the worker cap.

## Review and corrections

Independent review found and verified fixes for stalled status persisting after empty successful
retry and an event consuming a queued refresh before its task starts, causing an unnecessary third
scan. Coordinator found the cheap-sampling latch held across a re-probe await; fixed and covered by
healthy-group progress while the changed group's probe is suspended. Final W4 source review clear.
Optional additional scheduler-interleave and same-instance deferred-cleanup tests were noted;
current source checks and integrated lifecycle tests revealed no remaining concrete W4 blocker.

A separate **pre-existing W3 membership issue** remains explicitly tracked in TASKS and V1: when a
short final segment arrives before its predecessor, the predecessor's event does not invalidate
unchanged cached membership or its quiet timer. A stalled refresh can admit the partial group.
Normal full-segment continuation is size-gated; this finding concerns out-of-order copying.
Source inspection confirms the path; no runtime reproduction was performed. A targeted fix needs
membership evidence and must preserve unrelated-group progress. W4 clearance does not close AC4.

## Automated validation

- First focused build compiled; 31 tests / 1 failure: old sleep-based timeout test expected immediate
  retry. Replaced with controlled timeout/clock proof of poll-triggered retry and actual admission.
- Second expanded run was interrupted after the new real-manager fixture stalled: `/var` versus
  `/private/var` bookmark resolution made its fake availability check reject the returning root.
  Corrected fixture canonicalization and guarded setup. No production change hid this failure.
- Final expanded run: **132 tests / 0 failures**, nine classes: ProcessedGroupLedgerTests 20,
  QueuePersistenceCompatTests 18, QueueRecoveryTests 8, WatchAdmissionTests 10,
  WatchFolderCoordinatorTests 14, WatchFolderManagerTests 18, WatchFolderReconcilerTests 21,
  WatchMetadataTests 14, WatchRecordingIdentityTests 9.
- Seven new controlled regressions replace one old timing-sleep test. Coverage includes burst
  coalescing, timeout without a new event, bounded workers, late old results, disable/replacement,
  healthy sampling while re-probe hangs, budget aliases and actual manager suspended-reader
  transitions through unmount/remount at a changed path, settings/toggle/remove/re-add.
- Negative mutation removed only the event-generation result guard. The burst regression failed
  with two assertions. Source restored **byte-for-byte**; coordinator/manager **32 tests / 0 failures**
  passed again. This is mutation evidence, not a claim of pre-implementation red tests.
- Logs/result bundles: `01_Project/build/ReleaseBlockers-Wave4-{First,Second,Third,Negative,Restored}`
  with `.log` / `.xcresult` suffixes. Commands follow active-plan T with the classes above; Negative
  selects `WatchFolderCoordinatorTests/testEventBurstDuringDiscoveryRunsOneTrailingPassAndRejectsOldResult`.
- Standalone plan B passed: `ReleaseBlockers-Wave4-App.log`. Generated test scheme isolation was
  retained; no project regeneration needed. `git diff --check` passed; all eight pre-existing dirty
  source/test SHA256 values match the saved pre-wave baseline.

## Artifact and boundaries

Fresh Debug **1.0.6 (106)**:
`01_Project/build/ReleaseBlockers-App-DD/Build/Products/Debug/Conjoyn.app`.
Old PID 95006 quit gracefully; fresh PID 5328's exact executable path verified. Launch log:
`ReleaseBlockers-Wave4-Launch.log`. Left running under the standing instruction. Source/dirty patch
and artifact hashes are in `release-blockers-wave4-source.json` and the referenced build patch.

No full suite, foreground UI automation, physical-device test, signed-artifact validation,
packaging, push, merge or deployment. Prior dirty source is preserved and excluded from the W4
commit; E2 controls release inclusion. V1/V2 and E1–E3 remain open, including the membership finding.
