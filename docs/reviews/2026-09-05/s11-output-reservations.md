# S1.1 — Queued output reservations

Completed 2026-09-05. Scope: the shared `QueueManager.addJob` enqueue path only.

Every enqueue now runs the existing filename resolver, including when the destination is absent.
Queued destinations and recorded actual outputs use standardized, symlink-resolved,
case-insensitive path comparison, consistent with the app's conservative naming policy.
Renaming mutates only the copied job's destination, preserving identity, overrides and directory
bookmarks. Source filesystem identities are still captured before append/persistence.

## Verification

Four new caller-level regressions cover distinct source files sharing an absent destination,
case-equivalent queued names, occupied numbered names mixed with queued names, and a directory
occupying the requested output path. The distinct-source test also checks job identity, bookmarks,
source identity capture and destination/clip persistence. All tests use disposable storage.

- Before fix: **80 tests, 4 failures**, exactly the four new regressions (Xcode exit 65).
- After fix: **80 tests, 0 failures**, QueueManagerTests (62) + QueuePersistenceCompatTests (18).
- Results: `01_Project/build/s11-red.xcresult`, `01_Project/build/s11-green.xcresult`.
- Logs: `/tmp/conjoyn-s11-red.log`, `/tmp/conjoyn-s11-green.log`.
- Independent Codex subagent inspected the fix and callers; no concrete S1.1 defects found.
- `git diff --check` passed. No full-suite run, live batch reproduction or fresh user app handoff
  in this task; the test-host build is not a release validation or user launch artifact.

## Remaining safety work

R1 remains open: files created after enqueue and SRT publication require S2.1. R5 picker/destination
intent requires S1.2/S2.2; the complete live workflow and fresh app handoff remain S3.1.

## Checkout handling

Fetched canonical history and verified the three implementation/test files matched origin before
editing. Created `fix/queued-output-reservations` and aligned its history/index with fetched main
using a mixed reset, preserving all working-file bytes. Existing local UI, search and review/docs
changes remain in place. The S1.1 commit includes only its three code/test files and this evidence.
