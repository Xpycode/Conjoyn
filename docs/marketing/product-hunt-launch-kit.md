# Conjoyn — Product Hunt Launch Kit

> Everything to run a clean Product Hunt launch as a solo dev. PH is a one-day traffic spike + a
> permanent piece of social proof + a backlink — treat it as a *milestone*, not a strategy. Launch
> only after the landing page, demo video, free trial, and a small warm audience are ready. A launch
> into a void underperforms. For a small/tight-knit audience, a **weekend launch** faces less
> competition than a Tuesday.

---

## Pre-launch checklist (2–3 weeks out)

- [ ] Landing page live, demo video embedded, free trial downloadable, checkout working.
- [ ] **Become a PH member now** and start upvoting/commenting on other products daily — brand-new
      accounts with zero history get their votes discounted by PH's ranking, so warm the account up.
- [ ] Line up a **hunter** (optional). Self-hunting is fine in 2026; a well-followed hunter only helps
      if they genuinely use the tool. Don't chase a big-name hunter who won't engage.
- [ ] Build a **launch-day list**: anyone who'll genuinely upvote/comment — trial users, email signups,
      drone-forum contacts, friends. 20–50 real supporters beats a cold launch.
- [ ] Prepare the gallery assets (see shot list below).
- [ ] Draft the tagline, description, and first comment (below).
- [ ] Pick the date: a **Saturday or Sunday** for a smaller audience; avoid major tech-launch days.
- [ ] Schedule the launch for **12:01 AM PT** so you get the full 24-hour window.

---

## The listing copy

**Name:** Conjoyn

**Tagline (≤60 chars — this is the hook, lead with the outcome):**
> `Rejoin split DJI drone clips losslessly — telemetry and all`

*Alternates to A/B in your head:*
> `One clean file from your split DJI footage. SRT included.`
> `Auto-stitch split DJI videos on Mac — no re-encoding`

**Description (the short blurb under the tagline):**
> DJI cameras split long flights into ~4 GB chunks. Conjoyn auto-detects which segments belong together,
> rejoins them losslessly (no re-encode), fixes the timecode, and stitches the `.SRT` telemetry back
> in sync — on a native Mac app. Drag, drop, done.

**Topics/tags:** Mac, Video, Productivity, Photography (+ Drones if available).

**First comment (post this the second you launch — it frames the whole thread):**
> Hey Product Hunt 👋 I'm [name], the solo dev behind Conjoyn.
>
> This started from my own annoyance: DJI drones split long recordings into separate ~4 GB files
> (a FAT32 card limit), so one clean flight lands on your Mac as `DJI_0001`, `0002`, `0003`… plus a pile
> of `.SRT` telemetry files. You *can* rejoin them with FFmpeg, but you're building file lists by hand,
> hoping you don't re-encode, and the telemetry usually gets lost.
>
> Conjoyn does the whole thing automatically:
> • Auto-detects which segments belong to the same flight (metadata, not just filenames)
> • Joins them **losslessly** — no re-encoding, original quality
> • Fixes the timecode + creation date
> • **Rejoins the `.SRT` telemetry** with corrected offsets — the part other tools skip
> • Watch-folder mode auto-stitches as you offload a card
>
> It's a native Mac app, one-time purchase, notarized, no subscription. There's a free trial — I'd
> genuinely love for you to run it on your own footage and tell me where it falls short. Happy to answer
> anything about the lossless join, the SRT handling, or which drones it supports. 🚁

---

## Launch-day playbook

- **Post the first comment immediately**, then stay in the thread all day — reply to *every* comment
  within minutes. Engagement (comments + maker activity), not just raw votes, drives PH ranking.
- **Notify your warm list** — but ask them to "check out the launch," *not* "go upvote." Vote-soliciting
  language ("please upvote") can get a launch penalized. Let them find the button.
- **Don't buy votes or use vote rings.** PH detects and penalizes it; it can nuke the launch.
- Share the launch where it's *welcome*: your own social, an email to your list, a Show HN if you want.
  **Do NOT** drop the PH link in the DJI forums/Reddit — that's the spam move that burns your best channel.
- Answer hard/skeptical questions honestly (the FFmpeg-vs-Conjoyn comparison from the tutorial is your
  friend here). Technical audiences reward candor.

---

## After the launch (don't let it fade)

- Add a **"Featured on Product Hunt" / badge** to the landing page — permanent social proof.
- Screenshot the ranking and any nice comments for future "what people say" sections.
- Keep the backlink — link to the PH page from your site and vice versa.
- Recycle the best comment exchanges into FAQ / testimonial copy.
- Whatever your best-performing message was on PH, fold it back into the landing-page hero.

---

## Gallery / image shot list (PH shows these prominently)

1. **Cover image** — the core promise as text over a clean drone-footage still: *"One clean file from
   your split DJI footage."*
2. **The drag-and-drop** — messy folder of `DJI_0001…0004` + `.SRT` files being dropped in.
3. **Auto-grouping** — UI showing detected flights/groups (and a variant like `_T` kept separate).
4. **The result** — one output file, with a "lossless / no re-encode" callout.
5. **SRT telemetry** — the standout: telemetry rejoined and in sync.
6. **Watch-folder mode** — for the pro segment.
7. **The 60–90s demo video** (PH lets you feature it — see the demo script doc).
