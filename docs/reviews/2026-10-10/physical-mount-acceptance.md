# E1 physical-volume mount acceptance — 2026-10-10

**Later scope decision (2026-10-10):** user deferred the unverified active-read device-loss test
to **1.1**. E1 is accepted for the revised 1.0.6 scope. Results and original limitations below
remain unchanged; E2/E3 are still required. See decisions.md and TASKS → 1.1 acceptance.


**Partial acceptance; E1 remains open only for its remaining device-loss claims.** The user closed
IINA and authorized testing had already been established. New read-only preflight found no open
files on `4.x - MORE`. Native-helper mount/recovery checks passed. Loss during an active read was
not achieved: macOS rejected the graceful unmount. No forced unmount or USB cable removal occurred.

## Scope and results

The volume is the same physical external USB SSD, UUID
`A7FC471B-9BBD-4190-98B6-0A5D3FA30278`, APFS disk11s1 at inspection. These are **OS-controlled mount
cycles on a physical volume**, not simulated directories and not physical USB unplug/reconnect.
Its Fixed media classification still does not establish SD-card removable-media/TCC behavior.

| Scenario | Result |
|---|---|
| Watch root absent at launch | PASS. Gracefully unmounted volume, launched isolated app, observed enabled external watch WAITING and healthy internal watch WATCHING. Volume remained unmounted. |
| Healthy root while volume absent | PASS. Added `DJI_0051` to the internal fixture root; it exported before the volume was mounted. |
| Mount after launch | PASS. Same app process automatically discovered/exported `DJI_0041` after `diskutil mount`, without toggling or relaunching. |
| Active-discovery volume loss | NOT COMPLETED. Gate proved reader awaited `DJI_0043`; first driver preflight stopped on its open read. Repeated with `DJI_0045`, allowing only this identified isolated app's read-only fixture handle: `diskutil unmount` exited 1, dissented by Conjoyn PID44724. Volume stayed mounted; gate released in cleanup; clips then completed normally. No loss/recovery claim from either attempt. |
| Idle watch-root loss | PASS. Original helper restored; idle volume gracefully unmounted. External watch showed WAITING; internal `DJI_0053` exported while it was absent. |
| Changed mount path | PASS for a real physical volume at an explicitly specified test mountpoint. Mounted the same UUID at `/private/tmp/Conjoyn-E1-Physical-Mount-20261010`; existing watch followed its bookmark, UI showed the new path, and new `DJI_0047` exported. Saved queue source paths point to that temporary mount. No volume rename or simulated-filesystem substitute. |
| Return to original mount | PASS. Gracefully unmounted temporary mount, mounted at `/Volumes/4.x - MORE`, observed UI path restored without toggling. No duplicate output after the observation window. Temporary mountpoint directory removed. |
| Relaunch/history | PASS. Original helpers, same isolated preferences/home: eight-second observation, output counts unchanged (four external, two healthy), ledger bytes unchanged, same two completed persisted queue records and no new persisted jobs. |
| Integrity | Six output videos match synthetic source decoded frame hashes; six test source videos retain exact fixture bytes. These are small synthetic clips, not new real-camera codec acceptance. |
| Restoration | PASS. Test app quit gracefully; normal Wave 5 Debug 1.0.6/106 relaunched at PID46197, exact executable verified. Four real JSON files and watch preference keys unchanged. Original volume UUID/path verified mounted. |

## Evidence and limitations

Scripts and curated evidence: `e1-mount-evidence/manifest.json`. Raw evidence, preferences and
fixtures remain under `01_Project/build/E1-Device-Acceptance/mount-evidence` and its parent.
External fixtures remain only beneath `Conjoyn-Acceptance-20261010`; existing drive content was
not modified. Test preferences use only `com.lucesumbrarum.conjoyn.e1device`; normal app state
was snapshotted before testing and compared after restoration.

The native-helper checks used the original app's compiled code, with a separate bundle identity,
ad-hoc signature and redirected home. The failed active-read attempt additionally used the
previously documented bounded helper gate. No production code change, rebuild or XCTest rerun;
170 source hashes matched and existing 721/0 and 64/0 results remain valid. Original helper was
restored before idle remount/changed-path and relaunch checks. This is not exact signed-release
artifact acceptance. Quiet window was accelerated to two seconds as in the earlier harness.

Timing uses shared mach_absolute_time. First absent launch: unmounted 201666.131629, healthy
export observed 201670.274422, mounted 201670.817274, external export observed 201673.034272.
Changed mount: 201792.416379, new-path export observed 201795.331116; normal mount restored
201799.763420, no-duplicate check 201805.201989. These are observation timestamps, not performance
guarantees or claims about event delivery latency.

Driver corrections: diskutil plist uses MountPoint rather than a Mounted Boolean; first attempt
stopped before changing the disk and was corrected. Relaunch originally expected an empty persisted
queue, but completed records remain on disk; corrected the assertion to compare exact records/IDs,
ledger bytes and output counts/hashes. Neither issue is an app failure. The unmount refusal is
retained as an explicitly labeled transcription from the tool response, not redirected raw stderr.

Fresh-context `e1_review` independently reviewed scripts, actions and UI evidence. It confirmed
the mount/recovery claims and required keeping the active-read loss and physical cable claims open.
Final audit verified all 24 curated hashes, identical before/after persisted queues, alternate-path
source URLs and restoration records; no blocking evidence finding remained.

## Remaining boundary

E1 remains unchecked: abrupt physical loss during active discovery has not been accepted.
Perform that scenario on disposable media where interrupting the device is appropriate; do not
force-unmount this populated drive to manufacture a pass. Independent controlled late-result
rejection already passed, but does not substitute for the missing device scenario. E2 source
inclusion is still pending; E3 signed-artifact/upgrade checks remain gated. No commit, merge, push,
package or release in this run.
