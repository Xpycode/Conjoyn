# Conjoyn — Landing Page Copy

> Drop-in copy for the marketing site. Sells the *outcome* (one clean file, telemetry intact),
> not the tech. Honest, technical-audience-friendly. Replace `[PRICE]`, `[TRIAL LIMIT]`, and
> CTAs with live values. Structure mirrors the funnel: hook → proof → differentiate → reassure → buy.

---

## Hero (above the fold)

**Headline:**
# Drop in your DJI clips. Get one perfect file back.

**Subhead:**
Conjoyn auto-detects which split segments belong together and rejoins them **losslessly — no
re-encoding**. It fixes the timecode and creation date, and stitches the `.SRT` telemetry back
together too. Native Mac app. Drag, drop, done.

**Primary CTA:** `Download free trial`  **Secondary CTA:** `Watch 60-second demo`

**Trust strip (small, under the buttons):**
Lossless · Built on FFmpeg · Notarized for macOS · Apple Silicon · No subscription

*(Hero visual = the 60–90s demo loop: a folder of `DJI_0001…0004` dragged in → one file out.)*

---

## The problem (one short block, in their words)

### Your drone splits long flights into pieces. That's not your fault.
DJI cameras break recordings into ~4 GB chunks because of the SD card's FAT32 limit. So a single
clean flight lands on your Mac as `DJI_0001.MP4`, `DJI_0002.MP4`, `DJI_0003.MP4`… plus a pile of
`.SRT` files. Rejoining them by hand is fiddly, and the usual tricks either re-encode (quality loss),
drop a blank frame between clips, or throw away your telemetry.

---

## How Conjoyn works (3 steps)

**1. Drop in a folder or card.**
Conjoyn reads each clip's embedded metadata and figures out which segments belong to the same flight —
by `creation_time`, duration, and filename order. No building file lists by hand.

**2. It joins them losslessly.**
A clean, frame-accurate concat with **no re-encode** — your footage is byte-for-byte the original
quality, just in one file. Codec/resolution/fps mismatches are never force-joined.

**3. It fixes the details others ignore.**
Timecode and creation date corrected. Camera variants (`_T` thermal, `_W` wide, `_Z` zoom) kept
separate, never accidentally merged. And your **`.SRT` telemetry is stitched back together with the
right time offsets** — so GPS, altitude, and camera data still line up with the footage.

---

## Why Conjoyn instead of the free tools? (comparison)

You can merge clips with FFmpeg, DaVinci Resolve, Shutter Encoder, or a script. Here's what you'd
still be doing by hand — and what Conjoyn just handles:

| | FFmpeg / DaVinci / scripts | **Conjoyn** |
|---|:---:|:---:|
| Works out which files belong together | You do, manually | **Automatic** |
| Won't merge camera variants by mistake | You have to know | **Guarded** |
| Truly lossless (no re-encode) | If you get the flags right | **By default** |
| Fixes timecode & creation date | No | **Automatic** |
| **Rejoins the `.SRT` telemetry** | **No** | **Yes** |
| Watch-folder card ingest | No | **Yes** |
| Friction | Command line / setup | **Drag & drop** |

**The short version:** it's the only tool that rejoins your **telemetry** too — and figures out the
grouping for you.

---

## For people who process cards every day

Shooting real estate, inspections, events, or mapping? Turn on **watch-folder mode** and point Conjoyn
at your card or ingest folder. Every complete flight gets stitched automatically while you unload the
next card. Minutes back, every single shoot.

---

## FAQ

**Is it really lossless?**
Yes. Conjoyn uses a stream copy (built on FFmpeg's concat demuxer) — it re-wraps your existing video
and audio without re-encoding. The result is the original quality, just in one file.

**Which drones / files work?**
DJI MP4 segments from the consumer and pro lines — both the legacy `DJI_NNNN` naming and the newer
`DJI_YYYYMMDDHHMMSS_NNNN_<suffix>` naming. If your card splits long flights into numbered `.MP4`
parts, Conjoyn handles them.

**Will my telemetry survive?**
Yes — and that's the point. Conjoyn stitches the matching `.SRT` files with corrected time offsets so
GPS/altitude/camera data stays in sync with the merged video.

**Is my footage safe?**
Conjoyn never modifies your originals — it writes a new merged file. Everything runs locally on your
Mac; nothing is uploaded.

**Subscription?**
No. One-time purchase. Buy it once, it's yours.

**Mac App Store?**
No — Conjoyn is distributed directly and **notarized by Apple**, so it installs and runs like any
trusted Mac app.

---

## Final CTA

### Try it on your own footage — free.
Download the trial, drag in your split clips, and watch one clean file come out. [TRIAL LIMIT].
Like it? Unlock everything for a one-time **[PRICE]**.

`Download free trial`   `Buy Conjoyn — [PRICE]`

---

### Meta / SEO tags for the page
- **Title tag:** `Conjoyn — Merge Split DJI Drone Videos Losslessly on Mac (with SRT)`
- **Meta description:** `Auto-rejoin split DJI MP4 clips into one lossless file on your Mac — no
  re-encoding. Conjoyn fixes timecode and stitches the SRT telemetry too. Free trial.`
- **Primary keyword:** merge split DJI video mac · **Secondary:** join DJI clips lossless, DJI SRT merge,
  combine DJI drone footage.
