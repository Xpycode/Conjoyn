# E1 live/device acceptance — 2026-10-10

**Later follow-up:** [device/timing acceptance](device-timing-acceptance.md) records external-drive
ingestion and controlled live discovery passes. Physical mount/reconnect checks still remain;
the original observations and limitations below describe this earlier run.

**Partial live acceptance; E1 remains open.** Foreground permission was confirmed by the user.
No disposable removable volume was identified during this run. Read-only disk preflight found
one external physical 4 TB disk; it was not used, unmounted, renamed or disconnected.

## Artifact, isolation and preservation

Started with the Wave 5 standalone Debug 1.0.6 (106), source base `ff18f37` plus the reviewed
candidate patch. All 170 source hashes and the recorded executable hash matched. The app initially
ran as PID 21473. No new application build or implementation change was made.

Initial recovery/search/four-output checks used that exact original app with HOME and
CFFIXED_USER_HOME redirected to `01_Project/build/E1-Acceptance/Home`. Foundation home/application
support resolution was verified first. The test corrupt queue was created only in that home.

Because home redirection alone does not prove preferences-daemon isolation, subsequent watch tests
used a copied app with bundle ID `com.lucesumbrarum.conjoyn.e1acceptance`, ad-hoc re-signed, with the
same redirected home. Both the launcher executable and **Conjoyn.debug.dylib compiled __text**
sections match the original. Signatures/bundle identity differ: this is an isolated Debug harness,
not acceptance of an exact signed release. `e1-evidence/acceptance-binary-provenance.json` records
both executable hashes and compiled-code hashes. Production source is unchanged.

Only the separate acceptance preference domain was seeded/edited for watches. Three initial test
entries had real bookmarks to disposable directories, two stable polls, a two-second quiet window,
0.25-second polling and a 15-second discovery timeout. This is accelerated local testing, not a
claim about timing on a real SD card. Later large-card watch used normal default settings.

Afterward both injected permission faults were restored. The isolated app quit gracefully and the
original exact Wave 5 app was relaunched with normal environment: **PID 33591**, executable
`01_Project/build/ReleaseBlockers-App-DD/Build/Products/Debug/Conjoyn.app/Contents/MacOS/Conjoyn`.
All four protected real queue/history JSON files and the real watch preference keys were unchanged
even after restoration. See `e1-evidence/checks.json` and `restore-normal.log`.

## Observed live results

| Flow | Result and evidence |
|---|---|
| Corrupt queue and reveal | PASS. Notice visible in empty queue; original fixture retained byte-for-byte. Show in Finder selected that exact recovery file in the isolated home. Notice remained after new queue saves. `recovery-ax.txt`, `four-done-ax.txt`; original/recovery bytes retained under build/E1-Acceptance. |
| Search/Find | PASS for Cmd-F focus, typed query, populated filtering, unchanged selection and Escape reset. Search `0001` showed 1 of 2 while 2 of 2 stayed selected; Find exists in Edit. No comprehensive theme/layout, clear-button or every menu-open interaction claim. `search-ax.txt`, `menus-ax.txt`; subsequent four-job enqueue corroborates preserved selection. |
| Four outputs from reused card filenames | PASS. Two one-second recordings per card, identical stems across cards, one destination. Four distinct reservations and four completed outputs. Decoded video frame checksums match each corresponding source; parsed SRT indices/times/text match the correct card/color fixture. Eight source files unchanged. Writer adds a trailing blank line, so raw SRT bytes differ; initial byte-equality assertion was corrected to semantic cue comparison. `four-output-verification.json`, `four-done-ax.txt`. |
| Legacy review with unrelated progress | PASS. V1 hash for DJI_0001 held that exact recording; DJI_0003 and the second healthy root exported. Review explained historical ambiguity. Cancel/relaunch retained the hold; original legacy bytes unchanged. Already processed recorded one v2 decision. `history-review-ax.txt`, `review-after-relaunch-ax.txt`. |
| Reused names/new recording identity | PASS. Replacement DJI_0001 with a different capture date needed a new legacy review; Process once admitted it. The healthy root's replacement DJI_0005 with a changed capture date exported to a distinct collision-safe filename. Relaunch before replacement produced no extra outputs. These are metadata identity checks, not proof against identical-descriptor replacement. |
| Pending admission after removal/relaunch | PASS. Real write denial on only the disposable ledger directory retained a pending queue job and visible history-storage explanation. Removing its watch and relaunching retained the job. Start did not export it. A deliberately failed-status fixture exercised the row Retry action; Retry returned it to pending, preserving its admission marker, and Start still could not export. Restoring directory access committed history; the manual-start marker was retained; Start then completed exactly one output. `fault-*.txt`; queue snapshots under build/E1-Acceptance. |
| Source switching | PASS for the observed UI/enqueue flow. The 1,200-file source showed Scanning with Add disabled; immediately selected card B through the picker, then enqueued only B's two recordings. No slow-card jobs appeared. UI snapshots do not timestamp the old reader's actual completion, so deterministic stale-completion ordering remains established by the controlled scan tests. `scan-a-start-ax.txt`, `scan-b-result-ax.txt`; `scan-switch-queue.json` under build/E1-Acceptance. |
| Output unavailable/recovery | PASS for local permissions. Made only healthy-output unwritable, added DJI_0011: UI reported OUTPUT UNAVAILABLE, no destination output and no source fallback appeared. Restored access: one DJI_0011_joined.mp4 appeared at the intended output. This is not an unmount test. `output-unavailable2-ax.txt`. |
| Disable after starting discovery | Corroborating live check, timing not fully proven. Added the 1,200-file watch, copied a 1,201st file, disabled the third watch; UI stayed OFF, no slow-card queue job or output appeared, including after relaunch. UI says WATCHING before disable, not a reader-in-flight marker; do not claim controlled overlap from that alone. `watch-scan-start-ax.txt`, `watch-disabled-ax.txt`. |
| Restored queue Apply/Keep/Cancel | PASS. Two pending jobs restored with no selected output. Choosing apply-output offered a two-job Apply popover. Keep and picker Cancel preserved destinations. Reselecting the same folder offered Apply again; Apply persisted both new destinations. `apply-restored-ax.txt`; before/after queue snapshots under build/E1-Acceptance. |

No fresh XCTest/full-suite run was needed: production source stayed identical to Wave 5's **721/0**.
These are additional live checks, not replacements for that suite or physical/signed acceptance.

Show in Finder selection, Escape reset and the separate Keep/Cancel destination comparisons were observed by the
coordinator through successful tool calls/assertions; separate per-click snapshots were not retained.
`e1-evidence/coordinator-observations.json` records that distinction and original/retained hashes.
Independent evidence review verified the curated file hashes, fixture preservation, admission
markers, latest-source jobs and Apply IDs/destinations; it did not independently replay the UI.

## Test-driver limitations and remaining gates

The initial accessibility driver recursively walked the 1,200-file picker list and stalled. A short
app sample showed the normal `NSSavePanel.runModal` event loop, not an established app hang. Bounding
the driver's outline/table traversal resolved it. Do not add a new app defect or count the stalled
attempt as a successful scan check. The existing September ViewBridge timeout remains separately
tracked; this sample does not prove its recurrence.

The first manually authored failed-job JSON used `message` instead of Codable's `errorMessage`;
the app correctly quarantined that invalid disposable fixture. Retried with the correct schema.
Retry's accessibility label is Refresh because row help overrides the local Retry help; the actual
Refresh action was exercised. Failed driver lookups are not counted as successful clicks.

Still required for E1:

- Identify a disposable **physical** removable test volume. Launch with its watch root absent,
  mount it, disconnect during active discovery and reconnect; verify the resolved path and a
  second healthy root continuing. Record changed-path coverage separately as physical or simulated.
  Neither physical nor simulated changed-mount-path testing was performed here.
- A positive live event-during-discovery/trailing-refresh observation and a reader-in-flight
  disable observation with clear timing evidence remain unverified. The large-card toggle check
  is corroborating only; controlled regression coverage remains Wave 5 evidence.
- Device results should use the isolated harness for data safety and document its identity; E3
  must repeat key flows, legacy upgrade, clean install and 1.0.5 update on the exact signed artifact.

E2 review and exact source proposal: `release-source-review.md`, `release-source-candidate.json`
and `release-source-candidate.patch`. Inclusion disposition remains pending. No commit, merge,
push, package, notarization, appcast or deployment occurred. Public release remains 1.0.5.
