# Conjoyn 1.0.6 — release-blocker implementation plan

Created 2026-10-10. **Waves 1–5 complete; E1 accepted with active-read device-loss deferral to 1.1; E2 source frozen at c6a1b23. E3 closed by explicit GUI acceptance waiver; 1.0.6 published.**
Active plan; historical v1 remains in `../../IMPLEMENTATION_PLAN.md`, completed output safety in
`output-safety-1.0.6.md`. This plan contains the requirements; no separate feature spec is needed.

## Goal and release boundary

Make source selection, watch discovery/identity and queue recovery safe enough to release 1.0.6
without regressing the completed output-publication protections.

**Done for this repair batch:** latest-request-only scan results, reliable watch refresh/recovery,
recording-aware dedup with explicit upgrade ambiguity handling, preserved unreadable queue data,
regression suite green, independent review clear, and live acceptance recorded.
**Done for shipping:** additionally freeze the exact release source, build/sign/notarize after the
last source fix, and smoke-test that exact artifact including update and clean-install paths.

Scope: R4 scan ownership; R6 discovery/lifecycle/source recovery; R7 recording identity and the
migration necessary to deploy it; queue-persistence subset of R10. No broad scan-progress UI,
selection redesign, Stop lifecycle repair, output-option implementation, or architecture cleanup.
R2/R3/R8/R9/R11/R12 and the remaining R4/R10 usability work stay deferred, not silently declared fixed.
The original planning turn authorized no implementation or Git changes. The subsequent execution
requests cover Waves 1–5, including their validation and local execution checkpoints.
Merge, push, deployment and destructive operations remain outside this execution request.

### Evidence and severity

- Current code confirms all four failure paths. R10 is conditional loss of recoverable **queue
  state**, not footage destruction or proof existing compatibility fixtures fail.
- R6 also permits a discovery completion after disable/removal, and skips unavailable roots at
  startup. Both belong to the same watch lifecycle repair.
- R7's current persisted hashes contain only stem/index/variant. Those hashes cannot be reversed
  into historical capture identity. A v2 hash function alone cannot safely migrate old records.
- The ledger is currently sealed at **enqueue**, despite comments saying completed. Preserve the
  existing admission semantics in this batch; failed jobs retain the existing explicit Retry path.
- Baseline full-suite log: 643/0; later permission and batch checks are recorded in
  `../reviews/2026-10-10/output-safety.md`. These are earlier results, not plan-execution evidence.
- Available notarized export is 1.0.2, DMG/appcast 1.0.5, current runnable Debug 1.0.6 (106).

## Acceptance criteria

- **AC1:** When scans A and B overlap, only the latest request may publish recordings, selection,
  errors, status, loading state or warmed date-cache results, including two scans of the same URL.
  Changing source immediately prevents adding the previous source's rows to the queue.
- **AC2:** Events arriving during discovery trigger one coalesced trailing discovery. A timeout
  schedules a bounded retry without requiring another filesystem event. Polling settled files
  remains cheap. Disabled/removed/replaced coordinators cannot enqueue or publish late results.
- **AC3:** An enabled root absent at launch resumes after remount without a toggle/relaunch;
  the same holds after disconnecting an active root, including a changed mount path. Loss of
  availability invalidates old work before recovery; healthy entries are not restarted.
  Disabled/removed entries never reactivate automatically.
- **AC4:** Settled new footage reusing filenames but with different capture identity is admitted;
  the same recording remains suppressed across scans/relaunches. Restored live jobs are not
  duplicated. Weak identity and legacy ambiguity cannot silently become “already processed.”
  Metadata and settled samples must describe the same observed file generation; stale discovery
  metadata cannot authorize admission or suppress replacement footage while refresh is stalled.
- **AC5:** Unknown/corrupt queue bytes survive subsequent saves byte-for-byte. Failed preservation
  prevents replacement writes. Release UI explains recovery and can reveal the retained original.
- **AC6:** Existing queue compatibility, DJI/GoPro grouping, source fidelity, paired video/SRT
  collision protection, output-picker Cancel, unavailable-output recovery and toolbar remain green.
- **AC7:** A dated evidence record distinguishes automated, manual, device and signed-artifact
  checks. No Debug build stands in for release acceptance.
- **AC8:** A persisted admission awaiting ledger commit remains recoverable after watch disable,
  removal or restart. Manual Start/Retry cannot bypass the commit gate. Cancellation/removal of a
  queued job invalidates its outstanding admission retry; storage recovery cannot resurrect it.

## Decisions and interfaces

### D1 — legacy history and weak identity (accepted 2026-10-10)

User confirmed **Hold for review** for actual app upgrades. Ambiguous recordings wait while
unrelated new recordings continue. The review offers **Already processed** (record this exact v2
identity) and **Process once** (authorize this identity to enter normal readiness/dedup/output-safety
checks). Cancel does nothing. Weak evidence remains explicitly weak even after a per-identity decision.
Never promote the first new candidate matching an old hash to processed, and never keep a permanent
v1-hash fallback. Preserve the legacy file/entries. An initial reprocessing answer was based on a
misunderstanding that the question concerned testing; the clarified hold-for-review answer supersedes it.
D3's exact queue-footer placement is accepted by the Wave 2 execution request. D4 is accepted by
the subsequent “next” request following the status report's exact placement proposal.

### D2 — identity contract

Use a versioned, deterministic canonical encoding and SHA256, not interpolated delimiter strings.
Descriptor inputs: ordered clips' camera family, stem/index/variant, GoPro recording number,
embedded capture date with fixed numeric precision, normalized exact duration, path relative to
this watch root, and captured settled video byte size. Missing capture date is weak evidence;
mtime may aid display/review but cannot upgrade it into reliable recording identity.
Do not claim byte-level identity: two files with identical descriptors can collide semantically.
Full video hashing and a general media catalog are outside this repair. Include a same-metadata
limitation in the acceptance evidence rather than describing metadata as proof of unique content.

Capture descriptors only after stability/complete-set gates; do not call live `totalFileSize` from
fingerprinting. Use separate stable ephemeral group keys for sampling/quiet-window history.
Revalidate the sampled files before admission. Store a versioned optional watch-identity snapshot
on the queued job (absent on old jobs); existing manually queued jobs stay compatible. Include the
originating watch-entry ID and stable ledger namespace for recovery, not just the recording hash
or current root path. These fields are optional only for pre-existing/manual jobs.

Bind each metadata read to an observed file generation: capture size/mtime and an available
session-local file identifier before and after probing, plus the root lifecycle generation.
Reject a read spanning a change. A changed/missing sample, root loss or relevant change event
invalidates that clip's cached metadata and review approval. Once files settle, re-probe invalid
clips and regroup from current metadata before constructing the descriptor; verify the samples
again before admission. Merely hashing an old `DJIClip` after settling is insufficient. Polling
unchanged files remains cheap; refresh/probe work shares W4's timeout and worker budget. During
a stalled refresh, affected groups wait while unaffected current groups may proceed. Session-local
identifiers are freshness checks, never durable recording identity. Undetectable same-metadata
replacement remains within the explicitly recorded descriptor limitation above.

### D3 — queue recovery contract and exact UI proposal

On read/decode failure, preserve `queue.json` at a unique sibling recovery name before allowing any
replacement. If preservation fails, leave it untouched and disable persistence writes for that
manager instance. Missing file remains normal first launch. Keep recovery state separate from
ordinary save errors, so a later successful save cannot erase the recovery notice.
Reuse `Views/QueuePanel.swift` → `FooterBar` persistence notice (currently around line 951); add a
compact AppKit-backed **Show in Finder** action adjacent to that notice. Explain whether new work
will persist or is temporary. No speculative JSON salvage or new recovery window.

### D4 — watch review UI placement (accepted 2026-10-10)

Reuse `Views/WatchFoldersPanel.swift` → `WatchFolderRow`, directly below the output path and beside
existing unavailable-output explanation. Add a history-review status/count and **Review…** action.
A small sheet lists ambiguous current recording names/capture dates/clip counts and D1 actions.
Use AppKit controls through wrappers for new interactive controls. Manager forwards coordinator
review records/actions; the sheet never edits ledger storage directly. Implement this placement
only once the plan/UI proposal is accepted; do not add a generic settings surface.

## Schedule and ownership

All app paths below are under `01_Project/Conjoyn/`; tests under `01_Project/ConjoynTests/`.
A task is one logical patch with red-to-green checks. If a listed task exceeds ~30 minutes, keep
its named substeps as separate checkpoints rather than expanding scope. Estimates include more
than code typing: allow **one focused working day, with another day of contingency**, plus release
packaging/checks and external waits. The earlier 2–4 hours was optimistic about migration/testing.

Coordinator owns project generation, build/test processes, docs, integration, Git and shared
`01_Project/build/ReleaseBlockers-*` directories. Agents may inspect any file; only the named owner
edits its files. No concurrent Xcode/test jobs against shared caches, host app, or user defaults.
Test fixtures use temporary directories and isolated defaults; never mutate the user's real queue.
Existing dirty search/UI/Apply changes remain intact; compare overlapping diffs before each edit.

### Wave 1 — independent foundations (three parallel owners)

- [x] **S1 — Own scan requests and reject stale publication.**
  - Depends/external gates: none. Owner: scan agent.
  - Owns: `ConversionViewModel.swift`, `ContentView.swift`, new `ConversionScanTests.swift`.
  - Interface: one request path used by source selection and manual rescan; synchronous generation
    invalidation, retained task, captured source and injectable discovery. Cancellation is advisory;
    generation is authoritative for every completion including detached date prewarm.
  - Steps: controlled-reader red tests; request/lifecycle fix; guard cache/publication/enqueue.
  - Success: AC1; preserve search reset, sort, renamed-output and existing Apply behavior.
  - Backpressure: T with `ConversionScanTests`, `RecordingSearchTests`, `QueueManagerTests`.
    Drive A/B completions in both orders, same-source rescans, cancellation-ignoring reader,
    immediate source switch and old prewarm completion. Use continuations, not timing sleeps.

- [x] **Q1 — Preserve unreadable queue and retain recovery state.**
  - Depends/external gates: none. Owner: queue agent.
  - Owns: `Services/QueueManager.swift`, new `QueueRecoveryTests.swift`.
  - Interface: typed/read-only recovery state (original URL, preserved URL if any, reason,
    writesAllowed), separate from transient `persistenceError`; non-overwriting preservation seam.
  - Steps: failure/preservation tests; load/save protection; persistent Release log/notice state.
  - Success: malformed/unknown data preserved exactly; failed move/copy leaves original protected;
    later successful saves retain notice; repeated recoveries cannot overwrite earlier backups.
  - Backpressure: T with `QueueRecoveryTests`, `QueuePersistenceCompatTests`, `QueueManagerTests`.
    Inject preservation failure deterministically; cover missing/valid-empty files and 1.0.4 fixture.

- [x] **W1 — Define settled v2 identity and queue snapshot compatibility.**
  - Depends/external gates: none. Owner: watch identity agent.
  - Owns: new `Models/WatchRecordingIdentity.swift`, `Models/ConversionJob.swift`, new
    `WatchRecordingIdentityTests.swift`; coordinator owns any shared fixture/project adjustment.
  - Interface: pure descriptor → strong/weak versioned identity; optional Codable job snapshot.
    Snapshot includes watch-entry/ledger ownership for admission recovery independent of a monitor.
    Does not yet switch production ledger keys. No I/O in the pure fingerprint function.
  - Success: equal descriptors stable across fresh objects/JSON; changed capture identity with
    reused filenames differs; family/order/size differences distinguish; unavailable facts explicit.
  - Backpressure: T with `WatchRecordingIdentityTests`, `QueuePersistenceCompatTests`.
    Test canonical encoding, rational normalization, nil fields and old queue decoding unchanged.

### Wave 2 — independent recovery layers

- [x] **Q2 — Wire the queue recovery notice/reveal.**
  - Depends: Q1. External gate: acceptance of D3 placement before implementing the new action.
  - Owner: queue agent. Owns: `Views/QueuePanel.swift`, a new narrowly scoped AppKit wrapper only if
    none is reusable, `QueueRecoveryTests.swift` for state behavior. Does not edit shared DesignControls.
  - Success: notice visible with empty queue and after new saves; reveal targets retained bytes;
    failed preservation clearly says persistence is blocked. No changes to unrelated queue controls.
  - Backpressure: T `QueueRecoveryTests`; Debug build B; exact live notice/reveal check in E1.

- [x] **W2 — Version ledger storage and classify legacy ambiguity.**
  - Depends: W1. External gate: D1 migration policy resolution.
  - Owner: watch identity agent. Owns: `Models/ProcessedGroupLedger.swift`,
    `ProcessedGroupLedgerTests.swift`. Review-required narrow integration also owns the coordinator,
    its tests and existing watch-row status solely to pause admissions on ledger storage failures;
    W3/W4 retain their larger integration/lifecycle scope.
  - Interface: known v2 / new / legacy-ambiguous / weak / storage-unavailable classification;
    explicit per-v2 resolution; preserve original v1 file and unsupported/corrupt storage.
  - Steps: v1/v2/unknown-format fixtures; safe storage/migration; decision persistence.
  - Success: no global v1 fallback, silent ledger reset, or first-seen auto-promotion. Failed writes
    remain observable and do not pretend history is durable; automatic admission pauses if history
    cannot safely be loaded/persisted. Keep existing enqueue-time semantics explicit.
  - Backpressure: T `ProcessedGroupLedgerTests`, `WatchRecordingIdentityTests`.
    Include legacy same-name/different-capture candidates, restart and failed persistence.

- [x] **M1 — Recover enabled watch roots after mount.**
  - Depends: none. External gates: real removable device only for E1.
  - Owner: watch lifecycle agent. Owns: `Services/WatchFolderManager.swift`, `WatchFolderManagerTests.swift`.
  - Interface: injectable mount/unmount, availability and root-resolution events; distinguish a
    healthy active root from an allocated coordinator. On root loss mark the entry unavailable
    and deactivate it; W4 supplies the definitive in-flight-result fence. Retry only enabled
    inactive/unavailable entries with bounded fallback polling. Re-resolve the saved bookmark on
    return, update the last-known path and rebuild at the resolved URL; never substitute a same-name
    volume merely because its path exists. Preserve healthy coordinators and output intent.
  - Success: absent-at-launch → available resumes once; disabled/removed stays inactive; duplicate
    mount/poll events do not reset healthy coordinators; active → unavailable → available also
    resumes once, including a changed mount path. Observer/timer teardown verified.
  - Backpressure: T `WatchFolderManagerTests`; fake mount/unmount/availability and clock events,
    changed-path resolution and another healthy root remaining active; E1 device test. Suspended
    discovery completions across disconnect/reconnect are validated after W4 integration.

### Wave 3 — serialize watch integration; independent files already complete

- [x] **W3 — Integrate v2 admission, live-job dedup and review actions.**
  - Depends: W1, W2, M1, Q2. External gates: D1 and D4 accepted.
  - Owner: one watch integration agent (exclusive coordinator/manager/UI ownership this wave).
  - Owns: `Services/WatchFolderCoordinator.swift`, `Services/WatchFolderReconciler.swift`,
    `Services/WatchFolderManager.swift`, `Views/WatchFoldersPanel.swift`,
    `WatchFolderCoordinatorTests.swift`, `WatchFolderReconcilerTests.swift`,
    `WatchFolderManagerTests.swift`. Exclusive follow-up ownership of `Models/ConversionJob.swift`,
    `Services/QueueManager.swift`, `Services/QueueManager+Operations.swift` and
    `Services/QueueManager+Processing.swift` only for durable-admission gating below;
    new `WatchAdmissionTests.swift` keeps those regression cases separate.
    Follow-up ownership of `Views/QueuePanel.swift` covers admission recovery/hold presentation
    after Q2, reusing its notice conventions without replacing queue-file recovery state.
    Also owns `Services/DJIFolderReader.swift` and focused reader tests if the generation-bound
    probe seam requires them; preserve the manual scan interface used by S1.
  - Steps/checkpoints: metadata/sample generation binding + settled snapshot; live-job exclusion;
    durable admission/recovery; review state/actions; UI binding.
  - Success: AC4; no restored live-job duplicates. Use saved v2 identity for new jobs; old jobs
    without it require conservative source/clip matching, not reading possibly replaced media and
    claiming it was the old job. Distinguish admission from completion. Retire old group-state keys
    safely without treating meaningless legacy states as proof of completion.
  - Review decisions bind exact v2 descriptors; recheck readiness/destination/files before enqueue.
    Repeated clicks/events enqueue at most once; cancel/relaunch preserves unresolved cases;
    new nonambiguous groups continue; other roots' status/history remain isolated.
  - Durable admission policy: queue persistence must succeed before recording a v2 admission;
    do not start processing a newly admitted watch job until ledger persistence also succeeds.
    Persist an admission-pending marker with the job so restart cannot bypass that gate. On ledger
    failure retain the recoverable queued job, pause its automatic processing, expose storage
    recovery, and retry ledger commit idempotently before making it runnable. On queue-write failure
    do not seal the ledger or start the job; retain a visible in-memory recovery state. Do not
    clear the pending marker until ledger commit; reconcile a persisted pending job with an already
    committed ledger on restart. This is a narrow watch-admission gate, not a general queue rewrite.
    Explicit per-recording Already processed decisions may persist without a queued job by design.
    Preserve existing manual jobs/retry behavior and never treat a failed admission as completed.
  - Recovery ownership: the manager owns admission recovery separately from its running
    coordinators, loading pending jobs even when their entries are disabled/removed. Use the job's
    persisted ledger namespace; serialize writes with any live owner of that ledger. Removing a
    watch entry must retain ledger/recovery storage referenced by queued admissions; deleting the
    entry must not delete their recovery path. Re-adding the root must still exclude existing live
    jobs even though the new entry has a different namespace. Do not add automatic orphan cleanup
    in this batch. Surface pending recovery on the queued job even if its watch row is gone.
  - Disable/remove stops discovery, not recovery of saved state. Ledger repair may finish, but a
    pending admission held by disable/remove requires explicit Start/Retry after repair; persist
    that hold across restart. Every processing entry point enforces the ledger gate. Job Cancel,
    Remove and Clear invalidate retry ownership before mutation; recheck job existence/status
    before commit or release. Do not seal a cancelled/removed uncommitted admission. An already
    committed admission retains the existing ledger semantics; cancellation does not undo history.
    A failed queue save remains visible and must not be reported as durable cancellation/removal.
  - Test partial failures before/after each persistent write and restart with only one side saved;
    a pending job must neither execute prematurely, duplicate, nor silently suppress unqueued work.
    Cover ledger failure → disable/remove watch → restart → storage recovery, re-add under a new
    entry ID, manual Start/Retry before/after recovery, and job Cancel/Remove/Clear during retry.
    Verify unrelated runnable jobs continue and referenced ledger storage survives watch removal.
    Also test weak identities with no legacy match, both review choices across restart, and changed
    descriptors invalidating prior review approval. Replace footage at the same path after metadata
    discovery (including equal byte size with changed mtime/file identity), settle new samples while
    refresh stalls, and prove old metadata neither enqueues nor marks the replacement processed.
    Cover changes during probing and regrouping when refreshed metadata changes group membership.
  - Backpressure: T `ProcessedGroupLedgerTests`, `WatchFolderReconcilerTests`,
    `WatchFolderCoordinatorTests`, `WatchFolderManagerTests`, `WatchAdmissionTests`,
    `QueuePersistenceCompatTests`, `QueueRecoveryTests`.

### Wave 4 — same coordinator, dependent on integrated identity path

- [x] **W4 — Retain refresh requests and fence lifecycle/timeout results.**
  - Depends: W3. External gates: none. Owner: watch integration agent.
  - Owns: `Services/WatchFolderCoordinator.swift`, `Services/WatchFolderManager.swift`,
    `WatchFolderCoordinatorTests.swift`, `WatchFolderManagerTests.swift`;
    `Views/WatchFoldersPanel.swift` for the existing status presentation;
    `Models/WatchFolderSettings.swift` only if an internal bounded retry policy cannot reuse current timing.
  - Interface: one active discovery generation, pending-refresh flag, retry deadline, lifecycle token.
    Disable/remove/root loss/root replacement invalidate tokens and cached sample/metadata
    generations before stopping timers/monitors. Apply M1's unavailable transition synchronously.
  - Success: AC2; one trailing pass for a burst; timeout retries from timer without new FSEvent;
    late generations cannot update groups/state/ledger/status or enqueue. Resampling stays cheap.
  - Preserve nonblocking timeout behavior: task-group cancellation that waits for a wedged child is
    not acceptable. Bound abandoned underlying discovery work; at most one retired and one current
    scan per watch entry, with manager-owned accounting surviving coordinator replacement; retain
    retired-worker accounting through remove/re-add for the same canonical root and remount at a
    changed path (carry the existing root/entry association; path change is not fresh budget).
    Generation-validation re-probes share this budget, rather than spawning untracked work. Then expose
    “Discovery stalled” in the existing watch-row status, without a new reset control that bypasses
    the cap. Late retirement releases budget; disabling prevents restart. App relaunch is the
    recovery for workers that never return. Evidence must state the bound and recovery action.
  - Backpressure: T `WatchFolderCoordinatorTests`, `WatchFolderManagerTests`.
    Controlled discovery/clock tests: event during scan, event burst, timeout on quiet root, late old
    result, disable/remove while suspended, repeated timeout cap across settings/toggle/replacement
    and remove/re-add, disconnect/reconnect at a changed path while discovery is suspended,
    stale metadata awaiting re-probe, and healthy resampling during timeout. Only actual underlying
    completion frees capacity; an unavailable root cannot admit cached groups.

### Wave 5 — independent fault review then final integrated validation

- [x] **V1 — Independent review and targeted corrections.**
  - Depends: S1, Q2, W4. External gates: none. Owner: fresh reviewer, read-only source access;
    original owners make any corrections serially. Owns: review evidence only.
  - Inspect all post-await writes, old/new ledger compatibility, live queue dedup, failed storage,
    duplicate decisions/events, generation-bound metadata, admission recovery after watch removal,
    reconnect lifecycle fencing, and preservation/no-replacement guarantees. Check dirty-change overlap.
  - W4 review follow-up (pre-existing in W3): out-of-order copy can leave a short final segment's
    cached group eligible while discovery of a newly copied predecessor stalls. Review targeted
    directory-membership invalidation/regrouping before full D2/AC4 acceptance; tracked in TASKS.
  - Success: no unresolved blocker findings; each concrete correction has its relevant regression.
  - Backpressure: reviewer references real code paths and tests; no claim of correctness from consensus.

- [x] **V2 — Final suite/build and evidence handoff.**
  - Depends: V1. External gates: foreground user testing must not be disturbed.
  - Owner: coordinator; owns project generation if needed, shared Xcode resources, evidence/docs.
  - Success: full suite once after final fixes; fresh runnable Debug build; preserve prior user state.
    Follow standing graceful quit/relaunch policy for a fresh runnable build unless the user's newer
    foreground-testing instruction still applies; never launch the test-host product.
  - Backpressure: T without filters, then B. Record exact source commit plus dirty patch manifest,
    commands, result bundles, counts, build time/version and launched executable path.
  - Completion is automated only until E1 passes; ship readiness remains pending E2/E3.

## Commands (run from repository root during execution)

`T` means the following command, adding only the task's listed XCTest class filters:

```sh
xcodebuild -project 01_Project/Conjoyn.xcodeproj -scheme Conjoyn -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath 01_Project/build/ReleaseBlockers-Tests-DD \
  -clonedSourcePackagesDirPath 01_Project/build/DD/SourcePackages \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  -only-testing:ConjoynTests/ConversionScanTests test
```

Replace the example filter; repeat `-only-testing:ConjoynTests/<Class>` for multiple classes.
For V2 remove all filters and use a unique `-resultBundlePath` under `01_Project/build/`.
New test files require coordinator inspection of project membership; use `xcodegen generate` from
`01_Project` only if needed, inspecting the generated diff. No agent independently regenerates it.

`B`:

```sh
xcodebuild -project 01_Project/Conjoyn.xcodeproj -scheme Conjoyn -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath 01_Project/build/ReleaseBlockers-App-DD \
  -clonedSourcePackagesDirPath 01_Project/build/DD/SourcePackages \
  -disableAutomaticPackageResolution CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
```

Xcode cache/service sandbox access may require escalation; report actual results, not intended runs.

## External acceptance and release gates

- [x] **E1 — Live repair acceptance for 1.0.6 (scope exception, 2026-10-10).** User deferred
  disconnect/reconnect during active discovery to **1.1**; this scenario remains unverified, not passed.
  All other recorded E1 checks are accepted for this release. Follow-up is in TASKS → 1.1 acceptance;
  exact signed-artifact acceptance remains E3. Original checklist below retains the deferred scenario
  for traceability. Depends V2; owner coordinator + user; requires a safe foreground
  window and removable test volume. Use disposable footage/state, never corrupt the user's queue.
  Rapidly switch two sources and enqueue only the latest; add footage during discovery; launch with
  watch root absent then mount; disconnect an active root during discovery and reconnect, verifying
  recovery and the resolved path while a second healthy root continues; disable during scan;
  ingest two different recordings with reused
  names; relaunch without duplicates; exercise D1 review/cancel/relaunch; reveal quarantined queue.
  With isolated fault-injected storage, verify a pending admission remains visible/recoverable after
  watch removal and relaunch, and Start/Retry cannot bypass the storage gate. Record changed-mount-path
  coverage separately as simulated or physical; do not substitute one for the other.
  Repeat four-output video/SRT identity and unavailable-output recovery acceptance. Local simulated
  filesystems do not prove physical mount behavior. Unavailable hardware blocks only these claims.
- [x] **E2 — Freeze release scope/source (2026-10-10).** User approved all eight reviewed paths
  unchanged; local commit `c6a1b23d5ba03c322ab2fcbdf824cdc8c767e581`. All 170 committed source hashes
  and seven build inputs match the reviewed candidate. Final provenance and approved-scope draft
  notes: `../reviews/2026-10-10/release-source-freeze.md` and `.json`. No push/merge/package.
  Original requirement: depends V1; requires disposition of pre-existing dirty
  search/UI and September Apply changes. Preserve all work; propose an exact inclusion list and
  review it. No blanket stash/reset or accidental packaging of unrelated changes. Record final
  source commit/patch provenance and release notes. Gates packaging, not independent repairs.
- [x] **E3 — Actual release artifact acceptance (closed with user waiver, 2026-10-10).** Depends V2, E1, E2; requires release authorization,
  signing identity/notary credentials and update-test environment. Follow existing make-dmg and
  make-appcast recipes; never reuse stale export via SKIP_APP. Validate app/DMG signatures and
  stapling, packaged helper execution, and clean-install + 1.0.5 update path with disposable state.
  Re-run key scan/watch/queue/publication smoke flows on the exact signed artifact, including legacy
  watch upgrade. Record checksum/version/build/source/time; stage notes before appcast and include
  emitted deltas. Public upload/deployment is a separate authorized step, not part of this plan turn.

## Web research and design consequences (checked 2026-10-10)

These primary sources support API semantics; the repair design is inferred from current project code.

1. [Swift Task.cancel](https://docs.swift.org/latest/documentation/swift/task/cancel()/): cancellation
   is cooperative. Therefore correctness uses request/lifecycle tokens, not cancel alone.
2. [Apple FSEvents guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html): events can coalesce;
   scan-time modifications need another rescan. Therefore retain a trailing refresh request.
3. [Apple fileResourceIdentifierKey](https://developer.apple.com/documentation/foundation/urlresourcekey/fileresourceidentifierkey): identifiers are not persistent across system restarts.
   Therefore they cannot be the durable watch identity by themselves.
4. [Apple didMountNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didmountnotification): register with the workspace notification center. Use APIs available on macOS 14,
   not newer typed notification conveniences without availability handling.
5. [Apple data writing options](https://developer.apple.com/documentation/foundation/nsdata/writingoptions): atomic writes replace the destination after writing an auxiliary file. Atomic save alone
   does not preserve an unreadable old queue; recovery must happen first.

## Dependency audit, blocked tasks and execution log

Schedule checked: Wave 1 owners have disjoint files; Wave 2 owners have disjoint files. W3 waits for
ledger, manager and queue-recovery owners, then W4 serializes edits to the same coordinator. Review precedes
final suite so fixes cannot leave final evidence stale. Project/test execution is coordinator-only.
D1 gates W2/W3, D3 gates Q2, D4 gates W3, E2 gates packaging. These do not block S1/Q1/W1/M1.

Planning evidence: two read-only agents inspected scan/queue and watch/identity paths; primary web
sources above checked. A third independent agent reviewed the plan; its corrections to worker
budgets, partial admission failure, weak-identity tests and exact ownership were integrated;
its follow-up review found no remaining concrete plan blockers at that time. A subsequent source
review identified three additional gaps: recovery ownership after watch removal, cached metadata
outliving its sampled file generation, and active-root disconnect/reconnect. This correction adds
AC8 and extends AC3/AC4, D2, W1/M1/W3/W4, V1 and E1 to cover them. M1 defines root transitions;
W4 completes their async fencing. W3 owns metadata validation and admission recovery; W4 shares
its worker budget with re-probes. No new implementation wave or migration-policy approval is implied.
Wave 1 evidence: `../reviews/2026-10-10/release-blockers-wave1.md`. S1/Q1/W1 were implemented by
fresh-context agents, integrated by the coordinator and reviewed by a separate read-only reviewer.
The 118-test focused run passed; deliberate fault mutations caused 29 assertion failures across
21 new tests, then byte-for-byte restored source passed all 21 again. A separate Debug build passed
and its exact executable was launched after graceful termination of the old instance. These are
Wave 1 results only; V1/V2 and E1–E3 remain open. Q1 exposes recovery state/logging; Q2 UI is pending.
W1 adds a pure descriptor and optional snapshot only; production ledger/admission behavior is unchanged.

| Task | Assignment | Validation/evidence | Commit/exception | Next action |
|---|---|---|---|---|
| Planning | Main agent + scan_queue_plan + watch_plan + review_plan | Source inspection and primary-source research | Docs only; no app changes | Review plan; resolve D1; execution not requested |
| Plan correction, 2026-10-10 | Main agent | Three source-review findings incorporated into contracts, ownership and acceptance checks | Docs only; no tests/build | Resolve D1/UI proposals; execution not requested |
| S1, 2026-10-10 | scan_s1; coordinator integration; wave1_review | 4 deterministic tests covering both result/prewarm orders, stale errors, same URL and immediate enqueue; included in 118/0 and restored 21/0 | Uncommitted: overlaps existing search/Apply changes; new tests use uncommitted search API. Preserve E2 inclusion decision rather than commit unrelated work | Complete within Wave 1; final integration/live acceptance later |
| Q1, 2026-10-10 | queue_q1; coordinator integration; wave1_review | 8 recovery tests plus queue/compatibility regressions; failed-save gate detected by mutation | Local commit `3e434ee`; no push/merge | Q2 ready after D3 UI placement acceptance |
| W1, 2026-10-10 | identity_w1; coordinator integration; wave1_review | 9 identity/snapshot tests plus 18 compatibility tests; pinned independent digest; initial test compile unwrap corrected | Local commit `2590972`; no push/merge | W2 awaits D1 policy |
| Wave 1 handoff, 2026-10-10 | coordinator | 118/0 focused, 21/0 restored, independent review clear; fresh 1.0.6 (106) Debug build and executable path verified | Source manifest/evidence linked above; earlier dirty work preserved | Selected scope complete; M1 ready in Wave 2, Q2/D3 and W2/D1 gates remain |

Model fit: deep capability/high reasoning for concurrency, migration and independent review;
balanced implementation for isolated UI wiring. Use fresh task contexts during execution.

### Wave 2 execution, 2026-10-10

Q2/W2/M1 ran in fresh disjoint contexts `q2`, `w2`, `m1`; coordinator owned builds/Git/docs.
D1 clarified to hold for review; D3 placement accepted through execution request. Independent
`wave2_review` found the legacy caller failed open on ledger errors; expanded W2 ownership narrowly
into coordinator/tests/existing status presentation to pause further admissions. Regression tests
pass and follow-up review is clear. This does not complete W3 durable admission or W4 async fencing.

| Task | Validation | Commit | Remaining gate |
|---|---|---|---|
| Q2 | Recovery tests in 81/0; Debug build; source review | `23e99df` | E1 live notice/reveal |
| W2 | 20 ledger + 9 identity tests; 2 coordinator fault regressions; 81/0 integrated | `a13d563` | W3 v2 admission/review integration |
| M1 | 15 manager tests including 5 new deterministic lifecycle tests; 81/0 integrated | `a00d957` | W4 late-result fence; E1 physical device |

Evidence: `../reviews/2026-10-10/release-blockers-wave2.md` and accompanying source manifest.
Fresh final Debug build launched with exact path verified. No push/merge; pre-existing source
preserved. Selected scope complete; plan continues. Next: Wave 3 when requested, with D4 placement
acceptance; D1 resolved. Final integrated and live/release gates remain open.


### Wave 3 execution, 2026-10-10

The user's “next” after the exact Review placement proposal accepted D4 and authorized W3 only.
Fresh-context `wave3` owned the coupled source/tests serially; coordinator owned project membership,
Xcode checks, local Git checkpoint, artifact launch and docs. Fresh `wave3_review` independently
reviewed the implementation. No shared-source parallel editing occurred.

| Task | Validation | Commit | Remaining gate |
|---|---|---|---|
| W3 | 227/0 expanded focused; fault mutation caught; byte-restored 24/0 new tests; independent review clear; final standalone Debug build/launch | `4760ace` | W4 lifecycle/worker budget; E1 live UI/device/repair flows |

Review corrections cover cancellation rediscovery/restart, rejected-probe retry ownership, history
recovery without pending jobs, and unaffected recordings progressing during a stalled event refresh.
Self-review also tightened direct-rediscovery approval invalidation and captured-size grouping.
Cancelled uncommitted watch jobs remain explicit cancelled records across restart until Retry or
removal; no ledger admission is fabricated. Removing/clearing a job invalidates its recovery; this
batch does not create permanent per-recording deletion tombstones.

Evidence: `../reviews/2026-10-10/release-blockers-wave3.md` and source manifest. All pre-existing dirty
source hashes match the baseline. One final explicit MainActor UI-coordinator annotation was checked
by the final standalone build after tests; no behavior changed. No full-suite/live/device/signed
artifact acceptance claimed. Selected scope complete; plan continues. Next: W4 on execution request.


### Wave 4 execution, 2026-10-10

The explicit Wave 4 request authorized W4 only. Fresh-context `wave4` implemented the coupled
five-file patch; `wave4_review` independently reviewed it. Coordinator owned Xcode, Git, launch and
docs. Local scoped checkpoint `6f154ec`; no push/merge. Pre-existing dirty source hashes unchanged.

| Task | Validation | Commit | Remaining gate |
|---|---|---|---|
| W4 | 132/0 expanded focused; event-fence mutation caught (2 assertions); restored 32/0; independent review clear; standalone Debug build/launch | `6f154ec` | V1/V2; E1 physical/live; E2/E3 release |

Evidence: `../reviews/2026-10-10/release-blockers-wave4.md` and source manifest. Actual discovery work
is capped at two workers per associated root across lifecycle changes; only completion frees slots.
Both stuck means Discovery stalled; relaunch is recovery if neither returns. Metadata re-probes share
the cap while healthy sampling remains independent. Review fixes cover empty-success status,
queued-refresh ownership and cheap polling during re-probe. Real-manager fixture canonicalization
corrected a failed/interrupted check; final checks passed. No full-suite/device/release claim.

Pre-existing out-of-order-copy cached membership risk is tracked in TASKS and V1; W4 does not close
full AC4 acceptance. Selected scope complete; plan continues. Next: Wave 5 V1/V2 on execution request.


### Wave 5 execution, 2026-10-10

User explicitly authorized Wave 5 V1/V2. Fresh `v1_review` reviewed integrated source read-only;
`v1_membership` made serial corrections; coordinator owned builds/tests, Git, launch and handoff.
The cached-membership blocker is corrected with filename census including failed probes, affected
bucket invalidation, bounded asynchronous census, launch-event ownership and retained retries.
Review also drove alias-path and durable-test-assertion corrections. No unresolved concrete finding.

| Task | Validation | Commit | Remaining gate |
|---|---|---|---|
| V1 | Pre-fix 1 test/4 failures; 8 new regressions; final 64/0 focused; independent review clear | `ff18f37` (4 scoped files) | E1 live/device acceptance |
| V2 | Full suite 721/0; standalone Debug build; exact fresh 1.0.6/106 launch verified | Same source + preserved dirty patch manifest | E1, E2, E3 |

Evidence: `../reviews/2026-10-10/release-blockers-wave5.md`, independent review and source manifest.
Both census and metadata work share the two-worker bound; relaunch recovers permanently stuck workers.
Same DJI variant waits conservatively until complete metadata permits regrouping; independent buckets
continue. Source aliases are normalized inside bounded work. Prior dirty source hashes unchanged;
no push/merge. Selected scope complete; plan continues. Next: E1 safe live/device acceptance and E2
source-inclusion review; E3 exact signed-artifact validation follows their gates. No release claim.


### E1/E2 review and partial live acceptance — 2026-10-10

Coordinator owned foreground checks, isolated state, artifact restoration and docs; fresh-context
`e2_review` independently reviewed the eight dirty source/test files, then audited acceptance evidence.
No correctness blocker found in the proposed inclusion set. All 170 Wave 5 source hashes match;
base ff18f37 plus the candidate patch (including both untracked tests) reconstructs all eight paths.
Full 721/0 evidence reused; no production source changes or redundant suite/build.

E1 live checks passed for recovery/reveal, populated search/Find, four paired outputs, legacy
review/cancel/relaunch/decisions, reused-name capture identities, admission hold after watch removal
and relaunch, Start/Retry gating with storage recovery, latest-source enqueue, local output-access
recovery, and restored-queue Keep/Cancel/Apply. Large-card disable is corroborating only: definitive
reader overlap/event-followup timing remains unverified. No physical/remount checks: device not yet
identified. E1 remains unchecked. See `../reviews/2026-10-10/live-device-acceptance.md`.

E2 review complete, inclusion disposition still pending: recommend scan ownership, search/Find and
September Apply together, all eight files unchanged. Exact list, review limits, draft release notes,
patch and input hashes: `../reviews/2026-10-10/release-source-review.md` and candidate artifacts.
No commit while the proposed pre-existing source inclusion remains unresolved; no push/merge/package.
E2 remains unchecked until disposition/final provenance is recorded. E3 stays gated by E1/E2.

Normal Wave 5 Debug app restored (PID 33591); real queue/history/watch preferences byte/value
unchanged after restoration. Watch acceptance used a separately identified, re-signed copy with
matching compiled code; that is not signed-release acceptance. Temporary storage faults removed.
Outcome: blocked/incomplete at device identification, remaining live timing and source-scope choice.

### E1 external-drive and controlled timing follow-up — 2026-10-10

User identified `4.x - MORE` and authorized testing. Coordinator owned serial foreground/device
work; fresh-context `e1_review` independently reviewed the evidence without touching app state.
Original-helper baseline exports passed from disposable external and healthy internal roots.
Controlled live checks then held a probe invocation, added footage during discovery, observed
follow-up probing/two outputs, and disabled another held discovery through the UI before release.
No late job/output; original-helper relaunch retained OFF and no duplicates. The first run's Python
clock mismatch was corrected with a fresh-fixture repeat using shared `mach_absolute_time`.
These checks do not claim exact FSEvents receipt/coalescing or natural device latency.

Physical mount/reconnect and changed-path checks remain blocked: IINA holds an unrelated video
open on the authorized drive. Requested that the user close it; no unmount was attempted. The SSD
is external USB but classified Fixed, so it cannot establish SD-card-specific media/TCC claims.
Disposable external directory is retained for resumption. E1 stays unchecked; E2/E3 unchanged.

No production source change; all 170 source hashes matched; existing 721/0 and 64/0 reused.
No commit because the source-inclusion gate remains unresolved; no push/merge/package.
Normal Wave 5 Debug app restored, exact path verified (PID 42069), four real JSON files and watch
preferences unchanged. Evidence: `../reviews/2026-10-10/device-timing-acceptance.md` and
`e1-device-evidence/`. Outcome: blocked/incomplete at physical device availability; next close
the IINA video, recheck drive activity, and resume isolated mount/reconnect acceptance.

### E1 physical-volume mount follow-up — 2026-10-10

User closed IINA; clean drive-use preflight. Coordinator ran serial physical-volume checks;
e1_review independently reviewed evidence read-only. Native-helper passes: launch while real
volume unmounted, healthy-root export while absent, automatic external recovery after mount,
idle unmount, healthy-root export again, same physical volume mounted at a temporary path with
resolved UI/queue paths and successful new export, and return to original mount without duplicates.
Original-helper relaunch retained ledger bytes and output counts. Six outputs match decoded source
frames; six source fixture videos unchanged. No physical USB cable removal is claimed.

Active-discovery loss remains incomplete: first preflight saw the app's fixture read; second
attempt allowed only that verified isolated read but macOS refused graceful unmount (exit1,
dissenter Conjoyn). No force; volume remained mounted and gates released. E1 remains unchecked;
use disposable media for the remaining active-read interruption. No app defect inferred from
normal unmount dissent. Driver plist and completed-queue assumptions corrected and documented.

No production changes/new suite/build/commit; existing source-inclusion gate retained, no push.
Normal exact Debug build restored PID46197; four real JSON files/watch preferences unchanged;
original drive UUID/path mounted, temporary mountpoint removed. Evidence:
`../reviews/2026-10-10/physical-mount-acceptance.md` and `e1-mount-evidence/`.
Outcome: blocked/incomplete only at remaining active-read device-loss acceptance within E1;
E2 inclusion and E3 release gates remain unchanged.


### User scope decision — defer active-read device-loss test to 1.1

On 2026-10-10 the user deferred the remaining disconnect/reconnect-during-discovery scenario to
1.1. E1 accepted for revised 1.0.6 scope; no physical pass claimed for the deferred scenario.
TASKS carries the 1.1 acceptance item, decisions.md records the tradeoff, and V1/V2/E1 is archived.
E2 source inclusion/freeze and E3 exact signed-artifact acceptance remain required. This decision
does not authorize packaging or deployment. No production change or additional test run.


### E2 source freeze — 2026-10-10

User selected step 1 and approved all eight reviewed paths unchanged. Coordinator verified current
source/build hashes, reviewed diffs, staged exactly eight paths and committed locally as `c6a1b23`.
All 170 committed source blobs match tested hashes; seven ignored/declared build inputs unchanged.
Prior independent review/full721/0/focused64/0 and E1 live evidence reused; no source rewrite or
redundant suite/build. Final manifest and draft-note disposition: `release-source-freeze.md/.json`
in the dated review folder. E2 complete; E3 ready for the next authorized release-artifact step.
No merge/push/package/deployment. Existing dirty documentation/evidence preserved outside the source
commit. Selected scope complete; plan continues. Pre-clear state/session/index updated.


### E3 local artifact preparation — 2026-10-10

User requested the next step. Coordinator owned serial archive/export/signing, local packaging,
launch and docs; fresh-context e3_review reviewed preparation and acceptance boundaries read-only.
All170 source/seven input hashes match freeze. Clean Release archive/export passed; eight nested
Developer-ID/runtime/timestamp signatures verified, helpers execute, mounted local DMG matches
export file/symlink hashes. Exact fresh signed app launched PID55387 after graceful Debug quit.

Automatic approval review rejected make-dmg.sh because explicit approval was required for artifact
uploads to Apple; rejected script never ran. Separate approved local-only preparation completed.
ZIP/DMG are pre-notary and retained at build/E3-Acceptance. No notarization, stapling, clean-install,
upgrade or Sparkle pass; E3 unchecked. Explicit upload approval and disposable exact-artifact
acceptance environment remain required. Final DMG must be rebuilt after app stapling.

Evidence: ../reviews/2026-10-10/release-artifact-preparation.md and e3-evidence. No production source
edit, new suite run, merge/push/deploy. No new commit: E3 incomplete, existing dirty docs/evidence
preserved and frozen source HEAD unchanged. Outcome blocked/incomplete; pre-clear log/state updated.


### E3 notarization — 2026-10-10

User explicitly approved app and rebuilt-DMG uploads. Coordinator submitted reviewed ZIP; Apple
accepted, app stapled/validated/Gatekeeper accepted. Rebuilt DMG from that app; Apple accepted,
DMG stapled/validated/Gatekeeper accepted. Final mounted app hashes/symlinks match export; contained
signature/ticket/Gatekeeper/helper fixture checks pass. All170 source/seven input hashes unchanged.
Exact notarized app gracefully relaunched PID60407. Old105 DMG Ed25519 and extracted app signature
verified; no old-app launch or interactive upgrade. No new source/build/suite/commit/merge/push/deploy.

Feed generation failed: keychain conjoyn key absent. Automatic review rejected documented backup-key
source use pending explicit user approval; rejected command never ran. Local draft notes/final DMG
staged, but no signed106 feed/deltas. User confirmed no disposable GUI test environment; clean-install,
actual Sparkle upgrade, legacy migration and app-level smoke remain unperformed. E3 unchecked.
Fresh-context e3_acceptance_environment reviewed environment and independently audited final hashes,
source inputs and Apple evidence; no discrepancy. Details: ../reviews/2026-10-10/release-artifact-notarization.md.
Outcome blocked/incomplete: backup-key authorization and disposable acceptance environment. Pre-clear
log/state/index updated; source freeze and pre-existing dirty docs/evidence preserved.


### E3 feed and delta verification — 2026-10-10

User explicitly approved documented backup Sparkle key; generation succeeded. Three failed-signing
cache markers had suppressed new deltas; preserved/moved only those markers and regenerated.
One106 item, nine signed enclosures, three106 deltas. Independent CryptoKit verification passes all
nine lengths/signatures; coordinator reconstructed final app from103/104/105 and compared all file
hashes/symlinks/modes, then checked code signatures/tickets. All pass. Fresh read-only follow-up
review found no feed discrepancy; it did not independently rerun crypto/reconstruction.

No source/artifact rebuild or public upload. All13 referenced staging files have checksums; see
../reviews/2026-10-10/release-feed-verification.md. Backup-key approval resolved and persists for this
workflow. E3 remains unchecked only for exact-artifact GUI acceptance: no disposable environment
available (user confirmed), no waiver inferred. No commit/merge/push/deploy; frozen source and dirty
docs preserved. Outcome blocked/incomplete; pre-clear handoff synced.


### E3 release closeout — 2026-10-10

User explicitly selected “Publish 1.0.6; waive pending GUI acceptance.” Packaging, notarization,
feed signatures and delta reconstruction had passed. Clean-install, real updater installation,
legacy migration and final exact-artifact GUI smoke checks remain unperformed, explicitly waived
for this release. This closes E3 by scope exception, not by an invented test pass.
Exact 1.0.6/106 published; download, every feed asset, feed and site pages hash-verified over HTTPS.
See `../reviews/2026-10-10/release-publication.md`. All six sprint groups are closed;
physical active-read device-loss acceptance remains in the 1.1 backlog. No further release wave.
