# Camera File-Splitting Research — Multi-Brand Survey

> Exploratory research (2026-06-09) for the post-DJI multi-camera roadmap (see memory
> `multi-camera-future`, `docs/ideas.md`). Captures **why** cameras split recordings, **how** each
> brand names/orders the segments, and **what** the pluggable parser/grouper needs per family.
> Four parallel research agents + web verification; source URLs inline.

## TL;DR for the architecture

1. **One universal cause:** the **FAT32 4 GB-per-file limit** (32-bit size field → 2³²−1 bytes).
   SD ≤32 GB ship FAT32 (split at 4 GB); SD ≥64 GB ship exFAT (effectively unlimited).
2. **exFAT does NOT always stop the split** — DJI, Autel, and Canon enforce a ~4 GB firmware cap
   *even on exFAT* (crash-safety: lose one segment, not the whole flight).
3. **The 29:59 limit is a different mechanism** (a WTO tariff rule) — the camera *stops* recording,
   it does **not** make a continuation file. A clip ending near 30 min may be standalone, not a join
   set.
4. **The market splits into two families:**
   - **Filename encodes continuity — GoPro only.** `GH01**0123**` / `GH02**0123**`: trailing 4
     digits = recording ID (constant), middle 2 = chapter (increments). Groupable by name (but the
     constant part is in the *middle*, so naïve alphabetical sort scrambles chapters).
   - **Filename does NOT prove continuity — everyone else.** DJI, Osmo, Autel, Skydio, Parrot,
     HoverAir, Sony, Canon, Nikon, Panasonic, Fujifilm all just **increment a counter**. Two
     consecutive numbers may be one recording or two unrelated clips → **must group by metadata
     continuity.** This validates DJIjoiner's existing core decision.
5. **AVCHD is the one structurally-different format** (`.MTS` transport-stream in
   `PRIVATE/AVCHD/BDMV/STREAM/` + a `.MPL` playlist) — and it is **legacy** (phased out for MP4/XAVC-S
   since ~2014). Defer it.
6. **The product gap is real:** auto-detecting joiners (ReelSteady, Gyroflow) are GoPro-only;
   cross-format joiners (LosslessCut) are fully manual. **No tool does auto-detect + multi-brand +
   lossless + telemetry preservation + SD-card watch-folder.** That is exactly DJIjoiner's niche.

## Pluggable architecture implication

Only **two** things need to be per-brand:
1. A **filename parser** (for ordering + variant-suffix detection).
2. An optional **playlist reader** (AVCHD `.MPL` only).

Everything else stays shared: the metadata-continuity grouper, the **stream-parameter identity hard
gate** (same codec/res/fps/pixfmt — non-negotiable before any `-c copy`), the FFmpeg join engine,
the queue, verification, and sidecar stitching. Adding GoPro ≈ "write a GoPro filename parser +
carry its embedded GPMF telemetry track" — not a rework.

---

## Brand-by-brand reference

### Action cameras

| Brand | Split trigger | Same-recording key | Order key | Sidecars | Concat |
|---|---|---|---|---|---|
| **GoPro** legacy | ~4 GB | trailing 4 digits constant (`GOPR####` → `GP01####`, `GP02####`) | middle 2 chapter digits | `.THM`, `.LRV` (`GL` prefix) | `-c copy`; GPMF telemetry needs explicit `-map` |
| **GoPro** HERO6+ | 4 GB (12 GB on H11+/exFAT) | **trailing 4 digits** (`GH01xxxx`, `GH02xxxx`) | **middle 2 digits** | `.THM`, `.LRV` | `-c copy`; `GH`=H.264, `GX`=H.265 (never cross-merge) |
| **GoPro MAX** 360 | 4 GB | `GS01####` / `GS02####` | chapter digits | — | `.360` proprietary stitch |
| **Insta360** | 4 GB + dual-lens | timestamp + `nnn`; lens `_00_`=back / `_10_`=front | timestamp/`nnn` | `.lrv`, `.insp` | MP4 inside `.insv`; 360 reconstruction proprietary |
| **DJI Osmo / Pocket** | 4 GB + time cap | metadata continuity (`DJI_NNNN` sequential) | sequence | `.LRF`, `.SRT` | `-c copy`; same engine as drones |
| **Sony** action | 4 GB | sequence + timestamp (`C0001`…) | sequence | — | `-c copy` (or TS for AVCHD mode) |
| **Akaso / budget** | 4 GB + time cap | sequence + timestamp | sequence | `.THM` | `-c copy`; SoC-vendor naming varies — rely on metadata |

**GoPro grouping rule (counter-intuitive):** files of one recording share the **last 4 digits**; the
**middle 2 (chapter) increment**. `GH010128` joins `GH020128`, NOT `GH010129`. Worth a dedicated
parser + unit test. GPMF (`gpmd`) telemetry track is dropped by naïve concat.

**Insta360 gotcha:** never rename `.insv` (software keys off timestamp+lens+number to pair lenses);
360 stitch (combine `_00_`+`_10_`, lens calibration, FlowState gyro) is proprietary.

### Drones / gimbals / FPV

| Brand | Split trigger | Same-recording key | Variant suffixes | Sidecars |
|---|---|---|---|---|
| **DJI** drones | 4 GB firmware cap (even exFAT) | metadata continuity; index **increments** per segment | `_W` wide, `_Z` zoom/tele, `_T` thermal(or tele), `_S`, `_V`, `_D` main | `.SRT`, `.LRF` |
| **DJI FPV / Avata** | 4 GB | metadata | `_D` main (single-camera) | `.SRT`, `.LRF` |
| **Autel** EVO | 4 GB (even exFAT) | metadata — **numbering resets per session** (collision risk) | thermal vs visible (folder/stream, not letters) | telemetry embedded / flight logs |
| **Skydio** 2/2+ | exFAT, firmware | `S100xxxx.MP4` sequence | single-camera | cloud / flight logs |
| **Skydio** R1 | firmware | `FXXX_VYY.MOV` (`FXXX`=flight, `VYY`=video #) | single-camera | `FXXX_MYY.M4A` phone audio |
| **Parrot** Anafi | 4 GB | `P` + 3-digit batch + 4-digit within-batch | single (thermal models separate) | embedded |
| **HoverAir** X1 | size/firmware | **undocumented** — app-mediated; assume metadata-only | single | none |
| **Walksnail** Avatar | 4 GB (exFAT on newer fw) | date/index per goggle | none | `.osd` + `.srt` (share basename) |

**DJI confirmations:** index **increments** per segment (filename can't prove continuity →
metadata-continuity grouping is correct + necessary). `_D` = main-camera marker, **not** a part
marker. Variant suffixes = parallel sensors (different codec/res) → the camera-variant guard is
essential. `.SRT`/`.LRF` share the MP4 basename.

### Mirrorless / DSLR / camcorders (MP4 family)

| Brand | Naming | Folder | Split | Continuity | Join |
|---|---|---|---|---|---|
| **Sony** XAVC-S | `C0001.MP4`, `C0002.MP4` | `PRIVATE/M4ROOT/CLIP/` | 4 GB FAT32; single on exFAT | sequence + sidecar XML + timestamp | remux (`-c copy`) |
| **Canon** EOS | `MVI_xxxx.MOV/.MP4` | `DCIM/100CANON/` | **4 GB even on exFAT** | sequence + timestamp | remux |
| **Canon** Cinema | `Cxxx`/`Dxxx` + camera/reel/codec letters | — | 4 GB | sequence; relay-recording across 2 slots | remux |
| **Nikon** | `DSC_xxxx.MOV/.MP4` | `DCIM/100NCxxx/` | 4 GB (Z bodies default exFAT) | sequence + timestamp only | remux |
| **Panasonic** Lumix | `P1000001.MP4` | `DCIM/100_PANA/` | 4 GB FAT32 (or 29:59 in legacy MP4) | sequence + timestamp | remux |
| **Fujifilm** | `DSCF xxxx.MOV` | `DCIM/100_FUJI/` | ≤32 GB card splits >4 GB; >32 GB single | sequence + timestamp | remux |
| **Blackmagic** | camera/reel/date/clip | — | **exFAT/HFS+ → single file** (outlier) | N/A — no spanning | usually nothing; `.braw` opaque |

**Note:** all of these reuse DJIjoiner's existing MP4/MOV concat path with just a per-brand filename
parser. Blackmagic is a near no-op (single-file by design).

### AVCHD (legacy — defer)

- **Structure:** `.MTS`/`.M2TS` (MPEG-2 transport stream) in `PRIVATE/AVCHD/BDMV/STREAM/`
  (`00000.MTS`, `00001.MTS`…); **`.MPL` playlist** in `PLAYLIST/` is the authoritative record of which
  segments form one continuous recording + their order; clip info in `CLIPINF/`. 8.3 short filenames.
- **Join:** TS is splice-designed — camera-spanned siblings rejoin losslessly via binary concat
  (`cat`), tsMuxeR, or FFmpeg concat. TS→MP4 caveat: AC-3 audio isn't MP4-native (may force AAC
  re-encode) and can introduce FPS quirks — keep output `.MTS`/`.mkv` for true lossless.
- **Currency:** **legacy.** Sony/Panasonic (its inventors) moved to MP4-wrapped **XAVC-S** and plain
  MP4 since ~2014; AVCHD survives only as a secondary mode on some still-shipping camcorders and on
  the large 2008–2018 installed base. Effectively **nobody buying a new camera in 2026 records AVCHD
  as their primary format.** Highest effort-to-relevance ratio of anything surveyed → **park as
  "only if users ask."** The FFmpeg engine already handles `.MTS`; only the discovery/parse layer
  (folder walk + `.MPL` reader) is new work.

---

## Existing tools / competitive landscape

| Tool | Auto-detect sets? | Lossless? | Telemetry | Limitation |
|---|---|---|---|---|
| **LosslessCut** | No (manual order) | Yes | Generic | Manual; needs identical params; no ingest/watch |
| **GoPro Quik** | Partial (in-app) | Re-encode | GoPro | No standalone merge export |
| **ReelSteady Joiner** | Yes (folder) | Yes | **Preserves GPMF** | **GoPro only** |
| **Gyroflow File Joiner** | Yes | Yes | For stabilization | Stabilization-oriented |
| **ffmpeg concat (DIY)** | No | Yes | Manual `-map` + exiftool | CLI; hand-built list |
| **tsMuxeR / Sony PlayMemories** | Partial | Yes | AVCHD/Sony | Brand/format-specific, legacy |
| **NLEs (Premiere/FCPX)** | Spanned-aware | Re-encode on export | Yes | Heavyweight |

**Gap:** strong auto-detect joiners are single-brand (GoPro); the strong cross-format joiner is
manual. None combine auto multi-brand set detection + lossless join + telemetry/sidecar preservation
+ SD-card watch-folder ingest. **That empty space is DJIjoiner's target.**

---

## Brand-agnostic detection strategy (strongest → weakest)

1. **Stream-parameter identity — hard gate.** Same codec/res/fps/pixfmt/audio. Mismatch → never
   merge (corrupt `-c copy`). The single biggest correctness lever.
2. **Timestamp continuity — strongest positive.** `creation_time[N+1] ≈ creation_time[N] + real
   duration[N]`. ⚠️ **Slow-mo trap:** slow-mo reports ~4× playback duration — use real elapsed/capture
   time or file-size-at-cap, never raw container duration (already learned on real DJI footage; see
   memory `slowmo-dual-timebase`).
3. **Segment ends at the split cap — corroborating.** ~4 GB (or ~2 GB old AVCHD) ⇒ continued; well
   under the cap ⇒ final/standalone (distinguishes the 29:59 truncation case).
4. **Sequential filename within a recording ID — brand-parsed, supporting only.** GoPro constant ID;
   DJI/Sony numeric runs. Never overrides a param mismatch.
5. **Camera-variant guard — hard exclusion.** Never merge co-temporal parallel-camera files (DJI
   `_T/_W/_Z/_V/_S`, GoPro front/rear).
6. **Sidecar association.** Carry `.SRT`/GPMF/`.osd` through with corrected cumulative offsets; copy
   global/spherical metadata explicitly (ffmpeg drops it).

**Most brand-agnostic core:** (1) identical stream params + (2) creation_time+real-duration
continuity, gated by (5) variant exclusion — needs *zero* per-brand filename knowledge and degrades
gracefully on unknown brands.

---

## Roadmap recommendation

- **v1 (now):** DJI only.
- **Phase 2 (rebrand):** modern **MP4/MOV family** — GoPro, DJI Osmo, Sony XAVC-S, Canon, Nikon,
  Panasonic, Fujifilm. ~90%+ of footage shot today; all reuse the existing engine + a per-brand
  filename parser. GoPro is the natural first target (also brings the GPMF telemetry path).
- **Deferred / "if asked":** AVCHD (legacy, structurally different), 360 reconstruction (proprietary),
  Blackmagic (single-file, near no-op).

---

## Key sources

- FAT32/exFAT, cross-brand split: <https://www.winxdvd.com/video-transcoder/why-does-gopro-dji-canon-sony-split-video-files.htm>, <https://www.winxdvd.com/resize-video/fat32-file-size-limit.htm>, <https://en.wikipedia.org/wiki/ExFAT>
- 29:59 WTO/ITA tariff origin: <https://www.dpreview.com/articles/0794343949/wto-looking-at-moves-to-remove-30-minute-limit-from-digital-cameras>, <https://www.recordinglimits.com/faq/>
- DJI splits even on exFAT / suffixes: <https://cosci.de/en/photography-en/why-dji-cameras-split-videos-into-multiple-files/>, <https://mavicpilots.com/threads/file-naming-ends-with-s-t-or-v.134826/>
- GoPro chaptering/naming: <https://community.gopro.com/s/article/GoPro-Camera-File-Naming-Convention?language=en_US>, <https://community.gopro.com/s/article/HERO13-Black-File-Chaptering-And-Naming-Information>; telemetry-preserving join: <https://www.trekview.org/blog/join-gopro-chaptered-split-video-files-preserve-telemetry/>
- Insta360 filenames: <https://subethasoftware.com/2022/04/06/insta360-one-x2-filenames-and-extensions/>, <https://www.insta360.com/support/supportcourse?post_id=20753>
- Sony XAVC-S split + folders: <https://helpguide.sony.net/ilc/2110/v1/en/contents/TP1000640149.html>, <https://www.sony-asia.com/electronics/support/articles/00017373>
- Canon naming / 4 GB: <https://cam.start.canon/en/C018/manual/html/UG-07_Set-up_0070.html>, <https://www.canon-europe.com/pro/infobank/file-numbering-and-naming/>
- Nikon / Panasonic / Fujifilm: <https://onlinemanual.nikonimglib.com/zf/en/video_file_types_39.html>, <https://support-uk.panasonic.eu/app/answers/detail/a_id/3725/>, <https://fujifilm-dsc.com/en/manual/x-t4/technical_notes/capacity/index.html>
- AVCHD spec + currency: <https://en.wikipedia.org/wiki/AVCHD>, <https://en.wikipedia.org/wiki/XAVC>, <https://en.wikipedia.org/wiki/MPEG_transport_stream>, <https://en.wikipedia.org/wiki/.m2ts>
- Autel / Skydio / Parrot / Walksnail: <https://autelpilots.com/threads/evo-recording-in-two-separate-files.2804/>, <https://support.skydio.com/hc/en-us/articles/360045594134>, <https://parrotpilots.com/threads/parrot-file-output-naming-convention.3310/>, <https://walksnail.wiki/en/FAQ>
- Tools: <https://github.com/mifi/lossless-cut>, <https://github.com/rubegartor/ReelSteady-Joiner>, <https://docs.gyroflow.xyz/app/getting-started/file-joiner>
- FFmpeg concat methods: <https://wavespeed.ai/blog/posts/blog-how-to-merge-concatenate-videos-ffmpeg/>, <https://ffmpeg.org/ffmpeg-formats.html>
</content>
</invoke>
