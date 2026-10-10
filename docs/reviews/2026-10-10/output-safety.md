# 1.0.6 output-safety validation — 2026-10-10

Target: Conjoyn 1.0.6 / build 106. Local Debug candidate; not a public release.

## Implementation and review

- S1.2: Cancel returns before changing the watch destination. Live configured output → alternate
  folder → Cancel preserved visible path and exact persisted entry/bookmark. A blue one-second
  generated DJI-named file then exported to the original output, proving the live coordinator
  destination. Temporary watch entry removed.
- S2.1: exclusively created private workspaces hold incomplete writes; `renamex_np(RENAME_EXCL)`
  publishes without replacement. Cleanup removes only private workspaces. Video/SRT conflicts fail
  clearly. A late SRT race retains and records the finished video; explicit Retry reserves a fresh
  paired name, and Reveal remains available. Independent review caught the initial Retry gap; it
  was fixed and re-reviewed clear. Case-equivalent destinations and dangling links are covered.
- S2.2: distinguish unconfigured, resolved, and configured-unavailable destinations. Re-resolve after
  async discovery and before enqueue; unavailable groups remain unsealed. Preserve bookmark/path,
  display recovery text, resume after access returns or destination is reselected. Independent
  review caught missing directory search permission; now both write/search access are required.
- User-added toolbar fix: port Penumbra's 2026-09-22 shared-toolbar-background fix, guarded for
  macOS 26+ while keeping macOS 14 deployment. Fresh window screenshot confirms capsules removed.

## Automated evidence

- Red: two publication tests reproduced video and SRT overwrites (7 assertion failures).
- First green focused run: 114 tests, zero failures (queue/persistence/concat/camera/watch manager).
- Retry/recovery focused run: 89 tests, zero failures.
- Watch + strengthened retry run: 19 tests, zero failures.
- Full suite: **643 tests, zero failures**; result `/private/tmp/conjoyn-106-full-20261010.xcresult`.
- Subsequent directory-permission fix: **19 watch tests, zero failures**.
- Clean Debug build and final toolbar build succeeded. Running artifact verified at
  `01_Project/build/Review-DD/Build/Products/Debug/Conjoyn.app`; bundle version 1.0.6 (106).
- Logs: `/private/tmp/conjoyn-106-{red,focused,retry-tests,watch-tests,full,permissions-tests,build,toolbar-build}.log`.

## Final live acceptance — passed

User confirmed all three checks: compact toolbar, four-output batch, and external-output
unavailable/recovery. Screenshots show four distinct video/SRT pairs and OUTPUT UNAVAILABLE →
SETTLING 1 with `/Volumes/4.x - MORE/FCP-temp` retained. The recovery sequence is user-reported;
no additional device instrumentation is claimed.

Read-only verification of the batch: all four compressed video stream SHA256 hashes match their
respective sources, all four sidecar identities match, and stems pair correctly. Persisted queue
records show all four completed with distinct actual outputs. See `batch-verification.json`.
The final automated four-recording regression passed (1 test, zero failures). Its initial two
failures were incorrect test expectations that completed jobs restore into the active queue;
all media assertions had passed. Corrected it to check persisted JSON, matching existing policy.

Staged-copy race tests force the production branch locally. Actual cross-volume failure/race
instrumentation remains unrun; the user's external-drive recovery check is separate evidence.
User app/watch/queue state retained at their request.

## Scope preserved

Existing unrelated search/UI and September Apply-fix changes remain in the working tree.
No push, merge, notarization, website update, or public release performed.
