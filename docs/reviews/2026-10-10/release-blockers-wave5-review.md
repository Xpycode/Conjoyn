# Wave 5 independent V1 review — 2026-10-10

Read-only source review against the release-blocker plan, starting at HEAD
`6f154ecd1da1c1524c3d2f5a94b75f0fcac9bcaa` plus the existing dirty source.
No builds, tests, app launches, Git mutations or user-state mutations were performed by this reviewer.
The coordinator owns correction validation and final source provenance.

## Initial verdict: needs correction

| Severity | Finding | Code path and effect |
|---|---|---|
| Blocker, AC4/D2 | Cached membership can admit incomplete out-of-order footage | `WatchFolderCoordinator.sourceDidChange` (original lines 446–454) filters stamps only for cached paths. `reconcile` polls `lastGroups` (550 onward), leaves the unchanged group's quiet timer intact (574–615), and checks only those members before admission (672–714). A short final segment can settle while discovery of a newly copied predecessor is suspended. The final-only descriptor is admitted and its subset output can start. |
| Same blocker, additional case | Successful partial discovery does not prove complete membership | `DJIFolderReader.read` enumerates all video candidates (84–113), but builds groups only from successful probes (120–156). A predecessor rejected because its generation changed, or because probing failed, disappears from the groups. A valid short final segment can still pass the complete-set gate. Stable probe failures are also absent from `retryPaths` (129, 134). A correction based solely on returned groups would retain this hole. |

Required regression: cache a short final segment, introduce its predecessor without changing the
final's sample, suspend discovery, advance stable polls/quiet time and assert no subset admission.
Release discovery, require fresh grouping and settling, then assert one full recording admission.
An independent filename bucket must continue while the affected bucket waits. Also enumerate a
predecessor whose probe is rejected/throws while a valid final is returned: no subset admission;
recovery must require successful fresh metadata. Include event and timeout/retry interleavings,
not just synchronous rediscovery. Original tests `testRefreshedGroupingReplacesOldMembershipBeforeAdmission`
and `testActualReaderRetainsChangedOnlyCandidateAndPollReprobesWithoutEvent` cover changed existing
members and a sole rejected candidate, not these membership cases.

## Other inspected contracts

- **Post-await ownership:** scan publication and date warming recheck `scanGeneration` before
  mutation. Watch discovery rechecks lifecycle, active request and disabled state before applying
  results, then event generation. Recursive re-probes return without subsequent stale publication;
  deferred cleanup is lifecycle-owned. The worker completion callback only releases its budget slot.
- **Ledger compatibility and decisions:** original v1 bytes are read without replacement; v2
  unknown/corrupt storage sets a load failure that blocks saves. Failed candidate writes do not
  publish decisions in memory. Legacy hashes cause review, not permanent v1 dedup. Weak identities
  retain weak classification after explicit resolution. Sealed decisions are idempotent.
- **Metadata generations:** reader probes bind before/after size, mtime and session file identifier;
  coordinator filters results against current generation and revalidates every admitted member.
  Descriptor size comes from sampled history. This protects member freshness, but alone does not
  establish the membership completeness identified above. Identical durable descriptors remain
  an acknowledged metadata-identity limitation, not proof of identical bytes.
- **Live queue and failed storage:** snapshot identity/root ownership suppresses restored live jobs;
  old jobs use conservative clip-path overlap. Cancelled admission-pending records suppress automatic
  recreation. Queue-save → ledger-commit → pending-marker clearance is synchronous on MainActor;
  failed final save restores the in-memory gate. Processing entry points check `watchAdmissionBlocked`.
- **Recovery after removal:** manager retains ledger storage, obtains recovery ownership from saved
  snapshot namespace and keeps pending admission recovery observation alive independently of watches.
  Disabled/removed entries impose explicit Start holds; Start/Retry cannot clear uncommitted admission.
  Cancel/remove/clear invalidate current in-memory retries. Failed persistence remains visibly failed;
  this review does not claim an unsaved removal survives process loss.
- **Reconnect fencing and worker cap:** root loss drops manager publication ownership and disables the
  old coordinator. New lifecycle work cannot receive old results. Budget aliases survive coordinator
  replacement and changed-path bookmark resolution. Only actual underlying completion frees slots.
- **Queue preservation:** load failure copies to a UUID sibling through non-overwriting `copyItem`;
  failed preservation leaves writes gated. Successful later saves do not clear recovery state.
  Existing output publication callers retain private-workspace and no-replacement publication paths;
  late sidecar failure retains the published video. No new preservation regression identified.

These are source-review conclusions supported by inspection of the corresponding existing tests,
not new runtime evidence or exhaustive proof. Stop lifecycle behavior is explicitly deferred by the plan.

## Dirty-change overlap

Inspected current diffs for `ConversionViewModel`, `ContentView`, `ConjoynApp`, `DesignControls`,
`RecordingsList`, and `QueueManagerTests`, plus the untracked scan tests. S1 scan ownership and
search/September Apply changes coexist in `ConversionViewModel`; a blanket file commit would mix
their scopes. Watch membership correction can remain in the coordinator/reader/test surface and
does not need those dirty UI files. Preserve all pre-existing files and leave final release inclusion
to E2. Coordinator owns hash/patch comparison; this reviewer has not independently reproduced the
historical baseline hash comparison.

## Correction follow-up

Reviewed the initial coordinator correction and three new controlled regressions. The filename
census uses family/variant/GoPro-number boundaries, requires all enumerated paths to have successful
current-generation probes, compares before/after census, and resets affected quiet timers. The
cached-tail and failed-predecessor cases are now closed in the inspected logic. Polling rechecks
membership without requiring an event, and review actions recheck census before writing decisions.
An unrelated variant can continue. Existing fake-discovery tests with nonexistent fixture files
have an empty physical census; that compatibility is harmless for their injected samples, but they
do not prove production membership behavior. The new regressions create real filename entries.

**Additional correction required: synchronous census bypasses W4's execution boundary.**
`readMembership` calls `resolveMediaFolders` and `contentsOfDirectory` synchronously from the
MainActor coordinator. It runs before `discoveryBudget.acquire`/`withDiscoverTimeout` at every
reconciliation, after discovery completion, and in the review-click handler. `resolveMediaFolders`
itself enumerates the root and candidate child directories. A stalled directory operation on a
removable/network filesystem can now block UI, timeout delivery and other roots' sampling before
the bounded discovery code can act. This also changes settled polling from per-known-file sampling
to complete directory enumeration. Move census work off MainActor with bounded ownership and
lifecycle fencing; an uncooperative census must not spawn unbounded replacement workers. A suspended
injected census should prove timeout/lifecycle responsiveness and the worker ceiling. V1 clearance
remains withheld pending disposition/correction of this newly introduced stall path.

The coordinator reports a pre-fix failing regression (one test, four failures); this reviewer did
not execute it. Integrated green verification was still running at this review checkpoint.

### Final asynchronous correction inspection

Re-inspected the subsequent coordinator/manager patch and seven new coordinator regressions.
The synchronous census finding is closed: filename enumeration is invoked through the asynchronous
reader seam and the same bounded timeout worker mechanism as discovery. One active census is
coalesced; timed-out underlying work retains its budget slot until actual completion. Lifecycle
invalidation drops census publication ownership without releasing occupied slots. Post-discovery
census does not deadlock waiting for its own discovery slot: the timeout helper awaits the worker
completion callback before returning a successful discovery result.

An intermediate asynchronous revision incorrectly checked each waiter's event generation rather
than the census task's launch generation. Review identified that a newer event could join an old
census and accept obsolete membership. It also identified that rejecting the census could lose the
only refresh request for a new independent bucket. The inspected final revision stores the launch
event token with the shared task, validates it for every waiter, and records pending refresh before
the first await. The next poll retains and schedules the trailing discovery. The new controlled
event-joining-census test covers stale admission rejection and discovery of a new independent bucket.

Review-action completion uses the same census ownership guards, then obtains the current review
record and rechecks member generations before the synchronous ledger write. Repeated clicks cannot
write an obsolete removed record. MainActor coordination serializes the final admission/ledger writes.
No remaining concrete production blocker was found in this final source inspection.

One test-evidence correction was requested: the two membership-review tests originally inspected
the original `ProcessedGroupLedger` struct after passing a copy into the coordinator. That assertion
cannot detect a coordinator ledger write. Reopen the retained ledger directory for the assertion.
Coordinator owns that correction and the focused/full-suite evidence. Source-review clearance does
not assert those tests passed, physical mount behavior, live UI acceptance or signed release readiness.

Subsequent coordinator report: focused run finished 63 tests with three assertions failing in the
existing actual-reader retry case. Path-spelling consistency (`/var` versus `/private/var`), stalled
status retention after post-discovery census timeout, and the ledger-test assertion are undergoing
narrow correction. Final V1 verdict remains pending re-inspection of those changes and green evidence.

### Final narrow corrections reviewed

Re-inspected the root-relative census representation, original-path generation lookup, post-discovery
census failure handling, and corrected persistent-ledger assertions. Census and discovery filenames
now compare relative to both the selected and resolved root spellings; resolving the root happens
inside the bounded worker. Metadata stamps still use the original discovered URL, avoiding a lookup
mismatch. A failed post-discovery census returns without publishing the result, retains Discovery
stalled, and schedules a bounded poll-driven refresh. The eighth new coordinator test covers that
failure/retry. Both review-decision tests now reopen durable ledger storage.

**Final source-review verdict: approved for V2 validation.** No unresolved concrete blocker found
in the inspected final correction. Test execution remains coordinator-owned; the focused actual-reader
recheck was running at this checkpoint. Full-suite, live/device and signed-artifact acceptance remain
separate gates. This verdict supersedes the pending source-review verdicts above, which are retained
as the record of findings and their corrections.

A later focused run exposed the reverse alias direction: enumeration may yield `/var` when the
selected root already uses `/private/var`. Re-inspected the subsequent small correction: census URLs
are canonicalized inside the worker, and their observed root aliases are retained for matching the
reader's original clip paths. Both selected-root alias directions now reduce to the same relative
membership key without moving filesystem resolution onto MainActor. No further concrete source
blocker identified; final clearance remains conditional on coordinator green validation of this
exact revision, superseding the earlier run's failed alias evidence.
