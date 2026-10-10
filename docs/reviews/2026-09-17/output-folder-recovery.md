# Output-folder recovery

User reported a minute-long freeze around enqueueing, then another on clicking Output → Choose
in installed Conjoyn 1.0.5 (105), macOS 27.0 (26A5425a).

- Live five-second sample: main thread waiting in `NSSavePanel._initBridgeAndStuff` during
  `NSOpenPanel` initialization. See `picker-hang-sample.txt`.
- System logs: picker initialization at 14:23:53, assertion/bridge initialization exception at
  14:24:53, reported HID response delay 60.02 seconds. Another matching timeout at 14:17:38–14:18:38.
  This locates the picker stall but does not establish its underlying cause or prove that all
  earlier enqueue delay had the same cause. Picker timeout remains unresolved.
- Queue inspection: 20 pending jobs, 25 present source segments (~112 GB), distinct absent output
  paths, no source overlap or existing sidecar conflicts; automatic original deletion disabled.
- After user force-quit/relaunch, queue restored. Choosing `MECK26/H11` updated the selector but
  offered no Apply prompt; jobs retained `MECK -H11-1` destinations.

## Fix

The prompt compared the selection against the previous session-only output URL. That URL is nil
after relaunch; `directoriesDiffer(nil, url)` deliberately returns false. Compare the selected
folder with pending jobs' destinations instead. Reselecting a previously kept folder also offers
Apply again. Preserve the existing 400 ms panel-teardown delay and explicit Apply semantics.

`acceptOutputFolder` handles accepted picker results; cancellation still exits before changing state.
Three new regression tests cover restored jobs through Apply and persistence, reselection, and
matching pending/finished-job exclusions. Focused queue/persistence suite: **83 tests, 0 failures**.
`git diff --check` passed. Full suite and live picker interaction not run at this point.
Existing unrelated dirty changes were preserved. Output publication safety sprint remains incomplete.

Fresh Debug build succeeded at `01_Project/build/Review-DD/Build/Products/Debug/Conjoyn.app`.
Gracefully quit the installed app, confirmed it exited, launched this artifact and verified its
running executable path. All 20 jobs were pending before handoff; queue backup retained at
`/private/tmp/conjoyn-queue-before-output-fix.json`. User live check: Choose `MECK26/H11`, Apply,
confirm destination-mismatch warnings clear before Start. Picker-timeout fix is not claimed.

User subsequently confirmed the destination/Apply flow worked and then reported the export
completed successfully. This closes the user acceptance check for the missing Apply prompt.
It does not establish byte-level output verification, resolve the intermittent picker timeout,
or replace the remaining safety sprint's collision and unavailable-destination checks.
