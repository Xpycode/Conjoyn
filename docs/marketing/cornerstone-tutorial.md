# Cornerstone SEO Tutorial (draft)

> The pillar article for organic search. Honest and genuinely useful — it covers the free methods
> *and* Conjoyn, because being the best, most trustworthy answer is what earns the ranking and the
> click-through in technical communities. Target reader: a Mac drone pilot who just found their flight
> split into numbered files. ~1,800 words; expand the per-model sections over time into a cluster.
>
> **Primary keyword:** how to merge split DJI video files on mac
> **Secondary:** join DJI clips lossless · DJI SRT merge · why DJI splits video · combine DJI footage
> **Suggested slug:** `/blog/merge-split-dji-video-mac`

---

## H1: How to Merge Split DJI Drone Videos on Mac (Losslessly, With Telemetry Intact)

*Last updated: [DATE]*

You shot one smooth, continuous flight — but back on your Mac it's landed as `DJI_0001.MP4`,
`DJI_0002.MP4`, `DJI_0003.MP4`, and a scatter of `.SRT` files. This guide explains **why** that happens
and walks through every reliable way to stitch the pieces back into one file **without losing quality** —
from free command-line tools to a one-click Mac app. By the end you'll know which method fits your
workflow, and how to keep your telemetry in sync.

### Quick answer
- **One flight, occasionally:** use **FFmpeg's concat demuxer** (free, lossless) or DaVinci Resolve.
- **You do this every shoot, or you care about the `.SRT` telemetry:** use a purpose-built tool like
  **[Conjoyn](#)** that auto-groups the clips, fixes the timecode, and rejoins the telemetry for you.

---

### H2: Why does DJI split videos into multiple files?

It isn't a setting you can fully turn off, and it isn't corruption. DJI cameras record to SD cards
formatted as **FAT32**, and FAT32 can't hold a single file larger than **4 GB**. So when a recording
crosses that size, the camera closes the current file and immediately opens the next — splitting one
continuous flight into ~4 GB chunks. At high bitrates (4K, high frame rates) you can hit that limit in
just a few minutes, which is why long takes produce three, four, or more parts.

The good news: the split happens **at the container level**, so the pieces can be rejoined *exactly*,
with no quality loss — if you do it right.

---

### H2: The one rule — join losslessly (don't re-encode)

The single biggest mistake is re-exporting your merged video through an editor, which **re-encodes** it
and throws away quality (and time). Because DJI's segments are already the same codec, resolution, and
frame rate, the correct approach is a **stream copy** — re-wrapping the existing video and audio into one
container without touching the pixels. Every method below that's labeled *lossless* does exactly that.

A second, subtler trap: some quick fixes (like dragging clips into QuickTime) can insert a **blank frame**
between segments. The methods below avoid that.

---

### H2: Method 1 — FFmpeg concat demuxer (free, lossless, command line)

FFmpeg is the gold standard for lossless joins. Create a text file listing your clips in order:

```
file 'DJI_0001.MP4'
file 'DJI_0002.MP4'
file 'DJI_0003.MP4'
```

Then run:

```bash
ffmpeg -f concat -safe 0 -i list.txt -c copy -fflags +genpts -movflags +faststart -y output.mp4
```

`-c copy` is what makes it lossless (no re-encode). `+genpts` rebuilds clean timestamps; `+faststart`
makes the file stream-friendly. It's fast because nothing is re-processed.

**Good for:** people comfortable in Terminal, occasional joins.
**Watch out for:** building the file list by hand (and in the *right order*), and making sure you don't
accidentally include a different flight or a camera variant. FFmpeg won't stop you from joining files
that don't belong together. It also won't touch your `.SRT` telemetry.

---

### H2: Method 2 — DaVinci Resolve (free, GUI, great if you already edit)

Resolve's free version is hugely popular with drone shooters. Import the clips, drop them on the timeline
in order, and — to stay lossless — export with a matching codec or use a "render in place"/passthrough
approach so you're not transcoding. If you're going to edit the footage anyway, this is a natural fit.

**Good for:** people already editing in Resolve.
**Watch out for:** it's easy to accidentally re-encode on export; and it's heavyweight if all you want is
to merge and move on.

---

### H2: Method 3 — Shutter Encoder / Avidemux (free, GUI, lossless)

Both are free desktop tools that can losslessly concatenate DJI segments without inserting the blank
frame QuickTime sometimes adds. They get the job done for one-off merges.

**Good for:** a free GUI without the command line.
**Watch out for:** still manual file selection and ordering; no telemetry handling.

---

### H2: Method 4 — Conjoyn (Mac app, automatic, telemetry-aware)

If you do this regularly — or you shoot with telemetry and want it preserved — a purpose-built tool
removes the manual steps the methods above leave you with. **[Conjoyn](#)** is a native Mac app that:

- **Auto-detects which segments belong together** by reading each clip's embedded metadata
  (`creation_time`, duration, filename order) — no hand-built file lists, no wrong-order mistakes.
- **Joins losslessly by default** (it's built on the same FFmpeg concat under the hood, `-c copy`).
- **Won't merge camera variants** like `_T` (thermal), `_W` (wide), or `_Z` (zoom) by accident.
- **Fixes the timecode and creation date** so the merged file carries the right capture time.
- **Stitches the `.SRT` telemetry** back together with corrected time offsets — so GPS, altitude, and
  camera data still line up with the video. *This is the part the other methods simply don't do.*
- Offers a **watch-folder mode** that auto-stitches complete flights as you offload a card.

**Good for:** anyone who does this more than once, anyone who cares about the `.SRT` data, and anyone
who'd rather drag-and-drop than build a file list. There's a free trial, so you can run it on your own
footage before deciding.

---

### H2: Don't forget the `.SRT` telemetry

Each DJI clip ships with a matching `.SRT` subtitle file holding per-frame telemetry — GPS coordinates,
altitude, ISO, shutter, and more. When you merge the video, those `.SRT` files need their **timestamps
offset and concatenated in the same order**, or the data drifts out of sync with the footage (or you lose
it entirely). The manual tools above leave this to you; Conjoyn handles it automatically. If you map,
inspect, or overlay flight data, this matters.

---

### H2: Which method should you use?

- **One flight, you live in Terminal:** FFmpeg.
- **You already edit in Resolve:** Resolve, careful not to re-encode on export.
- **You want a free GUI for the occasional merge:** Shutter Encoder or Avidemux.
- **You do this often, want it automatic, or need the `.SRT` telemetry preserved:** Conjoyn.

---

### H2: FAQ

**Will merging reduce my video quality?** Not if you use a lossless (stream-copy) method — all the ones
above qualify. Re-exporting through an editor's encoder is what costs quality.

**Why is there a blank frame between my merged clips?** That's a known artifact of some quick methods
(e.g. QuickTime). Use FFmpeg, Shutter Encoder, Avidemux, or Conjoyn to avoid it.

**Can I stop DJI from splitting files?** Not really — it's the FAT32 4 GB limit. Some workflows reformat
to exFAT where supported, but many DJI cards/cameras don't, so merging after the fact is the reliable fix.

**Do I need to keep the `.SRT` files?** If you want GPS/altitude/camera telemetry, yes — and you'll want
a tool that rejoins them in sync (Conjoyn does this automatically).

---

*Internal links to add as the cluster grows: per-model guides (Mini 4 Pro, Air 3, Mavic 3, Avata 2),
"why DJI splits video into multiple files," "how to read DJI SRT telemetry," "fix DJI video timecode."*
