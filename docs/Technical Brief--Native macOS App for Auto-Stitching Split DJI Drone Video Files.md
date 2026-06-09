# Technical Brief: Native macOS App for Auto-Stitching Split DJI Drone Video Files

## TL;DR
- **Build the grouping engine on embedded metadata, not filenames.** Read each segment's start timecode (QuickTime `tmcd` track), `mvhd`/`creationdate` creation timestamp, and exact duration; chain segment N→N+1 where `startTC(N) + duration(N) ≈ startTC(N+1)` within a sub-frame tolerance. Use DJI's `DJI_####` sequential numbering only as a corroborating secondary signal. Then concatenate losslessly with FFmpeg's **concat demuxer** (`-f concat -safe 0 -i list.txt -c copy`).
- **Use AVFoundation natively for reading, FFmpeg for joining, and exiftool for the metadata-fix write-back.** AVFoundation (`AVAsset`, `AVAssetReaderTrackOutput` on the `tmcd` track, `CMTime` durations) is the most reliable native reader; FFmpeg `-c copy` preserves streams but is limited for MP4 atom rewriting, so the TC↔creation-date fix is best finalized with exiftool/atom manipulation.
- **For watch-folder automation, use FSEvents for the directory tree and add a stability/debounce gate** (poll file size + mtime until stable, confirm no exclusive write lock) so partial files and incrementally-arriving segment sets are never processed prematurely.

## Key Findings

1. **Metadata-based chaining is the correct architecture.** DJI splits at the 4 GB FAT32 boundary. Per DJI Support (quoted on PhantomPilots), footage "is segmented every 4GB so that in an event of power surge or power failure, you will still have a file that you can recover compared to a total loss of the whole footage," and a DJI Forum representative confirms "our video processor does split video files near the 4GB file limit of FAT32, even if using a 32GB or 64GB SD Card formatted as exFat (FAT64)." Newer models cap segments at roughly 16.8 GB (about 20–21 minutes per the CoSci Blog). The split point falls mid-recording, so the end timestamp of segment N and the start timecode of segment N+1 are designed to be continuous. This makes TC + duration arithmetic a far more reliable grouping key than filenames, which DJI resets to `DJI_0001` on in-drone card format and which collide across multiple drones.

2. **FFmpeg concat demuxer with `-c copy` is the right join method** — it is I/O-bound, lossless, and handles thousands of files via a list. Per the FFmpeg Formats Documentation, "The timestamps in the files are adjusted so that the first file starts at 0 and each next file starts where the previous one finishes... All files must have the same streams (same codecs, same time base, etc.)." The concat *protocol* does not work for MP4/MOV, and the concat *filter* re-encodes (wrong for this use case).

3. **The main FFmpeg gotchas are timestamp continuity and non-video data streams.** Expect "Non-monotonous DTS" warnings at joins; DJI telemetry/subtitle (SRT) data streams can break a clean stream copy and need explicit mapping decisions. The `tmcd` timecode track and creation-date atoms are not reliably carried through concat copy and must be re-applied.

4. **The TC/creation-date fix should rewrite the creation-date metadata to match timecode (treat TC as authoritative for broadcast), not the reverse,** and is most reliably done with exiftool QuickTime tags or direct atom edits after the FFmpeg join.

---

## Details

### 1. Segment Grouping / Auto-Detection Logic

**Primary signal — metadata chaining.** For each candidate `.MP4`/`.MOV`, extract:
- `startTC` — start timecode from the `tmcd` track (HH:MM:SS:FF).
- `creationTime` — from `mvhd` `creation_time` and/or `com.apple.quicktime.creationdate`.
- `duration` — exact, as rational/`CMTime` (not the rounded "seconds" float).
- `frameRate` — nominal and whether VFR.

**Chaining rule:** convert `startTC` and `duration` to a common frame count at the clip's frame rate. Segment B follows segment A iff:

```
endFrame(A) = startFrame(A) + durationInFrames(A)
B follows A  ⟺  | startFrame(B) − endFrame(A) | ≤ TOLERANCE
              AND same codec/resolution/framerate/audio params
              AND creationTime(B) ≈ creationTime(A) + duration(A)  (corroborating)
```

**Tolerance window.** Because DJI splits mid-GOP at a file-size boundary, a clean recording is intended to be frame-contiguous — DJI/WinX guidance states that "even if the video is split up, there is no frame loss. As long as you have a continuous recording, you will get a seamless playback." However, DJI Forum users on slower cards report roughly a second of video / dropped frames at the join point. Default tolerance is therefore **±1 frame**, widened to **±2 frames** if testing on the target card/drone shows a sub-frame gap at the cut. A gap substantially larger than one or two frames (e.g. seconds) indicates a *separate* recording, not a continuation — that is the discriminator between "same recording, next chapter" and "new clip."

**Frame-rate / VFR considerations.** Do timecode math in the exact rational timebase, not floats. For drop-frame rates (29.97/59.94) account for DF vs NDF when converting TC↔frames. DJI footage is generally constant frame rate, but if `ffprobe`/AVFoundation reports VFR (`avg_frame_rate ≠ r_frame_rate`), fall back to comparing `creationTime + duration` continuity and total sample counts rather than nominal-rate frame math.

**Secondary/corroborating signal — DJI naming.** DJI uses `DJI_0001.MP4`, `DJI_0002.MP4`… sequential numbering; newer models (e.g. Mavic 3 Pro) use long date-time names like `DJI_20230813102011_0008_D.MP4`. The counter resets to 0001 when the card is formatted in-drone and rolls a new `DCIM` media folder after 999 files. Use ascending numbering / contiguous indices to break ties and order within a confirmed group, but never as the sole grouping key — the user's instinct to trust metadata over filenames is correct, since numbering collides across drones and resets on format.

**Edge cases to handle:**
- Multiple independent recordings copied into one folder → metadata chaining naturally separates them by the time-gap test.
- A trailing tiny segment (DJI sometimes emits a final clip of a few seconds / tens of MB) → include if it chains by TC continuity.
- Mixed drones / mixed settings in one folder → segment chains must also require matching stream parameters (codec, resolution, fps, audio sample rate), so dissimilar clips never merge.
- Missing middle segment → detect a TC discontinuity larger than tolerance and either split into two outputs or flag the gap.

### 2. Reading Metadata on macOS

**AVFoundation (preferred native path):**
- `AVURLAsset(url:)`; load `.duration` as `CMTime` for exact rational duration.
- Creation date: `asset.creationDate` (an `AVMetadataItem`; `dateValue` gives `Date`, else `stringValue`). Also query `AVMetadataItem.metadataItems(from:filteredByIdentifier:)` for `com.apple.quicktime.creationdate`.
- Timecode: locate the `tmcd` track via `asset.tracks(withMediaType: .timecode)`, then read the first sample with `AVAssetReader` + `AVAssetReaderTrackOutput`; convert the returned frame number to `CVSMPTETime`. Apple Technical Note TN2310 documents this exactly: the timecode sample "value identifies the first frame in the group of frames that use this timecode sample," and the read path is to create an "AVAssetReaderTrackOutput for the timecode track then call -(BOOL)startReading," converting the returned frame number "to a CVSMPTETime representation." The `avtimecodereadwrite` sample code is a working reference.
- Frame rate: `videoTrack.nominalFrameRate` and `.minFrameDuration`.

**ffprobe (corroboration / fallback):**
```
ffprobe -v error -show_streams -show_format -print_format json input.mp4
```
The `tmcd` stream exposes `TAG:timecode` (e.g. `00:36:32:10`); `creation_time` appears as an ISO-8601 tag (e.g. `2020-04-21T15:22:51.000000Z`) on streams/format. Note ffprobe exposes MOV timecode via the `tmcd` stream's `TAG:timecode`, not a top-level `timecode` field.

**exiftool:** strong for reading/writing the full QuickTime tag set (`QuickTime:CreateDate`, `Keys:CreationDate`, `TrackCreateDate`, `MediaCreateDate`), with `-api QuickTimeUTC=1` for correct UTC handling.

**Recommendation:** Use AVFoundation as the primary reader (native, no external dependency, authoritative for `tmcd` and `CMTime`). Shell to ffprobe only when AVFoundation returns nil for an unusual DJI variant, and use exiftool's reader to cross-check the creation-date discrepancy.

### 3. The Timecode / Creation-Time Mismatch Fix

**What to detect:** the embedded start `tmcd` value (wall-clock-of-day TC) disagrees with the `mvhd`/`creationdate` calendar timestamp. For broadcast workflows the **timecode is the authoritative reference**; the fix should rewrite the *creation-date metadata to be consistent with the timecode* (and the recording's real start), rather than altering the TC track.

**FFmpeg capabilities and limits during the concat copy:**
- `-metadata creation_time="2025-06-07T10:00:00.000000Z"` sets the container creation tag on output.
- `-timecode 01:00:00:00` writes a start timecode; the MOV muxer has a `write_tmcd` option (`-write_tmcd 1`) controlling whether a `tmcd` track is written.
- **Limit:** FFmpeg does not robustly preserve an *existing* `tmcd` track through `-c copy` concat, and its MP4 metadata model does not expose every QuickTime atom (e.g. `com.apple.quicktime.creationdate` Keys vs `mvhd` creation_time are handled inconsistently). So you generally must *re-specify* `-timecode` and `-metadata creation_time` on the concat output rather than rely on inheritance.

**Where exiftool / atom manipulation is needed:** to write the Apple `Keys:CreationDate` (the one QuickTime Player/Finder shows) and to keep `mvhd`, track, and media create/modify dates internally consistent:
```
exiftool -overwrite_original -api QuickTimeUTC=1 \
  '-QuickTime:CreateDate=2025:06:07 10:00:00' \
  '-Keys:CreationDate=2025:06:07 10:00:00-00:00' \
  '-TrackCreateDate<QuickTime:CreateDate' \
  '-MediaCreateDate<QuickTime:CreateDate' output.mp4
```

**Authoritative-source guidance:** Treat the start timecode as ground truth for the recording's start-of-day. Derive the corrected creation date from `TC + known recording date`, write it to all QuickTime date atoms, and write a single correct start `tmcd` on the joined output (`-timecode`). Do not silently rewrite the TC track to match a possibly-wrong camera clock; surface the discrepancy in the UI and let the user confirm which is authoritative, defaulting to TC.

### 4. P2toMXF Reference and Spanned-Clip Architecture Lessons

**Repo availability note:** A GitHub project named exactly **"P2toMXF" could not be located** via GitHub or web search during this research; it may be private, renamed, very new, or referred to by an informal name. The user should confirm the exact owner/slug. Rather than guess at its internals, the architecturally relevant lessons come from how Panasonic P2 spanning is *defined* and how established P2 tools (BBC Ingex, Telestream FlipFactory, EDIUS P2 Select, CatDV) handle it.

**How P2 spanning works (authoritative, from BBC Ingex and Telestream):**
- P2 uses OP-Atom MXF where each track is a separate file. Per BBC Ingex, the format "lays out all audio tracks under the CONTENTS/AUDIO/ directory and all video tracks under CONTENTS/VIDEO/... an 80x60 BMP thumbnail in the CONTENTS/ICON/ directory and writes an XML file containing structural metadata" in `CONTENTS/CLIP/`. One logical clip = a video MXF + N audio MXFs + a CLIP XML + icon, all sharing a 6-character hex prefix (e.g. `0009E7`).
- Spanning occurs at the same 4 GB FAT32 limit, or when a card fills mid-recording.
- **Grouping is done via the CLIP XML metadata**, not filenames. Per the Telestream FlipFactory P2 app note, spanned files carry special XML elements "named head, next, and prev. Each file has a head element so that the MXF codec can identify and locate the top of the chain... and then work back down through the chain." Critically, "FlipFactory does not use global unique IDs from the MXF headers or XML file" — instead it "uses the start timecode from each XML file in the playlist as the source timecode." This is a strong external validation of the user's timecode-first premise.
- **Filename numbering is explicitly unreliable for P2.** Per Telestream, "The P2 system creates files with unique names of random numbers and letters," and the second segment is not a consecutive suffix of the first (forum examples: `026JSV`→`001WGI`, `0001YK`→`0024T8`). Squarebox's CatDV documentation simply notes "CatDV supports P2 spanned clips – these are clips that have spanned across 2 recording cards," and the product offers grouping either by folder structure or by MXF UMID.

**Patterns that transfer to the DJI MP4 app:**
1. **Trust embedded relational/temporal metadata over filenames** — exactly the user's premise, and exactly what Telestream's start-timecode-based chain walking does. DJI's case is simpler because MP4 carries `tmcd` + `mvhd` directly, so TC-continuity + duration arithmetic is the DJI analogue of P2's XML chain pointers.
2. **Require matching essence parameters before joining** (P2 tools validate codec/format; DJI app should validate codec/resolution/fps/audio).
3. **Produce a single new output file** and treat the chain as one logical clip, while preserving originals until verified — the universal recommendation across DJI forums too.
4. **A watch-folder "predict what belongs together" monitor** (as FFAStrans does for P2 via the folder structure and sidecar files) maps directly onto the DJI watch-folder requirement: predict the full set, wait for all members, then join.
5. **Concatenation engine:** P2 tools rewrap essence (ffmpeg/bmx/mxflib) rather than naive byte-append because MXF has header/index/footer structure. The DJI app's analogue is the FFmpeg concat demuxer with `-c copy` — correct for MP4 because it re-muxes the container while copying the elementary streams.

### 5. FFmpeg Concat Gotchas for DJI Footage

**Method choice:** concat **demuxer** is correct:
```
ffmpeg -f concat -safe 0 -i list.txt -c copy -fflags +genpts output.mp4
```
- Concat *protocol* (`concat:a.mp4|b.mp4`) does **not** work for MP4/MOV (works for MPEG-TS only).
- Concat *filter* re-encodes — avoid for lossless I/O-bound joins.

**Timestamp continuity (DTS/PTS):** the classic symptom is `Non-monotonous DTS in output stream … This may result in incorrect timestamps`. As VideoHelp community guidance clarifies, this "means that a later segment in the concat list does not continue the time stamps from the end of the first segment... A warning is not an error." Mitigations: add `-fflags +genpts` to regenerate presentation timestamps; ensure files are listed in true recording order; all segments must share identical timebase. For stubborn cases, remux each segment to MPEG-TS first (`-c copy -bsf:v h264_mp4toannexb -f mpegts`) and concat the `.ts` files, then re-wrap to MP4 — a well-known fix.

**Audio streams:** all segments must share audio codec, sample rate, and channel count for `-c copy` to succeed — true for same-recording DJI splits by construction. A mismatch produces glitches or failure and would indicate the segments are not actually one recording.

**Data/telemetry & subtitle streams (DJI-specific):** DJI embeds telemetry as a sidecar `.SRT` and, on some models, as in-container subtitle/data streams. These can break a clean stream copy (unsupported data codec on copy) and the SRT timecodes are relative to each segment's start, so naive concat misaligns them. Decisions for the app:
- Map explicitly: `-map 0:v -map 0:a?` to take only video+audio, or `-map 0` to attempt everything and handle failures.
- If a data stream errors on copy, drop it (`-map -0:d`) or transcode just that stream.
- For the sidecar SRT, merge separately with corrected time offsets (cumulative duration of preceding segments) — a known unsolved pain point in the DJI community that this app could differentiate on.

**Codec variants:** DJI footage may be H.264 or H.265/HEVC (e.g. 4K30 D-Cinelike H.265). Concat copy works within a codec; never mix H.264 and H.265 segments in one `-c copy` join. HEVC in MP4 is fine for the demuxer as long as all segments match.

**Timecode/metadata through concat:** the `tmcd` track and creation-date atoms are not reliably preserved; re-apply on output via `-timecode`, `-metadata creation_time=…`, and the exiftool pass from §3. Add `-movflags +faststart` so the `moov` atom is at the front for fast playback/streaming of the joined file.

**Series differences:** Mavic/Air/Mini differ in default codecs, bitrates, and naming (older `DJI_####` vs newer date-time names), and exFAT-capable models may still split internally — so don't assume a fixed split size; rely on metadata continuity.

### 6. macOS Watch-Folder Architecture

**API choice:**
- **FSEvents** (`FSEventStreamCreate`, `FSEventStreamSetDispatchQueue`) — best for monitoring a directory *tree* and getting coalesced change notifications; ideal for the watch folder. Tricky from Swift (C callback, `Unmanaged` context pointer) but the canonical approach (see Apple DTS `DirMonitor` sample and Quinn "The Eskimo!" forum code).
- **DispatchSource** (`DispatchSource.makeFileSystemObjectSource`, `eventMask: [.write]`, fd via `open(path, O_EVTONLY)`) — lighter weight for watching a *single* top-level directory; simpler in Swift. Good choice if you watch one flat ingest folder.

Recommendation: DispatchSource for a single flat watch folder; FSEvents if recursive subfolders (SD card `DCIM` trees) must be watched.

**Detecting a finished file (critical to avoid processing partial copies):** filesystem events fire while a file is still being written/copied. Gate every candidate through a **stability check**:
1. On event, record file size + `modificationDate`.
2. Poll every ~1–2 s; only consider the file "settled" after it is unchanged for N consecutive polls (e.g. 3 polls / ~3–5 s).
3. Additionally confirm no exclusive writer holds it — attempt to open for reading / check it is not still growing; on macOS you can test for advisory locks or simply rely on size+mtime stability for SD-card copies.
4. Debounce the directory: collapse a burst of events into one evaluation pass after the folder goes quiet.

**Waiting for a complete SET of segments:** because segments of one recording arrive sequentially, don't join on first-file-settled. Instead:
- When a file settles, run the grouping logic over all settled files.
- A group is "complete" when the **last** segment is shorter than the split threshold (a full ~4 GB segment implies another may follow) **and** no new chaining segment has appeared within a quiet window (e.g. 30–60 s after the last member settled).
- Use TC continuity to know whether a just-arrived file extends an existing pending group or starts a new one.

**Background processing:** run probing and FFmpeg on a background `DispatchQueue` / `OperationQueue` with bounded concurrency (joins are I/O-bound, so 1–2 concurrent jobs avoid disk thrash). Use a state machine per group: `Discovered → Settling → Grouped → Ready → Joining → VerifyingMetadata → Done/Failed`. Persist state so a relaunch re-scans the folder and resumes. Keep originals until the joined output is probed and verified.

---

## Recommendations

**Stage 1 — Core engine (build & validate first):**
- Implement the AVFoundation metadata reader (`tmcd` start TC, `CMTime` duration, `creationDate`, frame rate) with an ffprobe JSON fallback.
- Implement the chaining algorithm with a configurable tolerance (default ±1 frame) and a stream-parameter equality gate. Unit-test against real DJI sets from multiple models (Mavic/Air/Mini, H.264 and H.265).
- Implement the FFmpeg concat-demuxer join with `-c copy -fflags +genpts -movflags +faststart`, explicit stream mapping, and the post-join exiftool metadata pass.

**Stage 2 — GUI:** drag-and-drop + file browser feeding the same engine; show detected groups, per-group TC/creation-date diff, and a confirm-before-fix control (default: TC authoritative).

**Stage 3 — Watch-folder automation:** DispatchSource (or FSEvents for recursive) + the stability/debounce gate + the "complete set" quiet-window logic + bounded background job queue + persisted state machine.

**Stage 4 — Differentiators:** correct SRT telemetry stitching with cumulative time offsets; batch ingest of whole SD cards.

**Thresholds that change the approach:**
- If real DJI sets show >1-frame gaps at splits → widen tolerance and document it.
- If `tmcd` is absent on a model → fall back to `creationTime + duration` continuity as the primary key.
- If data-stream copy errors are common → default to `-map 0:v -map 0:a?` and offer "preserve all streams" as an opt-in.
- If VFR is detected → switch that group to creation-time/sample-count continuity instead of nominal-rate frame math.

## Caveats
- The exact "P2toMXF" repository could not be verified; §4 is built on authoritative P2 spanning documentation (BBC Ingex, Telestream FlipFactory app note) and established tool behavior (CatDV, EDIUS, FFAStrans), not that specific codebase. Confirm the repo's owner/slug with the user before relying on its specifics. Notably, Telestream's confirmed approach — chaining via XML `head`/`next`/`prev` pointers and using each clip's *start timecode* rather than global IDs — independently validates this brief's timecode-first design.
- DJI behavior varies by model and firmware (split size, codec, naming, presence of in-container data streams); validate the engine against the specific drones the user targets. Note the documented variance: classic 4 GB FAT32/exFAT segmentation on most models vs ~16.8 GB segments on newer ones.
- FFmpeg's preservation of `tmcd` and QuickTime date atoms through `-c copy` is version-dependent and historically incomplete — always verify the joined output's metadata and re-apply rather than assume inheritance.
- "Non-monotonous DTS" warnings are common and usually benign with `+genpts` (a warning, not an error), but verify A/V sync at the join points on output before deleting originals.
- Tolerance, quiet-window, and stability-poll values above are sensible starting defaults, not measured constants; tune against real footage.