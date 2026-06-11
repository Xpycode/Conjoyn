# SEO Cluster Pages (per-drone-model drafts)

> Supporting pages that surround the [cornerstone tutorial](./cornerstone-tutorial.md) and target
> **model-specific long-tails** people actually type. Each should be published as **its own URL** and
> **internally link up** to the cornerstone (and the cornerstone links down to each — that hub-and-spoke
> is what makes the cluster rank).
>
> ⚠️ **Avoid thin/duplicate content.** Don't just swap the model name across identical text — Google
> penalizes that. Each page must carry *model-specific* facts: that drone's file-naming, its codecs/bitrate
> (and therefore how fast it hits the 4 GB split), and any quirks. Placeholders below marked `[verify]`
> need a real spec check before publishing.

---

## Page 1 — DJI Mini 4 Pro

- **Slug:** `/blog/merge-split-mini-4-pro-video-mac`
- **Title tag:** `Merge Split DJI Mini 4 Pro Videos on Mac (Lossless + SRT)`
- **Meta:** `Rejoin your DJI Mini 4 Pro's split clips into one lossless file on Mac — no re-encode.
  Keep the SRT telemetry in sync. Free guide + tool.`
- **Primary KW:** `merge split DJI Mini 4 Pro video`

**H1: How to Merge Split DJI Mini 4 Pro Videos on Mac (Without Losing Quality)**

Opening (model-specific): The Mini 4 Pro shoots up to `[verify: 4K/100fps, ~150 Mbps in some modes]`, so
a long flight crosses the 4 GB FAT32 limit and lands on your Mac as `DJI_0001.MP4`, `DJI_0002.MP4`… plus
matching `.SRT` telemetry. Here's how to rejoin them losslessly — and keep the GPS/altitude data in sync.

Body: brief 4 GB explainer (link cornerstone) → FFmpeg lossless method → mention the Mini 4 Pro's
`.SRT` carries the ActiveTrack/flight telemetry many Mini pilots want to keep → Conjoyn as the
auto-grouping, telemetry-aware one-click option (free trial). Close with FAQ + link up to cornerstone.

---

## Page 2 — DJI Air 3 / Air 3S

- **Slug:** `/blog/merge-split-air-3-video-mac`
- **Title tag:** `Combine Split DJI Air 3 Footage on Mac — Lossless, Telemetry Intact`
- **Meta:** `Your DJI Air 3 split a long take into multiple files? Rejoin them losslessly on Mac and keep
  the SRT telemetry synced. Step-by-step + tool.`
- **Primary KW:** `combine DJI Air 3 split video`

**H1: Combining Split DJI Air 3 Footage on Mac (Lossless)**

Model-specific angle: the Air 3's dual-camera system means you may have **two focal lengths** per flight —
a perfect place to explain Conjoyn's **camera-variant guard** (it won't merge the wide and tele/`[verify
suffix]` clips together by mistake, which is exactly the kind of error a manual FFmpeg list invites). Then
the standard lossless-merge + SRT story.

---

## Page 3 — DJI Mavic 3 / Mavic 3 Pro

- **Slug:** `/blog/merge-split-mavic-3-video-mac`
- **Title tag:** `Merge Split DJI Mavic 3 Pro Clips on Mac (No Re-Encode)`
- **Meta:** `Rejoin split DJI Mavic 3 / Mavic 3 Pro video into one lossless file on Mac. Keep timecode and
  SRT telemetry correct. Free guide.`
- **Primary KW:** `merge split Mavic 3 video lossless`

**H1: How to Merge Split DJI Mavic 3 Pro Videos on Mac (Losslessly)**

Model-specific angle: Mavic 3 Pro is a **triple-camera** rig (Hasselblad + medium tele + tele), and shoots
high-bitrate `[verify: up to ~200 Mbps / ProRes on Cine]` — so it splits fast *and* produces multiple
variants. Lead harder on the **variant guard + correct timecode** here because this is prosumer/pro
territory (bridge toward the pro/TC messaging). Then lossless merge + SRT.

---

## Page 4 — DJI Avata 2 (FPV)

- **Slug:** `/blog/merge-split-avata-2-video-mac`
- **Title tag:** `Join Split DJI Avata 2 FPV Clips on Mac (Lossless)`
- **Meta:** `DJI Avata 2 split your FPV run into files? Rejoin them losslessly on Mac and keep the flight
  data in sync. Simple guide + one-click tool.`
- **Primary KW:** `join DJI Avata 2 split video`

**H1: Joining Split DJI Avata 2 FPV Footage on Mac**

Model-specific angle: FPV runs are continuous and high-bitrate, so Avata 2 pilots hit splits constantly on
long sessions; emphasize **speed of a lossless join** (no re-encode of fast-motion footage) and that the
flight telemetry stays intact. Otherwise the standard structure.

---

## Shared structure (every page)

1. Model-specific intro naming the real file pattern + why *this* drone splits.
2. 1–2 sentence 4 GB explainer → **link to cornerstone** ("full guide here").
3. The free lossless method (FFmpeg, short) — be genuinely useful.
4. The model-specific wrinkle (variants / telemetry / bitrate) → where Conjoyn removes manual work.
5. Conjoyn as the auto/telemetry-aware option + free-trial link.
6. 2–3 model-specific FAQ lines.
7. Link up to cornerstone + sideways to 1–2 sibling model pages.

## Expansion backlog (add as you have time / see search demand)
Mavic 4 Pro · Mini 3 / 3 Pro · Air 2S · Neo · Inspire 3 (pro/ProRes angle — strong for the TC/metadata
message) · Osmo Action (action-cam split, adjacent audience). Also problem-pages: "DJI blank frame between
clips," "DJI wrong creation date fix," "how to read DJI SRT telemetry."
