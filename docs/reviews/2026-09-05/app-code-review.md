# Conjoyn app and code review — 2026-09-05

**Verdict: needs work. Fix output ownership first; then simplify controls and state handling.** The app has a coherent source → recordings → queue workflow and substantial media-integrity coverage. Its weaknesses are at the boundaries between those stages: visible selection versus queued work, settings versus actual behavior, and persisted watch-folder state versus real files.

Review by the main agent, GPT-5.6 Sol, and GPT-5.6 Luna. This examines the current working tree, including its existing uncommitted changes, rather than assuming the historical release notes describe every current file. No application source was changed.

**Validation and scope**

- Fresh Debug build succeeded using Xcode, with ad-hoc signing. This is not a notarization or release-signing assessment.
- The current suite ran: **625 tests, zero failures**. Counts include existing integration tests; this does not establish UI coverage or a coverage percentage.
- Launched and inspected the fresh app, loaded disposable copies of the bundled GoPro seam fixtures, queued and processed four jobs, examined the accessibility tree, and captured screenshots.
- Reproduced output collisions and search/selection behavior in the running app. Inspected the loaded view and output-options popover. Accessibility findings below include direct AX observations, not a full spoken VoiceOver or keyboard traversal audit.
- Watch-folder failures, scan races, and finishing-phase cancellation are established by traced code paths; they were not reproduced with live removable drives in this review. The tiny seam fixtures are not a substitute for full camera-original footage tests.
- App source: **59 Swift files / 15,512 lines**, including comments and blanks. Tests: **45 files / 10,349 lines**. Local HelpMenu source: **10 files / 742 lines**. Size alone is not a defect.

| Priority | Finding | Evidence | Smallest useful response |
|---|---|---|---|
| Critical | R1. Queued jobs can overwrite each other's outputs | Reproduced: four completed jobs, two output files | Reserve unique destinations at enqueue; prevent replacement at final write |
| Important | R2. Three output switches do not control processing | Complete call-site search and processing trace | Remove two unimplemented options; honor the telemetry switch |
| Important | R3. Search, selection, and processing order disagree | Hidden selection reproduced; order mismatch traced | Define one batch-selection policy and preserve displayed order |
| Important | R4. An older scan can replace a newer source's results | Unowned overlapping tasks, unconditional result assignment | Own the scan task and accept results only for the current scan |
| Important | R5. Watch output selection can silently revert to source | Failed bookmark and Cancel both become `nil` | Distinguish absent, available, and unavailable output; Cancel changes nothing |
| Important | R6. Watch discovery can miss later arrivals indefinitely | No mount retry; in-flight rediscovery events discarded | Retain a pending refresh and retry unavailable roots/discovery |
| Important | R7. Watch ledger mistakes reused camera filenames for old footage | Fingerprint excludes recording identity | Use a stable recording identity, tested across separate ingests |
| Important | R8. Stop does not stop finishing work | Copy is detached and uncancellable; success replaces cancelled state | Propagate cancellation through the entire job lifecycle |
| Important | R9. Core custom controls lack accessible meaning | Live AX tree: unnamed selection buttons, shape-named actions, inert console header | Use semantic controls or supply labels, values, and actions |
| Important | R10. Failure recovery is too hidden; queue decode failure is silent | Failure tooltip, counters, and Debug-only restore error | Show actionable errors and preserve unreadable queue data |
| Minor | R11. Duplicate and ineffective state machinery adds maintenance cost | Unused verification entry points; illegal watch-state transition | Remove unused production paths after compatibility checks |
| Minor | R12. Layout and editing impose avoidable effort | 1220-point minimum; rename editor requires off/on toggle | Let options wrap/collapse and provide a direct rename editor action |

**R1 — Output ownership is the immediate blocker.**

In `01_Project/Conjoyn/Services/QueueManager+Operations.swift:19–41`, `addJob` invokes the conflict resolver only when a file already exists on disk. A destination reserved by a pending job does not trigger that branch. The existing resolver already understands queued destinations (`QueueManager.swift:394–428`), but this caller bypasses it.

`QueueManager+Processing.swift:215–220` uses the job's destination unchanged. FFmpeg receives `-y` (`FFmpegWrapper+Conversion.swift:120`); the staged-copy path also removes an existing destination (`QueueManager+Processing.swift:346–355`). Consequently, two cards with repeated camera filenames can silently replace each other's finished outputs.

Runtime reproduction: copy the two seam fixtures into separate temporary card folders; choose one empty temporary output folder; select All and enqueue both cards before starting. The queue contained four jobs, with each destination repeated twice. All four finished, while the folder contained only `GX016349_1.mp4` and `GX026349_2.mp4`. The second pair replaced the first pair. These were disposable copies of the same fixture content, so this proves destination reuse and replacement, not loss of unique user footage.

See [machine-readable evidence](collision-evidence.json), [finished queue](conjoyn-review-done.png), and [AX output](conjoyn-review-ax-done.txt). Add a regression through `addJob`, rather than testing only the conflict helper. Also protect a destination created by another process after enqueue, and reserve the companion `.SRT` path when present.

**R2 — Remove choices that do not work.**

`Views/QueuePanel.swift:128–129` exposes “Re-encode if segments mismatch” and “Delete originals after verify.” Their properties occur in the settings model and UI, with no execution consumer. Enabling either cannot deliver its advertised behavior. Removing these controls is preferable to adding two substantial features merely to justify existing switches. Retain serialized compatibility fields if older queue files require them.

“Stitch telemetry” at `QueuePanel.swift:41` is also ignored: `QueueManager+Processing.swift:331` always calls the sidecar routine, and `:493–515` checks for sidecars but never reads `job.settings.stitchSRT`. A DJI recording with sidecars gets an SRT even when the switch is off. GoPro in-container telemetry is preserved by camera-family policy independently. Honor the sidecar setting and label its scope clearly. See [options screenshot](conjoyn-review-options.png).

**R3 — Make the batch users see match the batch they operate on.**

`ConversionViewModel.swift:79–102` filters/sorts the visible groups, while `:118–140` derives selection from all groups. Search changes only the query. The All/Splits/Singles controls also replace selection; None only clears selection. Thus one segmented-looking control mixes view filtering with destructive replacement of a hand-picked batch.

Runtime: select both rows, search `GX016349`. The app shows one row, the header says “showing 1 of 2 · 2 of 2 selected,” and the action still says “Add 2 to Queue.” The count is accurate, but the hidden batch is easy to overlook. See [screenshot](conjoyn-review-search.png) and [AX evidence](conjoyn-review-ax-search.txt).

Additionally, `selectedGroups` filters discovery-order `groups`, although its comment promises display order. Queue order and rename counters (`:408–430`, `:514–527`) therefore ignore the user's sort.

Keep filtering separate from selection. Provide “Select visible” and “Clear selection”; either enqueue only the selected visible rows or explicitly identify how many selected rows are hidden. Preserve the chosen display order for enqueue and numbering. Test the full search/sort → selection → preview → enqueue chain.

**R4 — Give scanning one owner.**

`ConversionViewModel.swift:307–310` changes the source and launches an unowned task. `scan()` at `:350–394` captures the source before awaiting discovery, then writes groups and status without a generation check. The source picker remains available while Scan itself is disabled (`ContentView.swift:60–81`).

Choose slow folder A and then fast folder B. A can finish last, publishing A's recordings beneath B's source path. Enqueue then uses the current B folder/bookmark around A's clip URLs. An older completion can also clear `isScanning` while newer work continues. Store/cancel the active scan and check its identity before publishing. A Cancel Scan action and basic file-count progress would make large-card scanning more understandable; a spinner alone provides little context.

**R5 — Preserve destination intent.**

`WatchFolderEntry.swift:65–68` makes both “no output configured” and “configured bookmark failed to resolve” produce `nil`. `WatchFolderManager.swift:188–211` forwards that value, and `WatchFolderCoordinator.swift:494–505` treats it as permission to write next to the source. If a saved output bookmark cannot resolve, the row can still show the old saved output path while processing uses the source folder. Pause that entry and expose an unavailable-destination state.

A separate, deterministic UI bug exists at `Views/WatchFoldersPanel.swift:156–163`: the output picker passes its optional result straight to `setOutputFolder`. Cancel returns `nil`, and `WatchFolderManager.swift:129–140` interprets that as clearing the saved destination. Guard the picker result; offer a separate explicit action to reset the destination.

Manual source selection also defaults output to the source (`ConversionViewModel.swift:307–309`). That is not by itself proof of source-file overwrite, but it contradicts Quick Start's promise that the app never writes into the source folder (`Help/help-quick-start.md:17–19`). Prefer an explicit initial output choice and correct the documentation.

**R6 — Watch mode must recover without another lucky event.**

At launch, `ConjoynApp.swift:141–143` calls `resumeAll`. If an enabled root cannot resolve, `WatchFolderManager.swift:156–165` leaves it idle with no coordinator. There is no mount observer or periodic manager retry. Inserting the card later can leave it waiting until the user toggles the entry or relaunches.

For active roots, `WatchFolderCoordinator.swift:307–320` drops a rediscovery request while discovery is running. Timer passes explicitly use `rediscover: false` (`:269–275`) and only examine cached groups. An event received during discovery—or a discovery timeout with no subsequent filesystem event—therefore has no guaranteed retry. Keep a pending-discovery flag and run one trailing refresh; retry timed-out discovery and unavailable roots. Test an arrival during discovery, a timeout with an otherwise quiet folder, and a mount after launch.

**R7 — A filename is not a recording identity.**

`Models/ProcessedGroupLedger.swift:77–96` hashes only each clip's stem, index, and variant suffix. `Services/WatchFolderReconciler.swift:91–95` suppresses matching fingerprints. A later recording that reuses the same legacy DJI names and chapter shape within the same watched ingest entry looks permanently processed. Hashing these fields with SHA-256 does not add the missing identity information.

Define a stable identity that distinguishes later footage while remaining repeatable across rescans and relaunches. Include camera family and dependable recording/file identity signals; do not use a freshly generated UUID. Test two separate ingests with identical filenames and different source media.

**R8 — Cancellation must cover copying and verification.**

`QueueManager+Operations.swift:162–183` stops FFmpeg and marks jobs cancelled, but the multi-GB finishing copy (`QueueManager+Processing.swift:346–386`) runs in a detached task without cancellation checks. SRT work is also outside that cancellation path. The success assignment at `:145–153` subsequently changes the cancelled job to completed. During auto-verification, Stop likewise does not invoke the verifier's cancellation path.

Own the processing task and propagate cancellation through joining, moving, sidecars, and verification. Guard the final status update. If a stage must finish safely, label that behavior explicitly instead of presenting an immediately effective Stop. Keep queue cancellation separate from whether a completed output should be retained.

**R9 — Restore control semantics.**

`Views/DesignControls.swift:265–285` draws recording checkboxes as buttons without labels or selected values. In the running app, these appear as unnamed `AXButton` elements, not meaningful checked/unchecked controls. The options gear is “Gear Shape”; Help is “Question Mark In A Circle”; Finder reveal is “Search.” Tooltips do not supply the needed primary labels in the observed tree.

The Console header is a tap gesture (`Views/QueuePanel.swift:824–850`), and the observed AX tree exposes its text/image without a disclosure action. This makes a documented troubleshooting surface hard to reach through assistive technology. Add semantic labels/state and use a real disclosure control. Retain the visual design where possible; native controls or accessibility representations can eliminate custom behavior code.

This recommendation follows Apple's guidance on describing custom controls through purpose, values, traits, and actions: [Refine accessibility for custom controls](https://developer.apple.com/videos/play/wwdc2026/220/). Apple's Mac-specific session also explains grouping related elements so users can navigate dense interfaces efficiently: [Make your Mac app more accessible to everyone](https://developer.apple.com/videos/play/wwdc2025/229/).

**R10 — Put failures where users can act on them.**

Join failure detail is primarily a row tooltip (`Views/QueuePanel.swift:339–340`, `:380–383`). Unreadable scan files appear as a count (`Views/RecordingsList.swift:118–126`), with no file/reason disclosure. A scan in which every plausible clip fails parsing can return to an empty view saying no segments were found (`ConversionViewModel.swift:375–388`), concealing the distinction between no media and unreadable media. Use a short visible explanation with Retry, Choose Folder, or Show Details as appropriate.

Queue loading has a more concrete recovery defect: `Services/QueueManager.swift:305–309` catches decoding/read failure and only prints in Debug. The queue stays empty; a later save can replace the unreadable file. Surface `persistenceError` and retain/quarantine the original file before accepting a replacement. This is a missing recovery path, not evidence that today's compatibility fixtures fail—they passed.

**R11 — Simplify state and unused paths before splitting files.**

The persisted watch state machine does not track production progress. `WatchFolderCoordinator.swift:453–455` tries `discovered → joining`, which `WatchGroupState.swift:47–66` forbids; the fallback retains `discovered`. There are no other production lifecycle transitions, and the coordinator's `resume()` has no production caller. Remove the ineffective state layer, or derive its status from the actual queue lifecycle if it has a demonstrated purpose.

The older verification APIs (`QueueManager+Verification.swift:23–105`) have no callers in the app UI. They retain the separate 792-line `VerificationService` alongside the active 811-line `SourceTargetVerifier`. Tests and historical Codable types may still depend on legacy pieces, so first distinguish runtime requirements, test-only helpers, and serialization compatibility. Retire unused runtime orchestration rather than adding another verification abstraction.

`QueuePanel.swift` is 1,026 lines and includes options, queue rows, timecode editing, console, and footer. Extracting those already distinct views could help navigation, but merely distributing the same competing state across more files would not simplify behavior. Prioritize one destination reservation policy, one batch-selection policy, and one owned job lifecycle.

**R12 — Reduce layout and editing friction.**

`ContentView.swift:50` enforces a minimum width of 1,220 points because the output bar keeps four switches and long labels on one line. This limits side-by-side use with Finder and leaves advanced decisions visible before users load anything. Keep destination and the primary action visible; let secondary options wrap or open in a compact panel. This is a design recommendation, not a claim of clipping reproduced on a particular display.

The rename editor opens only when renaming changes to on (`Views/QueuePanel.swift:43–51`). After clicking away, reopening requires switching renaming off and on. Provide a direct edit action with a compact pattern/output preview. Consolidate the separate filename, folder-name, and template controls into one understandable naming policy.

Additional low-cost clarity work: `Help/help-shortcuts.md:5–7` advertises Cmd+R and Cmd+, without corresponding Scan/Preferences commands, and omits working Cmd+O/Cmd+F. Add accurate shortcuts or correct the page. The Help manifest lacks a Watch Folders topic. Invalid file drops are accepted then silently ignored (`Views/RecordingsList.swift:503–510`); reject unsupported input visibly.

Apple's [progress indicator guidance](https://developer.apple.com/design/human-interface-guidelines/progress-indicators?changes=_4_6) supports informative progress descriptions and cancellation when feasible. Applied here, useful additions are a cancellable scan and truthful finishing behavior, not more status badges.

**Recommended implementation order**

1. Close output collisions and watch-destination mistakes with boundary-level regression tests.
2. Remove nonfunctional options; fix telemetry behavior, selection/order, and scan ownership.
3. Repair watch identity/retry and job cancellation; expose actionable failures.
4. Restore accessible semantics, simplify the output/naming UI, and retire unused state paths.

Preserve the camera-specific grouping guards, source identity checks, queue compatibility tests, and source-to-output verification. Those represent useful domain complexity. The goal is to reduce the number of rules a user or maintainer must remember around that engine.

Fresh app: `01_Project/build/Review-DD/Build/Products/Debug/Conjoyn.app`. Test results: `01_Project/build/review-2026-09-05.xcresult`. Full build/test logs are local temporary artifacts at `/tmp/conjoyn-review-build.log` and `/tmp/conjoyn-review-tests.log`.
