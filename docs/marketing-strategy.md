# Conjoyn — Solo-Dev Marketing Strategy

> How a one-person shop markets **Conjoyn** (the native macOS app that auto-stitches
> split DJI drone MP4 segments back into one lossless file) without a budget, an ad team,
> or a marketing background. Written for the realities in `CLAUDE.md`: solo dev, ~2 focused
> hours/week on marketing, direct + notarized distribution (no Mac App Store).

---

## TL;DR — the one thing to do

**Win the moment of intent.** Drone pilots don't search for "video stitcher." They hit a wall
("my flight recorded as 4 files — how do I join them losslessly?") and ask in the same 4–5 places
every time: **MavicPilots, PhantomPilots, the official DJI Forum, r/dji, and Google.** Be the best
answer in those exact places. Everything else (Product Hunt, YouTube, an email list) is amplification
on top of that wedge.

Pick **one wedge for month one** — community answering + a single cornerstone tutorial — and go deep
before adding channels. Splitting effort across five channels in week one is the #1 solo-dev failure mode.

---

## 1. Who the customer actually is (ICP)

Three overlapping segments, in priority order:

1. **Prosumer / hobbyist drone pilots on Mac** — fly a Mavic/Air/Mini/Avata, shoot long takes that
   split at the 4 GB FAT32 boundary, and want them rejoined *without re-encoding* before editing.
   Largest, most reachable, lowest willingness-to-pay individually but huge volume.
2. **Pro/commercial drone operators** — real-estate, inspection, mapping, wedding/event creators.
   They process cards daily, value the **watch-folder ingest** and **SRT telemetry stitching**, and
   will happily pay a one-time fee that saves them 10 minutes per card. Highest willingness-to-pay.
3. **Drone content creators / YouTubers** — they teach workflows. Each one who adopts Conjoyn becomes
   a distribution channel. Low in number, disproportionate in reach.

**What unites them:** they already have the problem *today*, repeatedly, and the existing fixes are
clunky. That is the easiest kind of product to market — you're not creating demand, you're intercepting it.

---

## 2. Positioning & messaging

### The core promise (use this everywhere)
> **Drop in your DJI clips. Get one perfect file back.**
> Conjoyn auto-detects which segments belong together, joins them losslessly (no re-encode),
> fixes the timecode and creation date, and stitches the `.SRT` telemetry — automatically.

### Why Conjoyn vs. the free alternatives (this is the whole pitch)
The market already has FFmpeg, Shutter Encoder, DaVinci Resolve, Avidemux, and small GitHub scripts
like DJIConcat. Conjoyn must earn its price by removing *work and risk*, not by "merging video" (a
commodity). Lead with the things the free tools **don't** do:

| Job to be done | FFmpeg / DaVinci / scripts | **Conjoyn** |
|---|---|---|
| Figure out which files belong together | Manual — you build the list by hand | **Automatic** — groups by metadata continuity (`creation_time` + duration + filename order) |
| Avoid merging camera variants (`_T`/`_W`/`_Z`) | You must know not to | **Guarded** — never merges variants |
| Lossless join | Yes (if you get the flags right) | **Yes, by default** — concat demuxer `-c copy` |
| Fix timecode ↔ creation-date | No / manual | **Automatic**, with discrepancy surfaced for confirmation |
| Stitch `.SRT` telemetry with corrected offsets | No | **Yes** — the standout feature nobody else has |
| SD-card ingest | No | **Watch-folder** auto-processing |
| Command line / friction | High | **Native Mac app, drag-and-drop** |

**One-line differentiator:** *"The only tool that rejoins the **SRT telemetry** too, and figures out the
grouping for you."* The SRT + auto-grouping combo is the moat — lead with it.

### Messaging guardrails
- Speak the customer's words: "split files," "4 GB limit," "joining clips," "merge without re-encoding,"
  "blank frame between clips" (a known pain with QuickTime). Not "concat demuxer" or "metadata continuity."
- Sell the outcome (one clean file, telemetry intact, seconds not minutes), not the tech (FFmpeg, AVFoundation).
- Honesty converts in technical communities: say it wraps FFmpeg and is lossless. These users respect that.

---

## 3. Channel strategy (ranked for a solo dev)

Ranked by ROI-per-hour for *this specific app*. Do them roughly in this order.

### Tier 1 — start here (highest intent, lowest cost)

**A. Community answering (the wedge).**
The forums where the exact question is asked weekly:
- **MavicPilots.com** — the largest Mavic/Air/Mini community; recurring "joining/combining video files" threads.
- **PhantomPilots.com** — "combining video files fast and without loss" is a perennial thread.
- **official DJI Forum (forum.dji.com)** — "Video split into multiple files," "How to Merge Video Files."
- **r/dji, r/djimavic, r/dronephotography** on Reddit.

Play: become a genuinely helpful regular. Answer the merge question thoroughly (even recommending free
options), and mention Conjoyn as the no-friction Mac option *when relevant*. Do **not** drive-by spam —
these communities punish it and it's the fastest way to get banned and torch the brand. Aim for a
reputation, not a link drop. Most forums let you put a link in your signature once you have standing.

**B. SEO / niche tutorial content (compounds for free).**
This is the solo founder's best channel — it's the only one that keeps paying after you stop working.
Target **long-tail, high-intent, low-competition** queries people literally type:
- "how to merge split DJI video files mac"
- "join DJI drone clips without re-encoding"
- "combine DJI Mini 4 Pro split video lossless"
- "DJI SRT file merge telemetry"
- "fix DJI video timecode / creation date after merging"
- "why does my DJI split video into multiple files" (top-of-funnel)

Write one **cornerstone tutorial** ("The complete guide to rejoining split DJI footage on Mac") that
honestly covers FFmpeg, Shutter Encoder, DaVinci *and* Conjoyn — then a cluster of short, specific
pages around it (per-drone-model, per-problem). 2–4 articles/month, consistently, beats a burst.
Long-tail because you cannot out-rank big sites on "merge video" — you can own "merge DJI Mini 4 Pro
SRT telemetry on Mac."

### Tier 2 — amplify once Tier 1 is producing

**C. YouTube / creator seeding.**
Drone tutorial channels are where this audience learns. Two moves: (1) make your own 60–90s screen
recording showing drag-in → one clean file (use it on the landing page, Product Hunt, Reddit, and as
a YouTube short); (2) offer free licenses to mid-size drone-workflow YouTubers for an honest review.
One workflow video that ranks for "DJI editing workflow" can outperform months of forum posts.

**D. Product Hunt launch.**
A one-day spike of traffic + a permanent piece of social proof + a backlink. Treat it as a *milestone*,
not a strategy. Indie macOS utilities (DevUtils, Screen Studio, Keeby) have used it well. Do it **after**
you have a polished landing page, a demo video, and a small warm audience to vote — a launch into a void
underperforms. For a small/tight-knit audience, a **weekend launch** faces less competition.

### Tier 3 — opportunistic / later
- **Hacker News** (Show HN) — works for dev-flavored tools; the "wraps FFmpeg, native Mac, lossless,
  here's the architecture" angle plays well. Higher variance.
- **Mac software roundup sites / newsletters** and drone-photography blogs — pitch for inclusion.
- **App directories** — listing on Mac app catalogs and "alternatives to X" pages for the SEO backlinks.

---

## 4. The content/asset engine (build these once, reuse everywhere)

A solo dev should produce a small set of durable assets and recycle them across every channel:

1. **The 60–90s demo video** — drag clips in, one file out, SRT preserved. This is your single most
   reused asset (landing page hero, PH, Reddit, YouTube short, forum embeds).
2. **A focused landing page** — headline = the core promise; above the fold = the demo + download/buy;
   then the comparison table, the SRT/auto-grouping differentiators, FAQ (4 GB split explainer, "is it
   lossless?", "which drones?", "is my footage safe?"), and a visible price.
3. **The cornerstone SEO tutorial** + a model/problem-specific cluster.
4. **Before/after screenshots** — a messy folder of `DJI_0001`…`0004` → one file; the SRT overlay intact.
5. **A short FAQ/explainer** on *why* DJI splits files (4 GB FAT32 limit) — pure top-of-funnel SEO bait
   that earns trust before the pitch.

Reuse over reinvention: every channel gets a different framing of the same five assets.

---

## 5. Pricing & conversion (so the marketing pays off)

- **Stick with a one-time purchase** (matches `CLAUDE.md`: direct + notarized, no MAS). It's a clear,
  honest match for a "do one job perfectly" utility, and the audience is allergic to subscriptions for
  a tool they use occasionally. One-time + free-trial converts well for prosumer Mac utilities and is a
  *marketing message in itself* ("buy once, yours forever") in a subscription-fatigued market.
- **Offer a free trial / free tier** (e.g., full features, watermark or N-files limit) so forum and SEO
  traffic can self-serve and feel the magic before paying. Frictionless trial >> "contact for demo."
- Because distribution is direct, you control the funnel end-to-end. Use a simple license/checkout
  (Paddle/Gumroad/LemonSqueezy-style merchant-of-record handles VAT and notarized-app delivery), so you
  spend time on the product, not on tax plumbing.
- Anchor price against time saved for segment #2 (pros): "saves 10 min per card." That reframes the
  price from "expensive merge button" to "cheap hour back."

---

## 6. The 90-day plan (concrete, solo-sized)

**Weeks 1–3 — foundation & lurk.**
- Ship the landing page + demo video + free trial + checkout.
- Create accounts on MavicPilots, PhantomPilots, DJI Forum, Reddit. *Lurk and help first* — build a
  few weeks of genuine, non-promotional standing so you're not a day-one spammer.
- Publish the cornerstone tutorial + the "why DJI splits files" explainer.

**Weeks 4–8 — work the wedge.**
- Answer the merge question wherever it's asked, weekly. Track which threads/keywords convert.
- Publish 1 article/week in the SEO cluster (per-model, per-problem).
- Seed 3–5 drone-workflow YouTubers with free licenses.
- Start a tiny email list (one capture box on the landing page) — even 100 names is a launch audience.

**Weeks 9–12 — amplify.**
- **Product Hunt launch** (weekend, with the warm list + demo ready). Then a **Show HN** with the
  technical angle.
- Pitch Mac-software newsletters and drone blogs for inclusion.
- Double down on whichever Tier-1 channel produced the most installs; drop or pause the rest.

---

## 7. Metrics — what a solo dev should actually watch

Keep it to a handful, reviewed weekly (1 acquisition wedge at a time):
- **Trial downloads** and **trial → paid conversion** (the only revenue truth).
- **Source attribution** — which forum thread / search query / video drove installs (UTM links + a one-
  field "where did you hear about us?" at checkout).
- **SEO:** ranking + clicks for the target long-tails (Search Console).
- **Leading indicator of word-of-mouth:** repeat mentions of "Conjoyn" you didn't post yourself.

Rule: every two weeks, kill the lowest-ROI activity and reinvest the hours into the best one.

---

## 8. Things to NOT do (solo-dev traps)

- **Don't drive-by spam forums/Reddit.** One bad promo post can get the brand banned from the exact
  community that is your best channel. Help first, always.
- **Don't run paid ads early.** A niche this specific is cheaper to reach via SEO + community than via
  CPC, and ads burn cash a bootstrapper can't spare. Revisit only after organic proves the funnel.
- **Don't market the tech.** "Concat demuxer with `-fflags +genpts`" means nothing to a pilot who just
  wants one clean file. Sell the outcome.
- **Don't fragment effort.** Five half-channels < one channel done well. Sequence, don't parallelize.
- **Don't over-claim.** These are technical users; "lossless, wraps FFmpeg, here's exactly what it does"
  builds the trust that converts. Hype repels them.

---

## 9. The single highest-leverage move

If you only do one thing: **own the answer to "how do I rejoin split DJI footage on Mac" in the three
forums and on Google.** That's where the buyers already are, asking the exact question Conjoyn answers,
the day they need it. Be the best, most honest, most frictionless answer there — and let the SRT-telemetry
+ auto-grouping differentiators do the closing.

---

## Sources

- [App Marketing 2026: Indie Devs' Guide + Tools — App Growth Studio](https://appgrowthstudio.com/app-marketing-2026-indie-devs-guide-tools/)
- [Indie App Marketing Strategies (2026) — Rapid App Store](https://rapidappstore.com/blog/indie-app-marketing-strategies)
- [My Solo Dev Marketing Stack: What Actually Gets Downloads — DEV](https://dev.to/godnick/my-solo-dev-marketing-stack-what-actually-gets-downloads-1h8n)
- [App Ideas for Indie Hackers, Solo Devs & Small Studios (2026) — Niches Hunter](https://nicheshunter.app/blog/app-ideas-indie-hackers-solo-devs-studios)
- [How to Launch on Product Hunt: A 2026 Guide for macOS Apps — Screen Charm](https://screencharm.com/blog/how-to-launch-on-product-hunt)
- [Product Hunt Launch Guide 2026 — Calmops](https://calmops.com/indie-hackers/product-hunt-launch-guide/)
- [I launched 2 apps on Product Hunt and both were featured — Indie Hackers](https://www.indiehackers.com/post/i-launched-2-apps-on-product-hunt-and-both-were-featured-heres-what-i-learned-0b24c76a3a)
- [Top 15 DJI Forums in 2026 — Feedspot](https://forums.feedspot.com/dji_forums/)
- [Top 20 Drone Forums in 2026 — Feedspot](https://forums.feedspot.com/drone_forums/)
- [Combining video files fast and without loss — PhantomPilots](https://phantompilots.com/threads/combining-video-files-fast-and-without-loss.153386/)
- [Joining video files — MavicPilots](https://mavicpilots.com/threads/joining-video-files.134495/)
- [How to Merge Video Files — DJI Forum](https://forum.dji.com/thread-307348-1-1.html)
- [Why DJI Cameras Split Videos Into Multiple Files — CoSci](https://cosci.de/en/photography-en/why-dji-cameras-split-videos-into-multiple-files/)
- [DJIConcat (competing free tool) — GitHub](https://github.com/chann1n9/DJIConcat)
- [SEO for Solopreneurs: 2 Hours Per Week — Wrigo](https://wrigo.io/blog/seo-for-solopreneurs-the-content-strategy-that-works-with-2-hours-per-week)
- [SEO for Software: Niche Tutorial Marketing — Stormy AI](https://stormy.ai/blog/seo-for-software-niche-tutorial-marketing)
- [Escaping the Mac App Store: Distribution & Sales for Indie Apps — fatbobman](https://fatbobman.com/en/posts/zipic-2-selling-and-distribution)
- [11 App Pricing Models for 2026 — FunnelFox](https://blog.funnelfox.com/app-pricing-models-guide/)
