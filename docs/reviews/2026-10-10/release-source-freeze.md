# 1.0.6 source freeze — 2026-10-10

**E2 complete.** User approved step 1, the reviewed eight-file release scope. All eight source/test
paths in `release-source-candidate.json` were included unchanged in local commit `c6a1b23d5ba03c322ab2fcbdf824cdc8c767e581`
on `fix/queued-output-reservations`. No merge or push.

## Verification

- Rechecked all 170 source files and seven build inputs against the reviewed candidate: no drift.
- Reviewed current diffs; staged exactly the eight approved paths, including both new test files.
- Verified staged blob hashes before commit and all 170 committed source blobs afterward.
- Commit changes exactly those eight paths. Application/source working tree is clean; existing
  documentation, historical reviews, evidence and session changes remain outside this source commit.
- Reused full-suite 721/0 and final focused 64/0 evidence for identical source. No fresh test/build
  claimed or needed solely for this freeze. Live evidence remains in the E1 reports.
- `release-source-freeze.json` records source commit/tree, all source hashes, ignored build-input
  hashes, package pins, tested Debug artifact and prior review/patch provenance. Historical candidate
  manifest and patch retained unchanged. Verify ignored inputs again when building E3.

## Included behavior and release-note basis

The eight paths finalize latest-request-only scans, recordings search/Find, and Apply of a new output
destination to pending jobs restored from the queue. They join the existing queue recovery,
watch discovery/history and output-collision repairs already committed on this branch.

The draft release notes in `release-source-review.md` now describe the approved source scope.
They remain a draft until exact release-artifact acceptance. Active-read device-loss testing is
explicitly deferred to 1.1 by the user, not recorded as a pass for 1.0.6.

## Next boundary

E1 accepted for revised 1.0.6 scope and E2 complete. E3 remains: newly build/sign/notarize, test
clean installation and the 1.0.5 upgrade path, and smoke-test the exact signed artifact. This source
freeze did not authorize packaging, merge, push or public deployment. No app replacement was needed;
the previously restored normal Debug build remains the user artifact. Public release remains 1.0.5.
