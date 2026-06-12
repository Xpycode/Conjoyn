# Sparkle Auto-Update — Research Findings (pre-planning)

> **Status:** Research only (2026-06-12). **Proper planning happens next session.**
> Sourced from 3 parallel agents studying every sibling app's Sparkle setup:
> Penumbra, CropBatch, P2toMXF, the shared cookbook #16, AppUpdater, and the
> smaller live impls (DiskVerdict, QuickMotion, AspectRatioUnifier, syncthingStatus).
> No code changed; nothing decided. This doc is the raw input for the plan.

## Why this is easier than it looks

**Conjoyn is the *simplest* Sparkle case in the whole app family**, because it is
**non-sandboxed** (App Sandbox OFF, Hardened Runtime ON). Almost every hard-won scar
in the sibling apps is *sandbox-specific* and Conjoyn sidesteps it entirely:

- **No `com.apple.security.network.client`** needed — that's a sandbox-only entitlement.
- **No `SUEnableInstallerLauncherService`**, **no `…-spks`/`-spki` mach-lookup exceptions** —
  those exist only so a *sandboxed* app can reach Sparkle's spawned Installer/Downloader XPC.
- **No Sparkle-specific entitlement at all.** Conjoyn already ships
  `cs.disable-library-validation` + `allow-unsigned-executable-memory` + `allow-jit`
  for FFmpeg — and `disable-library-validation` is *exactly* what lets Sparkle load its
  Sparkle-team-signed XPC services. The FFmpeg entitlements double as the Sparkle enabler.

**Net:** adding Sparkle to Conjoyn needs **no new entitlement and no new build setting.**

## Closest references (in priority order)

1. **P2toMXF** (`_Published/P2toMXF/`) — Conjoyn's literal port ancestor. Same FFmpeg/dylib/
   non-sandbox/hardened-runtime profile. Its `UpdaterController.swift` + `FileMenuCommands`
   menu pattern are **copy-verbatim** candidates. ⚠ But P2toMXF **never finished** —
   its `SUPublicEDKey` is still the placeholder `PENDING_GENERATE_KEYS_STEP`. Don't copy that.
2. **Penumbra** (`Penumbra/`) — same vendor (`lucesumbrarum`), **self-hosted appcast on
   `*.lucesumbrarum.com`**, bundled ffmpeg/ffprobe, has a full **`docs/sparkle-release-runbook.md`**
   + `docs/PLAN-Sparkle.md`. Penumbra *is* sandboxed, so strip its sandbox/XPC layer; keep the
   notarize→staple→sign release dance, which applies 1:1.
3. **DiskVerdict** (`DiskVerdict/01_Project/DiskVerdict/App/Updater.swift`) — cleanest minimal
   controller template, best inline comments, non-sandboxed like Conjoyn.
4. **Cookbook #16** (`StatsWindow/docs/cookbook/16-sparkle-auto-updates.md`) — the canonical
   house pattern (byte-identical across StatsWindow/MenuBarPLUS/AutoRedact/DiskVerdict).

`AppUpdater/` is **NOT relevant** — it's a standalone MacUpdater-replacement app that *reads
other apps'* feeds, the opposite side of the relationship.

## The reusable shape

### SPM dependency (xcodegen translation)
Siblings add Sparkle through the Xcode GUI (pbxproj). Conjoyn is xcodegen-driven, so the
equivalent goes in `project.yml`:
```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: 2.8.1            # use latest 2.x; upToNextMajor. (Penumbra: 2.9.3; CropBatch/P2toMXF: 2.8.1)
targets:
  Conjoyn:
    dependencies:
      - package: Sparkle
```
SPM auto-embeds `Sparkle.framework` incl. nested `Installer.xpc`/`Downloader.xpc`/`Autoupdate`/
`Updater.app` — **no manual embed/run-script phase.** Re-run `xcodegen` after adding.

### Info.plist keys (3 of them, base plist not INFOPLIST_KEY_)
```xml
<key>SUFeedURL</key>            <string>https://conjoyn.lucesumbrarum.com/appcast.xml</string>
<key>SUPublicEDKey</key>        <string>__GENERATE_FRESH__</string>
<key>SUEnableAutomaticChecks</key> <true/>
```
- **⚠ `INFOPLIST_KEY_` trap:** with `GENERATE_INFOPLIST_FILE=YES`, custom `SU*` keys are
  **silently dropped** (not on Apple's allowlist) → runtime "You must specify the URL of the
  appcast" error. Conjoyn already hit this class of bug with `UIDesignRequiresCompatibility`
  (cookbook #89): the fix is a **base Info.plist** that Xcode merges generated keys onto.
  Conjoyn already has that base Info.plist — add the `SU*` keys there.
- Omit `SUEnableInstallerLauncherService` (sandbox-only). Leave `SUScheduledCheckInterval`
  unset → Sparkle default (~daily).

### Controller + menu (Swift)
Copy `UpdaterController.swift` (P2toMXF or DiskVerdict). Key points:
- `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)`
  as a stored property on the `@main App`.
- Needs `import Combine` (for `@Published`/`.assign(to:)`) — Penumbra's one build fix.
- Wire "Check for Updates…" via `CommandGroup(after: .appInfo)`.
- **Prefer P2toMXF's `FileMenuCommands` `Commands`-struct + `@StateObject` pattern** over an
  inline `CommandGroup` closure — the closure doesn't reliably observe the ObservableObject,
  so the disabled-state binding can go stale. (Documented in P2toMXF's own code comment.)

## The landmines (every one actually hit by a sibling)

1. **EdDSA private-key loss = users can NEVER auto-update again.** Happened for real
   (SyncthingStatus v1.5→v1.5.1). **Generate a fresh Conjoyn key** (blast-radius isolation;
   Penumbra used `--account penumbra`). Use `--account conjoyn` and **bake `--account conjoyn`
   into every `sign_update`/`generate_appcast` call** or it looks up a nonexistent default key.
   Back the private key up to **two** out-of-repo locations (e.g. `99-AUTH/`) *before* the first
   signed release. Keychain doesn't sync across Macs (same lesson as the `conjoyn-notary` profile).
2. **`codesign --deep` is forbidden** — it mis-signs Sparkle's XPC → "Failed to gain authorization."
   Use **Archive → Export (developer-id)**, which re-signs nested XPC + Sparkle.framework +
   ffmpeg/ffprobe correctly and preserves Hardened Runtime. Conjoyn's existing
   `notarize.sh`/`make-dmg.sh` already avoid `--deep` — confirm the Sparkle nested binaries get
   covered (the sign script should **leave Sparkle.framework alone**, only re-sign ffmpeg/ffprobe).
3. **Notarization inspects every nested Mach-O.** Adding Sparkle adds `Autoupdate`, `Updater.app`,
   `Installer.xpc`, `Downloader.xpc`, `Sparkle.framework` — each must be Developer-ID + `-o runtime`.
   Verify with `codesign -dv --verbose=4` (Authority=Developer ID Application, flags=0x10000(runtime))
   alongside the existing ffmpeg/ffprobe checks.
4. **Staple the `.app` BEFORE packaging** — the ticket is written into the bundle; zip/DMG first
   and the ticket isn't inside. (Conjoyn's `make-dmg.sh` already staples the app — verify ordering.)
5. **`sparkle:version` must equal `CFBundleVersion`, be a monotonic integer, never reused.**
   Sparkle compares ONLY `sparkle:version`; the marketing string is cosmetic. CropBatch shipped a
   downgrade loop from a non-monotonic build number. **Check Conjoyn's `CURRENT_PROJECT_VERSION` is
   a clean monotonic integer before the first Sparkle release.**
6. **Enclosure `length` must be the EXACT byte count** (`stat -f%z`) or EdDSA verification fails.
   Serve appcast as `application/xml`; serve the DMG/zip with **no gzip / CDN recompression**
   (recompression changes the bytes → signature breaks). Verify post-upload with `curl -sI`.
7. **First version can't test itself** — there's nothing to update *from*. Do a throwaway
   build-999 → build-1000 self-update test over a local HTTPS staging feed (mkcert CA so ATS
   accepts it; self-signed HTTP false-negatives) **before** the first public appcast.
   Sparkle reads a `SUFeedURL` user-default *before* Info.plist — handy for staging
   (`defaults write com.lucesumbrarum.conjoyn SUFeedURL …`), but `defaults delete` it after.

## Hosting (Conjoyn = self-host, like Penumbra)

- `SUFeedURL` → `https://conjoyn.lucesumbrarum.com/appcast.xml` (or an `apps.lucesumbrarum.com/conjoyn/`
  path — TBD next session). Enclosure URL → the DMG at the same host.
- Strato webspace gotchas (`DiskVerdict/docs/29_web-strato-hosting.md`): deploy with
  `lftp mirror -R` **without `--delete`** (protects the PHP download-counter's flat-file state);
  `chmod 644`/`755` before mirroring (macOS sets 0600 → Apache 403); bind the subdomain to its
  docroot in the control panel first; no PHP `SetHandler` (Strato is FastCGI).
- **Point Sparkle's enclosure `url` at the RAW DMG path, not the counted/302-redirect PHP endpoint** —
  let the website's download *button* use the counter; keep Sparkle on the direct file URL to avoid
  content-type/length surprises and double-counting per update poll.

## Open decisions for the planning session (do NOT pre-decide)

- **Enclosure format: DMG vs ZIP.** House precedent + `generate_appcast` deltas favor **ZIP**;
  PROJECT_STATE says host **DMGs**. Sparkle supports DMG fine. Likely answer: ship the DMG for the
  website download AND a ZIP enclosure for Sparkle (or just sign+serve the DMG). Decide next session.
- **Feed URL shape** — dedicated subdomain `conjoyn.lucesumbrarum.com` vs path under a shared host.
- **Sparkle version pin** — latest 2.x (`from: 2.x`, upToNextMajor) vs match a sibling exactly.
- **`make-dmg.sh`/`notarize.sh` wiring** — where `sign_update`/`generate_appcast` slot in, and the
  nested-binary verification additions.
- **Automatic vs manual-only checks** — `SUEnableAutomaticChecks` on (first-run prompt) vs menu-only.

## Concrete files to pull from next session

| Purpose | Path |
|---|---|
| Controller (verbatim) | `_Published/P2toMXF/01_Project/P2toMXF/Services/UpdaterController.swift` |
| Cleanest controller alt + comments | `DiskVerdict/01_Project/DiskVerdict/App/Updater.swift` |
| Menu pattern (`FileMenuCommands` + `@StateObject`) | `_Published/P2toMXF/01_Project/P2toMXF/P2toMXFApp.swift` |
| Entitlements (already matches Conjoyn) | `_Published/P2toMXF/01_Project/P2toMXF/P2toMXF.entitlements` |
| Release runbook (closest profile) | `Penumbra/docs/sparkle-release-runbook.md` |
| Sparkle plan template (5-wave) | `Penumbra/docs/PLAN-Sparkle.md` |
| Per-release procedure | `_Published/P2toMXF/docs/RELEASE.md` |
| Key custody / signing | `_Published/CropBatch/05_Docs/sparkle-signing.md` |
| Canonical cookbook | `StatsWindow/docs/cookbook/16-sparkle-auto-updates.md` |
| Strato hosting gotchas | `DiskVerdict/docs/29_web-strato-hosting.md` |
| Notarization auth (shared) | `/Users/sim/ProgrammingProjects/99-AUTH/` (`AuthKey_6HTCUZ9L7L.p8`, `IssuerID.rtf`) |
