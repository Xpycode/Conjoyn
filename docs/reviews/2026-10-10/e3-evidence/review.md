# Independent E3 preparation review

Read-only fresh-context reviewer: `e3_review`, 2026-10-10. No source edits or build/sign/notary commands.

- Local archive/export, signature and helper checks are useful preparation; they do not complete E3.
- Record Developer ID team, secure timestamps, entitlements, nested signatures, architectures,
  version/build, source commit and hashes. Recheck frozen source/build inputs after building.
- Preliminary DMG is not final: app stapling changes its payload. Rebuild the final DMG from the
  stapled app, then notarize/staple that DMG and record final checksums. No stale SKIP_APP reuse.
- Exact-artifact acceptance should use a disposable macOS VM or separate disposable user GUI
  session with original bundle ID/signatures and synthetic fixtures. HOME redirection alone did
  not establish preferences isolation in E1. Re-signing with another bundle ID cannot count.
- Clean installation and upgrade are separate checks. Manual app replacement checks migration,
  not the actual Sparkle updater.
- make-appcast.sh assumes build/notarize/export and 04_Exports. Bind final metadata to the actual
  app inside the final DMG; validate the single 106 item and each emitted delta separately.
- E3 stays open pending notarization, stapling and exact-artifact smoke/update acceptance.
  Automatic review requires explicit user approval for the Apple artifact uploads.
