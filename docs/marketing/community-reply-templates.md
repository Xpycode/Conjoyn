# Community Reply Templates (forums & Reddit)

> Ready-to-adapt replies for MavicPilots, PhantomPilots, the DJI Forum, and r/dji — for the recurring
> "how do I join my split clips?" threads. **The golden rule: help first, mention Conjoyn second, and
> only when it genuinely fits.** These communities ban drive-by promotion fast, and a ban kills your
> single best channel. Every template leads with a real answer the person can use even if they never
> touch Conjoyn.

---

## Ground rules (read before posting)

1. **Earn standing first.** Spend a few weeks being genuinely helpful — answer questions with *no*
   product mention at all. You want to be a known-good regular before you ever link your app.
2. **Disclose that it's yours.** Always. "Full disclosure, I make a Mac app for this" builds trust;
   hiding it destroys it. On Reddit, undisclosed self-promotion gets you banned and downvoted to oblivion.
3. **Always give the free answer too.** FFmpeg / Resolve / Shutter Encoder. If your only answer is "buy
   my thing," you're spam. If your answer is "here's how to do it free, and here's a shortcut if you do
   this a lot," you're helpful.
4. **Match the platform.** DJI forums tolerate a signature link and occasional honest recommendations.
   Reddit is stricter — keep self-promo rare, and follow each subreddit's self-promotion rule (many use
   a ~10:1 helpful-to-promo ratio). When in doubt, just help and skip the mention.
5. **No copy-paste spam.** Tailor each reply to the actual question. Reusing identical text across threads
   reads as spam to both humans and mods.

---

## Template A — Forum, general "how do I combine my files?" (DJI Forum / MavicPilots / PhantomPilots)

> The split happens because the SD card is FAT32, which can't hold a single file over 4 GB — so DJI
> closes each file at ~4 GB and starts the next. The good news is the pieces can be rejoined with
> **zero quality loss**, because you're just re-wrapping them, not re-encoding.
>
> Free option: **FFmpeg** with the concat demuxer does a perfect lossless join. Make a `list.txt` with
> your files in order and run `-c copy`. **Shutter Encoder** is a free GUI alternative if you'd rather
> not use Terminal, and it avoids the blank-frame-between-clips issue you can get from QuickTime.
>
> Full disclosure — I also make a small Mac app called Conjoyn that automates this (it figures out which
> clips belong together, joins them losslessly, and also rejoins the `.SRT` telemetry so your GPS/altitude
> data stays in sync). There's a free trial if a one-click version is useful, but the FFmpeg route above
> will get you there for free either way. Happy to walk through whichever you prefer.

---

## Template B — Reddit (r/dji), keep it lighter and free-first

> That's the FAT32 4 GB limit — long flights get split into ~4 GB chunks. You can rejoin them with **no
> quality loss** since it's a stream copy, not a re-encode.
>
> Easiest free routes: **FFmpeg** (`concat` demuxer with `-c copy`) if you're OK in Terminal, or
> **Shutter Encoder** / **DaVinci Resolve** if you want a GUI. Avoid just dragging into QuickTime — it can
> stick a blank frame between clips.
>
> One thing people forget: your `.SRT` telemetry files need rejoining too, in the same order with offset
> timestamps, or the GPS/altitude data drifts out of sync.

*(Only add a Conjoyn mention here if the thread is specifically asking for a Mac app / automated tool
**and** you've cleared the subreddit's self-promo rule. Otherwise leave it out — the goodwill is worth
more than one link.)*

---

## Template C — Someone specifically asks "is there an app that just does this on Mac?"

*(This is the one thread where mentioning your product is the genuinely helpful answer.)*

> Yeah — a few options. **Shutter Encoder** and **Avidemux** are free GUIs that do lossless joins.
>
> Full disclosure, I make one called **Conjoyn** built for exactly this: you drop in a card or folder, it
> auto-detects which split segments belong to the same flight, joins them losslessly (no re-encode), fixes
> the timecode/creation date, and — the part the others don't do — rejoins the `.SRT` telemetry so your
> flight data stays in sync. It's got a watch-folder mode too if you process cards regularly. Free trial
> on [link], so you can test it on your own footage before deciding. Happy to answer anything about it.

---

## Template D — Someone is frustrated about the telemetry / blank frames specifically

> Two separate gotchas here:
>
> 1. **Blank frame between clips** — that's usually from joining in QuickTime. FFmpeg (`-c copy`),
>    Shutter Encoder, or Avidemux won't do that.
> 2. **Telemetry going out of sync** — when you merge the video, the matching `.SRT` files have to be
>    concatenated in the same order with their timestamps offset, otherwise the GPS/altitude data drifts.
>    Most merge tools ignore the `.SRT` entirely, which is why it feels like you lose it.
>
> Full disclosure, I built a Mac app (Conjoyn) specifically because the telemetry-sync part was such a
> pain to do by hand — it stitches the `.SRT` with corrected offsets automatically. But if you just need
> the video joined cleanly, FFmpeg or Shutter Encoder will sort the blank-frame issue for free.

---

## Forum signature (where allowed)

> Conjoyn — auto-rejoin split DJI clips losslessly on Mac, telemetry and all. [link]

*Keep it to the signature; don't restate it in the body of every post.*

---

## What NOT to do

- ❌ First-ever post is a link to your app.
- ❌ Same canned paragraph pasted into ten threads.
- ❌ "Just use Conjoyn" with no free alternative offered.
- ❌ Hiding that the app is yours.
- ❌ Arguing with people who prefer FFmpeg — agree with them; FFmpeg is great, and your honesty about it
  is what makes the *occasional* "here's a shortcut" land.
