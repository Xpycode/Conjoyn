# Release-blocker Wave 1 — 2026-10-10

Selected scope complete: S1/Q1/W1. The active plan and later release gates remain open.
Target: local Debug Conjoyn 1.0.6 (106), Xcode 27.2 (27B5019j), arm64/macOS 14 deployment.

## Changes and ownership

- `scan_s1`: synchronous source/rescan invalidation, retained request task, generation-authoritative
  discovery and date-cache publication, immediate enqueue gate. Existing search/sort/Apply preserved.
- `queue_q1`: typed recovery state separate from save errors, unique non-overwriting sibling copy
  before replacing an unreadable queue, lifetime save block when preservation fails, Release log.
- `identity_w1`: pure v2 descriptor, length-prefixed canonical bytes, normalized rational duration,
  numeric microsecond capture time, strength/reasons and optional persisted watch snapshot with
  watch-entry/ledger ownership. Production ledger is unchanged.
- Coordinator: generated project membership, isolated test environment, serialized Xcode runs,
  one test-only optional unwrap correction, negative-check restoration, standalone build and launch,
  scoped local checkpoints and documentation.
- `wave1_review`: fresh-context read-only fault review of all changed production files and tests;
  no concrete blocker. Suggested fixed digest vector was present in final W1 and re-reviewed.

## Automated evidence

| Run | Outcome | Evidence under `01_Project/build/` |
|---|---|---|
| Initial sandbox attempt | Package-cache permissions prevented compilation | `ReleaseBlockers-Wave1-First.log` |
| First escalated build | Test compile failed: failable ExactDuration expectation required unwrap; corrected | `ReleaseBlockers-Wave1-Focused.log`, matching `.xcresult` |
| Focused integration | **118 tests, 0 failures** | `ReleaseBlockers-Wave1-Focused2.log`, matching `.xcresult` |
| Negative fault mutations | **21 tests, 29 assertion failures**, expected; all three protections detected | `ReleaseBlockers-Wave1-Negative.log`, matching `.xcresult` |
| Restored implementation | **21 tests, 0 failures** | `ReleaseBlockers-Wave1-Restored.log`, matching `.xcresult` |
| Standalone Debug build | **BUILD SUCCEEDED** | `ReleaseBlockers-Wave1-App.log` |

Focused classes: ConversionScanTests 4, QueueRecoveryTests 8, WatchRecordingIdentityTests 9,
RecordingSearchTests 7, QueueManagerTests 72, QueuePersistenceCompatTests 18. Each scan test
exercises several completion permutations using continuations rather than sleeps.

The negative run temporarily removed scan-generation checks, bypassed the failed-preservation save
gate, and omitted capture date from canonical identity. These are mutation checks, not a claim that
the new test interfaces ran against untouched historical source. All three production files were
restored byte-for-byte against saved SHA256 values before the green rerun/build. Originals remain
in `ReleaseBlockers-Wave1-MutationBackup/`; no mutation was committed or launched for user testing.

Tests used the plan's `T` command, with the six class filters above, serial Xcode invocations and
unique result bundles. Negative/restored runs selected only the three new classes. Ad-hoc signing:
`CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`; package resolution disabled; shared package cache
`01_Project/build/DD/SourcePackages`. Test derived data: `ReleaseBlockers-Tests-DD`.

The generated (gitignored) TestAction sets `HOME` and `CFFIXED_USER_HOME` to
`01_Project/build/ReleaseBlockers-TestHome`, with `-watchFolder.entries '()'` and
`-ApplePersistenceIgnoreState YES`. A Foundation probe confirmed the custom home/app-support path;
test diagnostic/speed files were observed there. Queue fixtures use disposable temporary directories.
Regenerating the Xcode project removes these local test-scheme settings; reinstate them before
another hosted test run. No test deliberately corrupts the user's real queue or changes their watches.

The app build used the plan's `B` command and `ReleaseBlockers-App-DD`, separate from the test host.
No full-suite rerun or manual/device acceptance was performed for this wave. The earlier 643/0
safety suite is historical evidence, not a new Wave 1 result.

## Artifact and source provenance

- Source at `2590972` plus the working-tree source changes listed in
  `release-blockers-wave1-source.json`. That manifest records SHA256 values, source-patch checksum,
  app version/build and executable checksum. Exact local patch: `ReleaseBlockers-Wave1-Source.patch`.
- Q1 local commit `3e434ee`; W1 local commit `2590972`. No push or merge.
- S1 stays uncommitted: its VM delta overlaps earlier search/Apply work and its new tests use the
  uncommitted search API. Committing all of that would silently resolve E2's pending inclusion
  decision. The pre-execution dirty-file snapshot and S1-only delta are retained in
  `ReleaseBlockers-Wave1-Baseline/`; unrelated pre-existing source changes were preserved.
- Fresh app: `01_Project/build/ReleaseBlockers-App-DD/Build/Products/Debug/Conjoyn.app`.
  Prior PID 11752 (`Review-DD` artifact) exited gracefully. Fresh PID 68008 was verified at the
  new bundle's `Contents/MacOS/Conjoyn` executable. Left running under the standing fresh-build
  handoff instruction. No foreground UI automation or changes to test watch entries/queue.

## Remaining boundaries

Q2 recovery UI/reveal requires D3 placement acceptance; Q1 currently provides state and logging.
W2 migration requires D1 policy; W3 review UI still requires D4. M1 is independently ready in Wave 2.
W1's “strong” means complete metadata evidence, not proof of unique video bytes or readiness;
generation-bound re-probing, settled admission and durable ledger integration belong to W3/W4.
V1/V2 final review/full suite and E1/E2/E3 live/source-freeze/signed-artifact acceptance remain open.
