# Outreach — Philip Bloom (special target)

> A big-name pro is normally the *wrong* target for a solo dev (generic pitch, drowned out). Bloom is the
> exception: he publicly flagged the exact pain Conjoyn fixes (the DJI timecode/metadata mess, in one of
> his drone reviews). So this isn't a cold pitch — it's "you raised this problem; I built the fix."
>
> **Lead with timecode/metadata correctness, NOT the 4 GB split.** To a hobbyist the hook is "one flight,
> five files." To a cinematographer like Bloom the hook is "your TC and creation date come out *correct*,
> and the SRT stays in sync" — broken TC wrecks ingest and multicam sync, which is what he actually cares
> about. The lossless split-merge is almost the boring prerequisite to him.

---

## Before you send — fill these two blanks

1. **`[THE REMARK]`** — find the specific drone review where he mentions the TC issue (check
   philipbloom.net/blog/category/reviews/drones/ — the blog post may quote it in text). Reference it
   accurately; paraphrase, don't put words in his mouth. Even "in your [model] review you mentioned the
   timecode/creation-date being a mess" is enough if you can't get the exact quote.
2. **`[YOUR APPS]`** — the "maker of [your other video apps]" credibility line. Pull this in your next
   desktop-terminal session where the other projects are visible. This line is what signals you're not a
   weekend hobbyist — you understand video plumbing. Don't omit it.

---

## Draft email

> **Subject:** You flagged the DJI timecode mess in your [MODEL] review — I built the fix
>
> Hi Philip,
>
> In your [MODEL] review you mentioned `[THE REMARK — e.g. how DJI's timecode / creation date comes
> through wrong]`. That stuck with me, because it's the exact thing I just spent months solving.
>
> I'm a solo developer — [maker of `[YOUR APPS]`] — and my latest is a small Mac app called **Conjoyn**.
> It auto-rejoins DJI's split clips losslessly (no re-encode), but the part I think you'd actually care
> about is the metadata: it **corrects the timecode and creation date** (treating TC as authoritative and
> surfacing any discrepancy for you to confirm, rather than silently guessing), and it **stitches the
> `.SRT` telemetry back together with corrected time offsets** so the flight data stays in sync with the
> footage. Drag in a card or folder, get one clean, correctly-stamped file back.
>
> I'd love to just **give you a license** — no strings, no ask for coverage. If it saves you a headache on
> the next drone job, that's the win. And honestly I'd value your eye on where the metadata handling falls
> short, since you clearly think about this more than most.
>
> Want me to send a code? There's a free trial here too if you'd rather poke at it first: [link].
>
> Best,
> [Name]
> [site] · [email]

---

## Shorter version (if reaching out via a DM / comment with a character limit)

> Hi Philip — in your [MODEL] review you flagged the DJI timecode/creation-date mess. I'm a solo dev
> ([maker of `[YOUR APPS]`]) and just shipped Conjoyn, a Mac app that rejoins split DJI clips losslessly,
> *corrects* the TC + creation date, and rejoins the `.SRT` telemetry in sync. Happy to give you a license,
> no strings — would love your take on the metadata side. Free trial: [link].

---

## Notes on handling it

- **Send via his business/contact channel**, not a public reply — this is a personal, specific note, and a
  public "hey check out my app" reads as spam even when it isn't.
- **One follow-up max**, ~a week later, if no reply. Then leave it.
- If he engages, **make it effortless**: send the license immediately, offer the demo video / screenshots,
  and be fast and humble about questions. A pro who feels listened to is worth far more than one video.
- **Don't ask for a review or a video.** If he likes it he'll mention it unprompted, and that's worth ten
  times a solicited plug. If he offers feedback instead of coverage, that feedback is the prize — it'll
  make the app better for every pro after him.
- **Disclosure:** if he ever does cover it off the back of a free license, that's fine as long as he
  discloses per his norms — but you never ask for or imply a positive review.

---

## Why this one is worth the effort

If Bloom even *mentions* Conjoyn in passing, it reaches exactly the pro/cinematographer segment that has
the highest willingness to pay and that the forums/SEO don't reach as well. And because the hook is *his
own stated complaint*, the response odds are far better than a generic big-name pitch. Low effort, asymmetric
upside. Worth doing carefully and once.
