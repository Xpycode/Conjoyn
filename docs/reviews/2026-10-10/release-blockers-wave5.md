# Release-blocker Wave 5 — 2026-10-10

Selected scope complete: V1/V2. Active plan continues through E1–E3; no release readiness claimed.
Scoped local correction commit: `ff18f37edfa59a6a343cb3288c4534ab203d06ea`.

## Ownership and corrections

Fresh-context `v1_review` independently reviewed the integrated repair paths; `v1_membership`
owned corrections serially. Coordinator owned Xcode, integration, Git, launch and documentation.
No shared-source parallel editing. Review details: `release-blockers-wave5-review.md`.

An out-of-order short final segment could be admitted while its newly copied predecessor's discovery
stalled. Filename membership now participates in freshness independently of successful probes:
missing/rejected predecessors cannot disappear from the completeness check. Changed membership
invalidates the affected quiet window/review and requires coherent regrouping. Buckets use camera
family, DJI variant and GoPro recording number; independent buckets continue. A DJI variant bucket
waits conservatively because filenames alone cannot distinguish its recordings before metadata.

Directory census and alias resolution run off MainActor under the same two-worker budget as discovery.
Timeout retains the actual worker slot; coalesced census results carry launch-event and request
ownership, and lifecycle invalidation rejects late results. Events retain pending refresh before new
awaits; polling resumes work after capacity returns. Review actions await fresh membership before
persisting a decision. `/var` and `/private/var` selected/discovered aliases compare consistently.
If both underlying workers never return, Discovery stalled persists; relaunch is recovery.

Eight new coordinator regressions cover event/no-event predecessor arrival, failed-probe omission,
independent bucket progress, quiet-window reset, review decisions against changed/unavailable
membership, stalled census worker limits/lifecycle, old census joined by a new event, and failed
post-discovery census recovery. The alias regression exercises both root spellings. Review tests
reopen durable ledger storage rather than inspecting the original value-type copy.

## Validation and provenance

- Pre-fix red regression: **1 test, 4 assertion failures**, reproducing premature tail admission.
  `ReleaseBlockers-Wave5-Red2.{log,xcresult}`. Initial `Red` attempt failed at sandboxed Xcode cache
  access before tests; escalation allowed the actual run.
- Iteration evidence is retained: Focused was interrupted after alias-related assertions/stall;
  Focused2 passed coordinator tests but stalled in manager retry recovery; Focused3 completed
  **63 tests / 3 assertions failing** in actual-reader alias handling; isolated Reader then passed;
  Focused4 exposed reverse alias handling and was interrupted. These are not acceptance passes.
- Final focused: **64 tests / 0 failures** (WatchAdmission 10, WatchFolderCoordinator 22,
  WatchFolderManager 18, WatchMetadata 14), `ReleaseBlockers-Wave5-Focused5.{log,xcresult}`.
- Independent final source review found no unresolved concrete blocker; final exact revision green.
- Full suite once after final fixes: **721 tests / 0 failures**, **TEST SUCCEEDED**,
  `ReleaseBlockers-Wave5-Full.{log,xcresult}`.
- Standalone Debug build **BUILD SUCCEEDED**: `ReleaseBlockers-Wave5-App.log`.
- All paths above are under `01_Project/build/`. Commands are active-plan T (four listed class
  filters for Focused5; no filters for Full; unique matching resultBundlePath), then B. Logs retain
  exact Xcode invocation. Shared test scheme HOME/CFFIXED_USER_HOME and empty-watch arguments retained.
- `git diff --check` passed. Eight pre-existing dirty source/test SHA256 values match the baseline.
  Only four correction files were committed. Tested source includes prior uncommitted S1/search/UI/
  Apply changes: HEAD alone is insufficient provenance. Full source hashes and dirty patch hash:
  `release-blockers-wave5-source.json`; patch: `01_Project/build/ReleaseBlockers-Wave5-Source.patch`.

## Runnable artifact and remaining gates

Fresh Debug **1.0.6 (106)** built 2026-10-10 (executable mtime 18:04:00 UTC):
`01_Project/build/ReleaseBlockers-App-DD/Build/Products/Debug/Conjoyn.app`.
Graceful quit of old PID 5328 completed before launch; fresh PID 21473 executable path verified.
Launch log: `ReleaseBlockers-Wave5-Launch.log`. The standalone app is intentionally left running
under the standing user instruction; no intermediate test-host product was launched for handoff.

E1 live/UI/removable-device acceptance remains required; no foreground automation or physical mount
check was performed. E2 must resolve prior dirty-source inclusion before release source freeze.
E3 requires the actual signed/notarized artifact and clean-install/update acceptance. No packaging,
merge, push or deployment occurred. Metadata descriptors still cannot distinguish identical-metadata
replacement bytes; automated checks do not prove device behavior or signed-artifact acceptance.
