# Plan — Sparkle Auto-Update for Conjoyn

> **Decision locked (2026-06-12):** Conjoyn ships **only with auto-update**. The first public
> download IS the first Sparkle-enabled build. No update-less interim release.
> Built on `docs/sparkle-research.md` (3-agent recon) + this session's verification against
> P2toMXF (verbatim port source), Penumbra (release dance), and the live Sparkle **2.9.3** docs.

## Decisions confirmed this session
| Decision | Choice | Why |
|---|---|---|
| **Enclosure** | **DMG only** | One notarized DMG = website download + Sparkle enclosure. Matches existing `make-dmg.sh`. No deltas (no installed base; 27 MB app). `generate_appcast` handles DMG natively. |
| **Check policy** | **Automatic + menu** | `SUEnableAutomaticChecks=true` (daily background, prompt on new version) **plus** a manual "Check for Updates…" menu item. |
| **Version debut** | **1.0 / build 100** | Feature-complete, notarized, 330 tests. `MARKETING_VERSION=1.0`, `CURRENT_PROJECT_VERSION=100` (monotonic int, room to grow). Current binary is 0.1.0/build 1 — never publicly distributed, so this is a clean reset. |
| **Sparkle version** | **`from: 2.9.3`** (upToNextMajor) | Latest 2.x; carries 2.9.2 symlink + appcast-validation security fixes. No breaking API for a Developer-ID app. |
| **Feed host** | `https://conjoyn.lucesumbrarum.com/appcast.xml` | Self-host, Penumbra pattern. **Standup gated on the website session** (Wave 4). |

## Why this is the simplest case in the app family
Conjoyn is **non-sandboxed** (App Sandbox OFF, Hardened Runtime ON). Every sandbox-specific Sparkle
scar in the siblings is sidestepped:
- **No new entitlement.** The existing `cs.disable-library-validation` +
  `allow-unsigned-executable-memory` + `allow-jit` (for FFmpeg) are exactly what lets Sparkle load
  its team-signed XPC services. **`Conjoyn.entitlements` needs zero changes.**
- **No `SUEnableInstallerLauncherService`**, no `SUEnableDownloaderService`, no `-spks`/`-spki`
  mach-lookup exceptions, no `network.client` — all sandbox-only.
- **No new build setting** beyond the SPM dep + the 3 Info.plist keys.

---

## Open factual note carried into execution — ✅ RESOLVED 2026-06-13
**The `--account <name>` flag for key isolation IS supported** (verified against the pinned Sparkle
2.9.3 `generate_keys --help` on the M4 Pro): `--account <account>` exists, default is the global
`ed25519` account, and Sparkle explicitly recommends *"using different accounts for different
organizations."* Confirmed empirically — this Mac's keychain already held a `penumbra` account from
the sibling app. **Conjoyn's key was generated with `--account conjoyn`** for per-app isolation.
Bake `--account conjoyn` into `make-appcast.sh` consistently.

---

## Wave 1 — Local integration (no release, no secrets yet) ✅ DONE 2026-06-12 (`11958e6`)
> Executed on `feature/sparkle-update`. xcodegen clean; **BUILD SUCCEEDED** with Sparkle 2.9.3
> linked; `Sparkle.framework` auto-embedded with all 4 nested Mach-Os; built Info.plist carries
> build 100 / version 1.0 + all 3 `SU*` keys. `SUPublicEDKey` is the `__FILL_FROM_WAVE_0__`
> placeholder — **Wave 0 (key generation) is the next step.**

### 1.1 Add Sparkle via SPM (`01_Project/project.yml`)
Add under `packages:` and to the `Conjoyn` target `dependencies:`:
```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.9.3"
# …
targets:
  Conjoyn:
    dependencies:
      - package: Sparkle          # add alongside HelpMenu + swift-timecode
```
Then `cd 01_Project && xcodegen generate`. SPM auto-embeds `Sparkle.framework` (with nested
`Installer.xpc`/`Downloader.xpc`/`Autoupdate`/`Updater.app`) — **no manual embed or run-script phase.**
First resolve pulls the binary artifact into
`build/.../SourcePackages/artifacts/sparkle/Sparkle/bin/` (where the CLI tools live for Wave 0).

### 1.2 Bump the version baseline (`project.yml` → `settings.base`)
```yaml
    MARKETING_VERSION: "1.0"          # was 0.1.0
    CURRENT_PROJECT_VERSION: "100"    # was 1  — monotonic integer == sparkle:version
```

### 1.3 Info.plist keys (`01_Project/Conjoyn/Info.plist` — the BASE plist)
Add the 3 `SU*` keys **into the existing base Info.plist** (which already holds
`UIDesignRequiresCompatibility`). **Do NOT use `INFOPLIST_KEY_SU*`** — with
`GENERATE_INFOPLIST_FILE=YES`, custom `SU*` keys are silently dropped (not on Apple's allowlist) →
runtime "You must specify the URL of the appcast" (same trap class as cookbook #89). The base plist
is the correct, already-proven home.
```xml
<key>SUFeedURL</key>
<string>https://conjoyn.lucesumbrarum.com/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>__FILL_FROM_WAVE_0__</string>
<key>SUEnableAutomaticChecks</key>
<true/>
```
Omit `SUEnableInstallerLauncherService` / `SUEnableDownloaderService` (sandbox-only). Leave
`SUScheduledCheckInterval` unset → Sparkle default (~daily).

### 1.4 Controller (`01_Project/Conjoyn/Services/UpdaterController.swift` — NEW, port verbatim)
Copy P2toMXF's controller 1:1 (it has zero app-specific code):
```swift
import Foundation
import SwiftUI
import Sparkle
import Combine

/// Owns the Sparkle updater and exposes `canCheckForUpdates` for menu bindings.
@MainActor
final class UpdaterController: ObservableObject {
    let updaterController: SPUStandardUpdaterController
    @Published var canCheckForUpdates = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: \.canCheckForUpdates, on: self)
            .store(in: &cancellables)
    }

    func checkForUpdates() { updaterController.checkForUpdates(nil) }
}
```
`import Combine` is required (Penumbra's one build fix).

### 1.5 Menu wiring (`01_Project/Conjoyn/ConjoynApp.swift`)
Conjoyn already uses a `Commands` struct (`HelpMenuCommands`) — mirror that pattern (a `Commands`
struct, **not** an inline `.commands { CommandGroup(...) }` closure; the closure doesn't reliably
observe the `ObservableObject`, so the disabled-state binding goes stale — documented in P2toMXF).
```swift
@main
struct ConjoynApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = ConversionViewModel()
    @StateObject private var updaterController = UpdaterController()   // NEW
    // … helpContent unchanged …

    var body: some Scene {
        WindowGroup { /* unchanged */ }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 800)
        .commands {
            HelpMenuCommands(content: helpContent, appName: "Conjoyn")
            UpdaterCommands(updater: updaterController)               // NEW
        }
    }
}

struct UpdaterCommands: Commands {
    @ObservedObject var updater: UpdaterController
    var body: some Commands {
        CommandGroup(after: .appInfo) {                              // Conjoyn ▸ Check for Updates…
            Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
```
`.appInfo` placement doesn't collide with any existing ⌘W/`.saveItem` override. Re-run `xcodegen`
after adding the new source file so it's compiled.

**Wave 1 exit:** `xcodegen generate` clean; project compiles with Sparkle linked.

---

## Wave 0 — EdDSA keys & custody ✅ DONE 2026-06-13 (on the M4 Pro)
> Sequenced after 1.1 because the `generate_keys` binary only exists once SPM resolves Sparkle.
> This is the highest-stakes, least-reversible step: **lose this private key and no future build can
> ever be signed → every user is permanently orphaned** (happened for real: SyncthingStatus v1.5→1.5.1).
>
> **DONE:** Generated on the **M4 Pro** (the M1 Max — the prior intended release Mac — was out of
> order/being reset, and no Conjoyn key existed anywhere yet, so a fresh generation here is clean and
> makes the M4 Pro Conjoyn's key-custody Mac going forward). `generate_keys --account conjoyn` →
> **public key `Ks14npeWNt9Rd8QawQiBYQuzFq08vPe2hXgu1s5zVOE=`** (now in `Info.plist`, round-trips via
> `-p`). Private key in the M4 Pro login keychain (account `conjoyn`, does **not** sync). **Backup #1:**
> `99-AUTH/conjoyn-sparkle-private.key` (`-x` export, 44-byte base64 seed, `chmod 600`).
> **⏳ Backup #2 OWED** — user must copy it to a second out-of-repo secure location (password manager /
> external drive) before the first signed public release.

```bash
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*artifacts/sparkle/Sparkle/bin/generate_keys' 2>/dev/null | head -1 | xargs dirname)"
"$SPARKLE_BIN/generate_keys" --help          # confirm whether --account exists in THIS version
# If supported:   "$SPARKLE_BIN/generate_keys" --account conjoyn
# Else (default):  "$SPARKLE_BIN/generate_keys"
# → prints the base64 PUBLIC key, stores the PRIVATE key in the login keychain.
```
1. Paste the printed public key into `SUPublicEDKey` (Wave 1.3).
2. **Export + back up the private key to two out-of-repo locations BEFORE any signed release:**
   ```bash
   "$SPARKLE_BIN/generate_keys" -x ~/Desktop/conjoyn-sparkle-private.key   # [--account conjoyn] if used
   # copy to BOTH: 99-AUTH/ (alongside the notary .p8) AND a second secure location
   chmod 600 ~/Desktop/conjoyn-sparkle-private.key
   ```
3. Record the public key + key location in memory (`notary-credentials-recreation` sibling note) and
   in `99-AUTH/`. Keychain does **not** sync across Macs (same lesson as the `conjoyn-notary` profile).

**Wave 0 exit:** fresh Conjoyn EdDSA key generated, public key in Info.plist, private key backed up ×2.

---

## Wave 2 — Local verification (no network, no publish)

1. **Build + full suite:** clean Debug build launches; `330 pass / 1 skip / 0 fail` still green.
2. **"Check for Updates…" smoke:** menu item present under the app menu, enabled, click shows
   Sparkle's "you're up to date" (or a network-error sheet if offline) — proves the updater starts
   and reads `SUFeedURL`/`SUPublicEDKey` (no appcast served yet).
3. **Signing/notarization audit — extend `notarize.sh` for the new nested Mach-Os.** Adding Sparkle
   adds binaries that notarization will inspect; each must be Developer-ID + `flags=0x10000(runtime)`.
   Add to the verify loop in `notarize.sh` (currently only ffmpeg/ffprobe):
   ```
   Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate
   Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater
   Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer
   Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader
   ```
   Verify each with `codesign -dv --verbose=4` (Authority=Developer ID Application, runtime flag).
   - **`sign-bundled-binaries.sh` must NOT touch `Sparkle.framework`** — it signs only the Helpers
     dir; xcodebuild re-signs the embedded framework. Confirm its scope.
   - **`codesign --deep` on *signing* is forbidden** (mis-signs Sparkle's XPC →
     "Failed to gain authorization"). `notarize.sh` only uses `--deep` on `--verify` (safe); the
     real signing is xcodebuild's inside-out pass. **Risk gate:** if a direct
     `xcodebuild build` doesn't correctly re-sign the nested XPC with hardened runtime, fall back to
     Penumbra's **Archive → Export (developer-id)** path (an `exportOptions.plist` with
     `method=developer-id`). Decide by the `codesign -dv` audit above, not by assumption.
4. **Monotonic version check:** confirm `CFBundleVersion` of the Release build == `100`.

**Wave 2 exit:** Release build signs + notarizes with all Sparkle nested binaries hardened; menu works.

---

## Wave 3 — Release pipeline + self-update dry run (local HTTPS, no public host)

### 3.1 New `01_Project/scripts/make-appcast.sh`
Runs **after** `make-dmg.sh` has produced the stapled, notarized `04_Exports/Conjoyn.dmg`. It:
1. Stages the DMG into an `updates/` folder.
2. Locates `generate_appcast` in DerivedData (path is volatile — `find … | head -1`).
3. Runs `generate_appcast` (with `--account conjoyn` iff Wave 0 confirmed it) over `updates/`,
   passing `--download-url-prefix https://conjoyn.lucesumbrarum.com/`. This **auto-signs** the DMG
   with EdDSA and **auto-computes the exact `length`** — never hand-edit those.
4. Hand-verifies the generated `<item>`: `sparkle:version` == 100, `shortVersionString` == 1.0,
   `<enclosure length>` == `stat -f%z Conjoyn.dmg`, non-empty `sparkle:edSignature`,
   `<sparkle:minimumSystemVersion>14.0.0`. `xmllint --noout appcast.xml`.

Expected appcast shape:
```xml
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Conjoyn Changelog</title>
    <item>
      <title>Version 1.0</title>
      <sparkle:version>100</sparkle:version>
      <sparkle:shortVersionString>1.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
      <description><![CDATA[ … release notes … ]]></description>
      <enclosure url="https://conjoyn.lucesumbrarum.com/Conjoyn-1.0.dmg"
                 sparkle:edSignature="…" length="26882684" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

### 3.2 100 → 101 self-update test (BEFORE any public appcast)
A first release can't test itself (nothing to update *from*). Prove the mechanism with a throwaway:
1. Build a "new" build `101` DMG; `generate_appcast` an appcast advertising 101.
2. Serve `appcast.xml` + the 101 DMG over **local HTTPS** (mkcert CA so ATS accepts it; plain HTTP or
   self-signed gives false negatives). Sparkle reads a `SUFeedURL` *user-default* before Info.plist:
   ```bash
   defaults write com.lucesumbrarum.conjoyn SUFeedURL https://localhost:8443/appcast.xml
   ```
3. Install the **build-100** app to `/Applications`, launch, **Check for Updates…** → it should offer
   101 → install → relaunch. Prove it:
   ```bash
   /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Applications/Conjoyn.app/Contents/Info.plist  # → 101
   ```
4. Cleanup: `defaults delete com.lucesumbrarum.conjoyn SUFeedURL`, stop the server, discard staging.

**Wave 3 exit:** an app can fetch a signed appcast, verify the EdDSA signature, download the DMG,
and swap itself in place — confirmed by the version bump.

---

## Wave 4 — Production publish (gated on the website session)
> Blocked on web tier (conjoyn site not live yet). Do this as part of, or right after, the website work.

1. Stand up `conjoyn.lucesumbrarum.com` (or a `/conjoyn/` path on a shared host — final shape TBD).
2. Deploy `appcast.xml` + `Conjoyn-1.0.dmg` (Strato gotchas, per `DiskVerdict/docs/29_web-strato-hosting.md`):
   - `lftp mirror -R` **without `--delete`** (protects the PHP download-counter's flat-file state).
   - `chmod 644`/`755` before mirroring (macOS sets 0600 → Apache 403).
   - Bind the subdomain to its docroot in the control panel first; Strato is FastCGI (no PHP `SetHandler`).
3. **Point Sparkle's enclosure `url` at the RAW DMG path, not the counted/302-redirect PHP endpoint** —
   let the website *button* use the counter; Sparkle stays on the direct file URL (avoids
   content-type/length surprises + double-counting per poll).
4. Post-upload verification (signature breaks on any byte change):
   ```bash
   curl -sI https://conjoyn.lucesumbrarum.com/appcast.xml      # 200, Content-Type: application/xml
   curl -sI https://conjoyn.lucesumbrarum.com/Conjoyn-1.0.dmg  # Content-Length == signed length, NO gzip
   ```
5. Real-world test: install the public 1.0 DMG on a clean Mac, confirm "you're up to date"; later cut
   1.0.1/build 101 to confirm a live update end-to-end.

**Wave 4 exit:** the public 1.0 DMG (Sparkle-enabled) is downloadable, the appcast is live, and a real
client updates itself. Only now is the download link published.

---

## Per-release procedure (after this plan lands — the steady state)
1. Bump `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` (strictly-increasing integer) in `project.yml`; `xcodegen generate`.
2. `make-dmg.sh` → notarized + stapled `Conjoyn.dmg` (app nested-binary audit passes).
3. `make-appcast.sh` → regenerates `appcast.xml` (EdDSA-signed, exact length) including the new item.
4. Deploy DMG + appcast (mirror without `--delete`); `curl -sI` verify length/type.
5. Tag the release in git.

## Risk register
| # | Risk | Guard |
|---|---|---|
| R1 | EdDSA private-key loss → users orphaned forever | Fresh key, `-x` export, **2× backup before first signed release** |
| R2 | `codesign --deep` mis-signs Sparkle XPC | Never `--deep` on *sign*; xcodebuild inside-out / Archive→Export fallback |
| R3 | Notarization rejects a nested Sparkle Mach-O | Per-binary `codesign -dv` audit added to `notarize.sh` |
| R4 | Host gzip/CDN recompression breaks signature | `generate_appcast` exact length; `curl -sI` post-upload; raw DMG URL |
| R5 | Non-monotonic `sparkle:version` (downgrade loop) | `CURRENT_PROJECT_VERSION` = clean monotonic int (100, then 101…) |
| R6 | `SU*` keys dropped by `INFOPLIST_KEY_*` | Keys live in the **base Info.plist** (cookbook #89 lesson) |
| R7 | First release can't self-test | 100→101 local-HTTPS dry run before public appcast (Wave 3.2) |

## Concrete source files to pull from
| Purpose | Path |
|---|---|
| Controller (verbatim) | `_reference/P2toMXF/01_Project/P2toMXF/Services/UpdaterController.swift` |
| Menu `Commands`-struct pattern | `_reference/P2toMXF/01_Project/P2toMXF/P2toMXFApp.swift` |
| Release dance (ordering, commands) | `Penumbra/docs/sparkle-release-runbook.md` |
| Strato hosting gotchas | `DiskVerdict/docs/29_web-strato-hosting.md` |
| Notary auth (shared) | `99-AUTH/` (`AuthKey_6HTCUZ9L7L.p8`, `IssuerID.rtf`) |
