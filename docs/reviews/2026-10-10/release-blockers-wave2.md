# Release-blocker Wave 2 — 2026-10-10

Selected scope complete: Q2/W2/M1. Active repair plan continues; no release readiness claimed.

## Changes and ownership

- Fresh-context `q2`: persistent queue-footer recovery notice and local AppKit Show in Finder button.
  Notice distinguishes protected original, retained backup, and subsequent save failures; empty
  queue still displays it. Local commit `23e99df`.
- Fresh-context `w2`: versioned sibling ledger, original v1 bytes preserved, explicit strong/weak
  descriptor decisions, durable-only in-memory updates, observable read/write failures. Local
  commit `a13d563`. Existing production legacy API writes an overlay into v2 storage; v2 recording
  admission/review is not integrated until W3.
- Fresh-context `m1`: workspace events plus one 5-second fallback timer, bookmark re-resolution,
  immediate root-loss teardown, changed-path recovery, healthy-root preservation, disabled/removed
  exclusion, observer/timer cleanup. Local commit `a00d957`.
- Coordinator: test/build ownership, final explanatory-text correction, scoped commits, source
  provenance, launch and documentation. All pre-existing dirty source hashes match the baseline.
- Independent `wave2_review`: found failed ledger writes could repeat production enqueueing because
  caller ignored insert failure. W2 owner added narrow coordinator guards before/after suspension
  and per batch, stops on first failed insert, existing-row history-unavailable explanation. Two
  regression tests cover corrupt history and failed-write batch/poll suppression. Final review clear.

## Policy

User clarified **Hold for review** for actual upgrades. Initial Reprocess once answer concerned
what they thought was testing and was superseded. Explicit per-v2 Already processed / Process once
APIs exist, with weakness still observable; no automatic migration policy enabled. D3 queue-footer
placement accepted through execution request. W3/D4 review UI remains a later acceptance gate.

## Automated validation

- First sandbox attempt failed before compilation due to Xcode/Swift package-cache access.
- Escalated focused command T: **81 tests, 0 failures**. Classes: ProcessedGroupLedgerTests 20,
  QueuePersistenceCompatTests 18, QueueRecoveryTests 8, WatchFolderCoordinatorTests 11,
  WatchFolderManagerTests 15, WatchRecordingIdentityTests 9.
- Result/log: `01_Project/build/ReleaseBlockers-Wave2-Focused2.xcresult` and matching `.log`.
  Six `-only-testing:ConjoynTests/<Class>` filters; all other flags match plan T.
- Standalone command B passed. Final text-only correction removed off/on retry advice because
  W3 still owns duplicate-safe pending-admission recovery. Rebuild passed:
  `ReleaseBlockers-Wave2-App-Final.log`. Tests preceded this text-only correction; no logic changed.
- Existing generated scheme retained isolated HOME/CFFIXED_USER_HOME and empty watch arguments.
  No project regeneration required. Test fixtures use temporary state. No user queue corruption,
  foreground UI automation, full-suite rerun, or physical-device check performed.
- `git diff --check` and original dirty-source SHA256 comparisons pass.

## Artifact and limits

Fresh Debug 1.0.6 (106):
`01_Project/build/ReleaseBlockers-App-DD/Build/Products/Debug/Conjoyn.app`.
Old PID 68008 terminated gracefully, then fresh PID 79905 launched and exact executable verified.
Launch evidence: `ReleaseBlockers-Wave2-Launch.log`. Left running under standing user instruction.
Source commit/dirty patch and executable hashes: `release-blockers-wave2-source.json`; exact local
patch: `ReleaseBlockers-Wave2-Source.patch`. No push/merge; pre-existing dirty work remains.

The narrow storage guard pauses subsequent admissions; the first failed-history-write job still
follows the old enqueue-before-ledger order. W3 must implement durable pending-admission recovery
and live-job dedup across restart/toggle/removal. W4 still owns definitive stale-discovery fences.
No claim of duplicate-safe recovery before those tasks. Root identity relies on Foundation bookmark
resolution; fake changed-path tests do not establish physical same-name-volume behavior.
Live empty-queue notice/reveal and physical mount tests remain E1. Active coordinator deallocation
cleanup was pre-existing and is not covered by the new recovery-observer cleanup tests. A suspended
discovery completing after another pass fails history is code-guarded, not a separate new test.
V1/V2 final integrated review/full suite and E1/E2/E3 live/source-freeze/signed-artifact gates remain.
