# E3 signed update feed — 2026-10-10

**Local feed and deltas verified. E3 GUI acceptance remains open; nothing published.**
User explicitly approved the documented backup Sparkle key. This resolves the credential-source
approval gate for this workflow; do not ask again for the same source/use. The release recipe already
supports that standard fallback. No key content printed, copied into the repo, or embedded in evidence.

## Generation and validation

- generate_appcast succeeded using the documented backup; initial success signed106 without deltas.
- Prior missing-key failure had created exactly three cached skip markers for106-from103/104/105.
  Read the cached Sparkle source to identify their behavior; moved only those zero-byte markers
  into build/E3-Acceptance/failed-signing-markers, then regenerated. No broad cache deletion.
- Feed contains exactly one106 item and retained105/104 entries. Version1.0.6, minimum macOS14.0,
  arm64 requirement, release-note URL/noindex and production destination URLs verified locally.
- Three new signed deltas: Conjoyn106-105.delta, Conjoyn106-104.delta, Conjoyn106-103.delta.
- Independently verified actual bytes of **all nine** feed enclosures using CryptoKit Ed25519 and
  the public key embedded in the app; every signature and length passes, including older enclosures.
- Applied each new delta to a disposable extracted original app. All three reconstructed apps
  exactly match final1.0.6 file hashes, symlinks and permission modes. Deep/strict code signatures
  and stapled ticket validation pass. No old/reconstructed app was launched or user state touched.
- First103 patch-driver invocation lacked its destination parent and stopped before applying;
  created required parent directories and repeated successfully. This was a driver setup issue.
- Final DMG checksum unchanged:668b8dd2005c91d6983fc7d21043a2d7138ee9aa9441fa756f3d6e65c6c4c4a1.
  Final source and packaging unchanged; no new build/suite/launch required for feed generation.

## Staging and remaining boundary

Local staging: `01_Project/build/E3-Acceptance/appcast/`.
`e3-evidence/feed-verification.json` lists all13 referenced staging files with SHA256 and byte sizes:
feed, three release notes, three full DMGs and six deltas. Retained unreferenced older files are not
part of that referenced manifest. Do not deploy only the DMG/feed while omitting referenced deltas.
Prior04_Exports/public website/appcast untouched; no push/merge/deploy. Public remains1.0.5.

The sole remaining E3 acceptance boundary is the previously recorded missing disposable macOS GUI
environment: clean install, actual Sparkle105→106 installation/relaunch, legacy-history migration,
and key scan/watch/queue/publication smoke flows on the unchanged final signed app. Delta
reconstruction does not establish these GUI/data behaviors. User has no test environment; no waiver
or authorization to replace real production state inferred. Keep E3 unchecked. Active-read device
loss remains explicitly deferred to1.1.

Coordinator owned key use/generation/validation/docs serially. Independent read-only reviewer
(e3_acceptance_environment) found no feed/manifest discrepancy, checked public-key/DMG consistency,
and corroborated nine passes. It did not rerun CryptoKit or audit reconstruction; those checks were
run by the coordinator and saved separately. Evidence logs/manifests copied into e3-evidence.
No new commit while E3 incomplete; existing dirty docs/evidence and frozen source HEAD preserved.
