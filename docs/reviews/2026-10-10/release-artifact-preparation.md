# E3 local release preparation — 2026-10-10

**Historical pre-notary preparation.** User subsequently approved uploads; app/DMG notarization
completed. Current status: [notarization and remaining gates](release-artifact-notarization.md).

Original boundary: local signed candidate prepared; Apple submission required explicit approval.
No notarization, stapling, Gatekeeper release acceptance, clean-install, upgrade or Sparkle update
pass is claimed. Public release remains 1.0.5. No merge, push, deployment or application-source edits.

## Authorization boundary

User requested “next please” after the E3 status handoff. The coordinator continued local release
preparation. Automatic approval review rejected `make-dmg.sh` because it uploads application artifacts
to Apple and required explicit approval for that payload egress. The rejected script did not run.
Only separately approved local archive/export/packaging and read-only notary credential preflight
ran. No artifact was submitted. Explicit approval is needed to submit the concrete app ZIP and the
DMG subsequently rebuilt from the stapled app to Apple's notarization service.

## Build and provenance

- Frozen source commit: `c6a1b23d5ba03c322ab2fcbdf824cdc8c767e581`.
- All 170 source hashes and seven build inputs match `release-source-freeze.json`, before and after
  archive/export. Existing package pins retained; automatic package resolution disabled.
- Fresh clean Release archive and Developer-ID export succeeded at
  `01_Project/build/E3-Acceptance/Conjoyn.xcarchive` and `export/Conjoyn.app`.
- Archive used the existing scheme/project, isolated derived data, existing package cache, manual
  Developer-ID archive signing and the recipe's developer-id export options. No project regeneration.
- Version **1.0.6**, build **106**, original bundle ID, arm64 executable. Eight app/helper/Sparkle
  components verify as Developer ID, team FDMSRXXN73, hardened runtime and secure timestamps.
- Deep/strict signature verification passed. Both packaged ffmpeg and ffprobe execute `-version`.
- App executable SHA256: `d71fd322df24f6f2d23be92775b35992094fe5fc88f2ea36c9a9280a4b16726c`.
- Archive includes existing actor-isolation warnings in RenamePopover/HelpMenu and a HelpMenu
  deprecation warning. Build passed; no source fixes were made during the freeze.
- Prior full721/0 and focused64/0 reused for unchanged source; no new test-suite run claimed.

## Local artifacts

All paths below are under `01_Project/build/E3-Acceptance/`:

| Artifact | Bytes | SHA256 |
|---|---:|---|
| `Conjoyn-1.0.6-pre-notary.zip` | 29761749 | `aca40b09d83e7b93b0be53d3114d389ad607dc223778bdbb7dfc51577a885797` |
| `Conjoyn-1.0.6-pre-notary.dmg` | 29720414 | `50d2f199e1bba36afe320554da2f7fca373a33f0852652f50f378ba6fa3a12f3` |

The local DMG follows the existing create-dmg layout and Developer-ID signing recipe, omitting all
notary submissions and stapling. Mounted read-only: app file hashes/symlinks match the export,
deep/strict signature passes, Applications link targets `/Applications`. Test mount detached.
Initial relative-path codesign calls produced a host/guest lookup error; repeating with an absolute
bundle path passed. This was a validation command issue, not a source/signature change.
Prior packaging artifacts and appcast preserved under `prior-artifacts`; `04_Exports` unchanged.

These are **pre-notary** artifacts. After app notarization/stapling, rebuild the DMG from that exact
app, notarize/staple the DMG, and record new final hashes. Do not publish the preliminary checksums
as final or silently reuse an older export via SKIP_APP.

## App handoff

Old exact Debug instance PID46197 terminated gracefully. Fresh original-identity signed export
launched as PID55387 and independently confirmed still running at:

`/Users/sim/ProgrammingProjects/1-macOS/Conjoyn/01_Project/build/E3-Acceptance/export/Conjoyn.app/Contents/MacOS/Conjoyn`

Normal app launch only; no fixture injection or production-state migration test was performed.
This launch is not a clean-install or upgrade acceptance pass. Standing user preference leaves the
fresh app running. No forced quit or production preference replacement occurred.

## Next pickup

1. Obtain explicit approval to upload the identified app ZIP and subsequently rebuilt DMG to Apple.
2. Submit the ZIP with the existing conjoyn-notary profile; on acceptance staple/validate the exported
   app and assess Gatekeeper. Rebuild DMG from that app, sign, submit, staple and assess the DMG.
3. Arrange a disposable macOS VM snapshot or separate disposable user GUI session for unchanged
   signed-artifact acceptance. HOME redirection alone did not establish preferences isolation in E1;
   changing bundle ID/helpers or re-signing a harness cannot establish exact-artifact acceptance.
4. Test clean install and actual 1.0.5 upgrade, including legacy history, scan/watch/queue/publication
   smoke flows. Manual replacement alone does not prove Sparkle updater success.
5. Stage notes before appcast; bind script metadata to the exact final app/DMG because make-appcast.sh
   hardcodes build/notarize/export. Verify one 106 item and all emitted deltas individually.
6. Complete E3 only with evidence. Public deployment remains separate. Active-read device loss is
   still deferred to 1.1, not a failed or passed 1.0.6 check.

Evidence: `e3-evidence/local-artifact.json` (bundle hashes/signatures), preflight, export, launch,
DMG logs and local driver scripts. Full archive log remains in build/E3-Acceptance/archive.log.
Fresh-context `e3_review` independently reviewed the preparation/acceptance boundaries; its findings
are in `e3-evidence/review.md`. Coordinator owned build/signing/app handoff and docs serially.
