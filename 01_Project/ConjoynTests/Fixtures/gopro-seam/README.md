# GoPro seam fixtures (wave G4.3)

Two real Hero 11 slices spanning a genuine chapter boundary, used by
`GoProJoinIntegrationTests` to prove that a GoPro seam joins losslessly with the in-container
`gpmd` telemetry track intact.

## Provenance

Cut 2026-08-07 from recording **6349** in the corpus
(`V26/V26-MEDIA/V26-H11/H11-PHOTOS H11/PHOTOS H11 - 2026/PHOTOS H11 - 2026-08`), an **intact**
two-chapter recording:

| Fixture | Source | Cut |
|---|---|---|
| `GX016349.MP4` | `H11--2026-08-04--18-14-42--GX016349.MP4` (10.85 GB, 2063.360 s) | last GOP, `-ss 2062.32` |
| `GX026349.MP4` | `H11--2026-08-04--18-14-42--GX026349.MP4` (1.72 GB, 327.240 s) | first GOP, `-t 1.04` |

So the boundary between the two fixtures **is** the real chapter boundary — the last frames the
camera wrote to chapter 01 against the first frames it wrote to chapter 02.

**Why 6349 and not 6347/6345** (which the plan named as examples): 6349 is the lowest-bitrate
intact multi-chapter recording in the corpus by a wide margin — **45 Mbps @ 25 fps** against
~120 Mbps for 6345/6346/6347/6348. The plan's own selection rule is "pick the lowest-bitrate
intact recording" to hold the fixture under the 12 MB cap, and at 120 Mbps a single GOP is ~11.5 MB
— two of them would have doubled the cap on their own. 6338 is excluded outright: its chapter 01
left the archive.

**Why one GOP each:** the keyframe interval is **1.04 s**, and `-c copy` cannot cut below a GOP.
1.04 s per slice is therefore the floor, not a preference. Total **11.67 MB**, under the 12 MB cap.

## Layout — note the index

Both fixtures probe as `hvc1 | mp4a | gpmd | tmcd`, i.e. **gpmd at index 2**.

The camera originals they were cut from carry `hvc1 | mp4a | tmcd | gpmd` — **gpmd at index 3**.
The difference is not an error in the cut: ffmpeg cannot copy GoPro's source `tmcd` track
(`Could not find tag for codec none in stream #2`, which produces a **zero-byte output** — the same
finding that forces the production join to map streams explicitly instead of using `-map 0`), so it
drops the source `tmcd` and regenerates one, writing it *after* gpmd. These fixtures are therefore
the **remux** shape that wave G2 also measured, not the camera-original shape.

**Consequence for test coverage:** the end-to-end test exercises index 2. Index 3 — the shape of
every camera original — is covered by `FFmpegConcatArgsTests`' exact-vector assertions and by the
join-time probe, but **not** end-to-end here. Task **G8.2** (a real full join of an unsliced GoPro
group) is what closes that gap. This is a known, deliberate limit of the fixture, not an oversight.

## Measured baselines (bundled ffmpeg/ffprobe, 2026-08-07)

Joined with the production vector
`-f concat -safe 0 -i list -map 0:v:0 -map 0:a? -map 0:2 -c copy -copy_unknown -fflags +genpts -movflags +faststart -timecode …`:

| Stream | `GX016349` | `GX026349` | Sum | Joined output |
|---|---|---|---|---|
| gpmd packets | 1 | 1 | 2 | **2** |
| gpmd bytes | 7,084 | 6,916 | 14,000 | **14,000** |
| video packets | 26 | 26 | 52 | **52** |
| video bytes | 6,360,559 | 5,803,911 | 12,164,470 | **12,164,470** |
| audio packets | 49 | 49 | 98 | **98** |
| audio bytes | 24,731 | 24,728 | 49,459 | **49,459** |

Byte-exact on every stream — the join copies, it does not re-encode. The output also carries a
regenerated `tmcd` from `-timecode`, which has no source counterpart by design.

**The gpmd packet counts are thin (1 per slice)** because gpmd runs at 1 packet/second and the GOP
floor is 1.04 s. The byte totals are the stronger assertion: a dropped telemetry track, a `d:0`
selection that grabbed `tmcd` instead, or a wrong `-map` index all fail the byte check.
