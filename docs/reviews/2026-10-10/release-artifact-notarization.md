# E3 notarization and final package — 2026-10-10

**App and DMG accepted by Apple, stapled and Gatekeeper-verified. E3 remains incomplete.**
User explicitly approved the app/DMG notarization uploads. Public release remains 1.0.5;
no public deployment, merge or push. Source remains frozen at c6a1b23.

## Completed evidence

- Verified the prepared ZIP/app against the reviewed manifest before submission.
- App submission `99c1f515-743c-41ec-9571-ad0a78d2b6e8`: Accepted, statusCode0, no issues.
  Stapled/validated the exact exported app; Gatekeeper reports Notarized Developer ID.
- Rebuilt DMG from that stapled app using the existing layout/signing recipe and new staging paths.
  No stale export reuse or source rebuild. Pre-notary files remain retained separately.
- DMG submission `94e1742d-6917-43ae-a823-15069377b3ca`: Accepted, statusCode0, no issues.
  Stapled/validated final DMG; Gatekeeper reports Notarized Developer ID.
- Mounted final DMG read-only: version1.0.6/build106, original bundle ID, file hashes and symlinks
  match the exported app including its ticket. Deep/strict signature, stapler validation and
  Gatekeeper acceptance passed for the contained app; Applications link correct; mount detached.
- Contained ffprobe inspected and ffmpeg decoded an existing disposable media fixture successfully.
  This is packaged-helper execution, not app-level scan/watch/queue/publication acceptance.
- All170 source files and seven frozen build inputs still match. Full721/0 and focused64/0 reused;
  no source changes or new suite run. Stapling added Contents/CodeResources; prior app files unchanged.
- Independently verified retained1.0.5 DMG length/Ed25519 signature with the shipped public key;
  extracted app deep/strict signature passed, version1.0.5/build105, embedded Sparkle2.9.3.
  The old app was not launched. Its disposable extracted copy is ready for later upgrade testing.
- Graceful exact-app relaunch after notarization: PID55387 exited, PID60407 launched and running
  executable path independently verified at `01_Project/build/E3-Acceptance/export/Conjoyn.app`.
  No fixture injection or production preference replacement; leave fresh app running per user policy.

## Final artifacts

Paths relative to `01_Project/build/E3-Acceptance/`:

| Artifact | Bytes | SHA256 |
|---|---:|---|
| `Conjoyn-1.0.6.dmg` | 29722779 | `668b8dd2005c91d6983fc7d21043a2d7138ee9aa9441fa756f3d6e65c6c4c4a1` |
| `Conjoyn-1.0.6.zip` | 29763619 | `a0270c3c62855285e536ec5a5e75d926475531bab99a5597519b84f905e130a0` |

Submission hashes differ from final files because tickets were stapled afterward; retain both Apple
logs and final manifest. Prior `04_Exports` and public appcast are unchanged. Final candidate DMG and
release notes are staged in the isolated `build/E3-Acceptance/appcast` directory.

## Remaining gates

### Signed feed and deltas: subsequently resolved

User approved the backup key; feed and delta validation passed. See
[feed verification](release-feed-verification.md). The original blocker history follows.

Local generate_appcast with account conjoyn failed: keychain entry not found, OSStatus-25300. No
signed106 entry or106 deltas were produced. The existing staged appcast still describes older releases;
do not deploy it as a completed106 feed. Draft106 notes were staged before the generation attempt.

The established recipe supports `SPARKLE_ED_KEY_FILE` using the documented backup at
`/Users/sim/ProgrammingProjects/99-AUTH/conjoyn-sparkle-private.key`. Presence was checked without
reading its contents. Automatic approval review rejected the proposed signing command because
explicit user approval for this credential source is required. **The backup signing command never
ran; the key was not exposed or copied.** Approval of Apple artifact uploads did not satisfy that
separate automatic review condition. Ask approval to use this backup for local feed/delta signing.

On approval, rerun generate_appcast against the staged final DMG with the backup key, then validate
one build106 item, notes link, version/minimum OS, enclosure length and Ed25519 signature; validate
all emitted deltas independently and reconstruct the expected app from old105. Do not re-notarize
or rebuild the already accepted source/artifacts merely because feed signing was blocked.

### Exact-artifact GUI acceptance: no disposable environment

User answered **“No test environment available.”** Read-only search found only the regular sim
session and no common local VM installation/storage. Account enumeration was limited by sandbox;
this is not a universal claim that no remote/custom VM exists. No account/VM was created.

Clean-install, actual Sparkle1.0.5 upgrade, legacy-history migration and final app-level smoke flows
remain unperformed. Prior Debug/re-signed E1 checks are separate evidence. Neither normal launch nor
helper/delta validation can replace these checks. A disposable macOS GUI account/VM/test Mac, or an
explicitly reconsidered acceptance boundary, is still needed before declaring E3 complete. User's
lack of a test environment does not waive acceptance. Active-read device loss remains deferred to1.1.

## Independent review and handoff

Fresh-context e3_acceptance_environment inspected available environment metadata and later audited
final evidence read-only. It independently recomputed final artifact hashes/sizes, exported app hashes
and symlinks, and all177 frozen input hashes; Apple IDs/status/logs agree. No concrete discrepancy.
Mounted equality was reviewed from coordinator evidence, not independently remounted. Automatic
review rejection/nonexecution is established by tool history, not by packaging logs.

Coordinator owned signing/notary/build/appcast/launch/docs serially. No new commit: E3 incomplete,
pre-existing dirty docs/evidence preserved and frozen source HEAD unchanged. Evidence under
`e3-evidence/`, especially final-artifact.json, app/dmg-notary-log.json, final-app-* and
appcast-generate.log. No release-readiness claim. Outcome blocked/incomplete.
