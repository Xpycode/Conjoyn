# E1 external-drive and controlled discovery checks — 2026-10-10

**Later follow-up:** [physical mount acceptance](physical-mount-acceptance.md) records completed
mount/path recovery after IINA closed. Loss during active discovery remains unverified.

**Partial acceptance; E1 remains open.** User identified `4.x - MORE` and explicitly requested
tests. Baseline ingestion and controlled discovery checks passed. Physical unmount/remount,
disconnect/reconnect and changed-mount-path checks were not attempted: IINA retained an unrelated
video file open on the drive. The user was asked to close that video; no reply had arrived at handoff.

## Device and isolation

- Mounted `/Volumes/4.x - MORE`: external USB SSD, APFS, 4 TB, approximately 2.9 TB free.
  Volume UUID `A7FC471B-9BBD-4190-98B6-0A5D3FA30278`; disk11s1, physical store disk10s2 at inspection.
  macOS reports **Removable Media: Fixed**. Do not claim SD-card removable-media/TCC acceptance.
- Only newly created `/Volumes/4.x - MORE/Conjoyn-Acceptance-20261010` was written. It contains
  disposable synthetic footage in `device`, `timing`, and `timing-repeat`; retained for the next
  physical-device run. Existing drive content was not modified, and the volume stayed mounted.
- Isolated app/home/scripts: `01_Project/build/E1-Device-Acceptance`. Bundle ID
  `com.lucesumbrarum.conjoyn.e1device`, ad-hoc signature, redirected HOME/CFFIXED_USER_HOME.
  Watch preferences use only that bundle domain. Outputs stay in the project build directory.
- All 170 Wave 5 source hashes matched. Mach-O compiled `__text` sections of the launcher and
  `Conjoyn.debug.dylib` match the normal Debug app; `provenance.json` records the hashes.
  No production source changes, rebuild, or new XCTest run. Prior 721/0 and 64/0 remain applicable.
- Three stable samples, 0.75-second polling, two-second quiet window and 90-second discovery
  timeout were used. This accelerates the quiet window; it does not establish default card timing.

## Results

| Check | Observation |
|---|---|
| External and healthy-root baseline | PASS with original helpers: one video/SRT pair exported from the external test folder and one from an internal test folder. Initial weak synthetic metadata correctly requested review; disposable clips were then given explicit capture metadata to exercise automatic admission. |
| File arrives during discovery | PASS, controlled live observation: helper held for original `DJI_0021`, `DJI_0023` copied while held, no early output, gate released, original clip re-probed and new clip discovered, two outputs published. |
| Disable during discovery | PASS, controlled live observation: helper held for newly added `DJI_0025`; third watcher switched OFF through accessibility UI; OFF captured before release; same helper PID subsequently exited successfully; no 0025 job or output after at least five seconds. Source remained present. |
| Relaunch with original helper | PASS: wrapper replaced by original ffprobe, isolated app re-signed/relaunched. Third watcher remained OFF, no 0025 job, its ledger unchanged, and output counts stayed one external + one healthy + two repeated-timing outputs. |
| Output/source checks | Four baseline/repeated-timing outputs decode to the same frame hashes as the synthetic source. Seven external fixture video files still match the strong source bytes. No claim of new real-camera codec coverage. |
| Restoration | PASS: isolated app quit gracefully, normal Debug 1.0.6/106 relaunched as PID 42069. Exactly one Conjoyn executable found at the expected normal build path. Four real JSON files and watch preference keys unchanged. |
| Physical mount/reconnect and changed mount path | NOT RUN: IINA still held the external volume open. No force unmount, app interruption, drive rename, or simulated mount substituted. |

## Timing evidence and limits

The first controlled run passed behavior but used incompatible Python `time.monotonic()` origins
between helper and driver. It is preserved under `build/E1-Device-Acceptance/first-timing-run` and
is not used for cross-process timing. Repeated with fresh root, watch ID, outputs, and a shared
`mach_absolute_time()` clock converted using `mach_timebase_info` in both processes.

Repeated-run ordering, in shared-clock seconds:

- Original reader held before new-file write at **201075.333050**; driver release request at
  **201078.336531**, actual helper release at **201078.344754**; both outputs observed at
  **201081.893031**.
- Disable reader PID **41551** held at **201082.421407**; UI action returned at
  **201082.599708**; OFF snapshot completed before release request **201082.752840**;
  helper released at **201082.776417**, ended successfully at **201082.786648**;
  no-job/output assertion at **201087.979762**. Both gates explicitly released before their
  45-second fallback. Same-PID ordering was checked programmatically.

The wrapper holds the helper invocation before executing original ffprobe; the production reader
is awaiting that invocation. It logs probes but not the app's exact FSEvents callback receipt.
These results establish added-file/follow-up behavior and disabled late-result rejection in a
controlled live app, **not exactly one coalesced callback or natural device-latency performance**.
Deterministic Wave 4/5 tests retain responsibility for exact coalescing/event ownership. This
modified-helper, re-signed harness is not acceptance of the exact signed release artifact.

Fresh-context `e1_review` reviewed scripts and initial evidence read-only. Its requested clock
correction, same-PID checks, retained queue/ledger snapshots and restrained callback claims are
reflected here. Curated repeated-run evidence and scripts: `e1-device-evidence/manifest.json`.
Raw earlier and baseline queue files remain under the build directory.
Final independent review verified all 18 curated hashes, shared-clock same-PID ordering,
successful helper exits, unchanged disable/relaunch queues and the stated coverage limits.

## Next

Close the unrelated IINA video and recheck volume activity. Then use the isolated harness to test
absent-at-launch mounting, loss during discovery, remount recovery and a healthy root continuing;
record physical versus simulated changed-path coverage explicitly. E1 stays unchecked until these
requirements are resolved. E2's eight-file inclusion decision and E3 exact signed-artifact checks
remain unchanged. No source commit, merge, push, package or deployment in this run.
