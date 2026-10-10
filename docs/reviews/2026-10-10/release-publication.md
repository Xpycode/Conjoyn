# Conjoyn 1.0.6 publication — 2026-10-10

## Authorization and acceptance

User explicitly requested GitHub README, download and website updates, then chose:
**“Publish 1.0.6; waive pending GUI acceptance.”**

E3 is closed by an explicit scope exception. Clean installation, actual Sparkle 1.0.5→1.0.6
installation/relaunch, legacy-history migration and final exact-artifact GUI smoke checks
were **not performed**. They are not reported as passing. Active-read physical device-loss
acceptance remains separately deferred to 1.1.

## Published artifact

- Version 1.0.6, build 106; frozen application source `c6a1b23`.
- SHA-256: `668b8dd2005c91d6983fc7d21043a2d7138ee9aa9441fa756f3d6e65c6c4c4a1`.
- Size: 29,722,779 bytes; existing notarized/stapled DMG reused unchanged; no rebuild.
- Prior evidence: full 721/0 tests, focused 64/0, nine feed signatures, three delta reconstructions.
  Those successful checks were not rerun; current publication checked all staged file hashes.
- Download: https://conjoyn.lucesumbrarum.com/dl.php?app=conjoyn
- Feed: https://conjoyn.lucesumbrarum.com/appcast.xml
- Release notes and changelog published; homepage updated for 1.0.6 and recordings search.
- Assets uploaded before activating the feed. All 13 feed/asset files, the direct download,
  the download redirect route, homepage and changelog verified over HTTPS using SHA-256.
- Focused SFTP stages used the existing deployment helper with atomic file replacement and
  no deletions. No counters, feedback state, unrelated sites or shared assets uploaded.
- Website source synchronized in App-Websites; catalogue update changes only Conjoyn in live JSON.
- GitHub README now covers DJI/GoPro compatibility, current download and 1.0.6 improvements.

## Evidence

`publication-https-assets.json` and `publication-https-pages.json` record downloaded hashes.
The original preparation/notarization/feed reports remain historical evidence of the prior hold;
this release decision supersedes that hold without rewriting the earlier test results.
