# Session: 2026-06-13 (h) — Git bootstrap discipline + Directions master reconcile

## Goal
Properly establish git on this Mac for Conjoyn (the folder had **no `.git`** — Syncthing
excludes it), then **generalize** the bootstrap discipline so future project sessions get it for
free, and **reconcile the Directions master** the same way. No Conjoyn app code this session — pure
infrastructure / meta.

## Progress

### 1. Bootstrapped Conjoyn's git (no data loss)
- This Mac had **no `.git`** at all (`~/ProgrammingProjects` is one Syncthing folder; `.git` is
  `.stignore`-excluded → source on disk, history only on `origin`). GitHub access = **HTTPS via
  `gh`** (account `Xpycode`, `repo` scope); **no SSH key** exists on these Macs.
- Safe sequence: `gh auth setup-git` → `git init -b main` → `remote add origin
  https://github.com/Xpycode/Conjoyn.git` → `fetch` → **`git reset --mixed origin/main`** (HEAD+index
  to origin, **working tree untouched**) → `git status`.
- **The check: 0 tracked drift** — every Syncthing'd file was byte-identical to `origin/main`
  (tip `5a69c6f`). Clean adopt; **no `reset --hard` needed**. Set repo-local identity `Luces
  Umbrarum <87826179+Xpycode@users.noreply.github.com>`, upstream `origin/main`.
- Cleaned the one untracked item: added **`.claude/settings.local.json`** to `.gitignore`
  (per-machine permissions, never canonical), commit + push (`1f6c8da`).

### 2. Generalized the runbook (so it's not a one-off)
- New **global skill** `~/.claude/skills/git-bootstrap/SKILL.md` — the full init→fetch→mixed-reset
  →verify procedure, "never blind `reset --hard`", per-Mac constants (HTTPS-via-gh, identity,
  expected-clean untracked tool dirs).
- **Patched global `~/.claude/CLAUDE.md` Multi-Mac pre-flight** to detect the **no-`.git`** case
  (was a silent no-op when not a repo) and delegate to the skill.
- Conjoyn project memory `git-bootstrap-runbook.md` (+ MEMORY.md index) as the concrete instance.

### 3. Corrected the unsafe `reset --hard` advice
- **Conjoyn** `docs/PROJECT_STATE.md` Repo/git line → mixed-reset+verify discipline, HTTPS-via-gh,
  identity, skill pointer (`2dd00db`). Historical session-log narratives left verbatim.
- **Directions master** `37_multi-mac-discipline.md` → new **Rule 1b** (fresh/reset Mac bootstrap)
  + a verify-first guard on Rule 1's "effectively identical → `reset --hard`" row.

### 4. The discipline caught a real divergence (master was stale)
- Bootstrapping the master to push the edit, the **mixed-reset+`git status` check fired**: the
  local master was **5 commits behind origin** and **missing Rule 5** (session-collision),
  `/worktree`, `hooks/install.sh`, `session-guard.sh`, cookbook #91. **My edit had landed on a
  stale copy** — a blind push would have **deleted Rule 5 + 4 files**.
- Recovered properly: `git checkout origin/main -- 37_…md` to get the canonical version, **re-applied**
  the two edits on top, staged only that file → clean single-file commit (`3d10e3c`), pushed.

### 5. Full guided 3-way reconcile of the master's local-only work
- Snapshotted everything to `backup/local-master-divergence-2026-06-13`, then adopted `origin/main`
  (clean tree). Re-applied the genuinely-local work:
  - **7 cookbook files** — origin had claimed `#91` (session-detector), so local `#91-97`
    **renumbered +1 → contiguous #92-98** (retiring origin's empty `#92` hook-handshake
    reservation). Filenames, H1 headings, **intra-group `#9N` cross-refs** (bodies + index rows),
    and the `PATTERNS-COOKBOOK.md` index all bumped to match.
  - **`cookbook/00-app-shell.md` §0.2** grafted (additive, +74/−0): `UIDesignRequiresCompatibility`
    in a checked-in `.xcodeproj`.
  - Kept origin's **newer** `PROJECT_STATE.md` / `commands/status.md` / `hooks/session-start.sh`
    (they carry the Rule 5 / session-guard work; local versions were the older pre-Rule-5 state).
  - Commit `5255d19`, pushed to `Xpycode/LLM-Directions`.
- **Conjoyn ripple:** updated the 3 live cookbook pointers in `PROJECT_STATE.md` (`#94→#95`
  quicklook, `#91,#92→#92,#93` sortable) — `bd47d74`. Global/project CLAUDE.md had no `#91-97`
  refs (never wired in). Session logs left as history.

### 6. Finalized
- Deleted the served-purpose backup branch (content confirmed re-applied via git's rename
  detection; reflog-recoverable ~90d). **Both repos clean and in sync.**

## Decisions
- **Git reconcile discipline:** `init → fetch → reset --mixed → read git status`. Clean tree = adopt;
  any tracked diff = stop, reconcile by hand. **Never blind `reset --hard`.** (Now Rule 1b in the
  master + the `git-bootstrap` skill.)
- **Cookbook numbering:** contiguous **#92-98**, dropping origin's empty `#92` reservation (vs
  honoring it at #93-99) — least gap, accepted the +1 ripple into Conjoyn refs.
- **Superseded vs unique:** the master's local `PROJECT_STATE` "lean-digest" edits were judged
  superseded by origin's newer state and **discarded** (preserved only in the now-deleted backup's
  reflog).

## Next
- **No change to Conjoyn's status** — still 100% feature-complete, 1.0 gated only on **Sparkle
  Wave 4** (website publish). This session touched **no app code**.
- Multi-Mac discipline is now self-correcting: a fresh Mac's session-start pre-flight detects the
  no-`.git` case and runs the safe bootstrap automatically.

## Commits
- Conjoyn: `1f6c8da` (gitignore), `2dd00db` (PROJECT_STATE reconcile advice), `bd47d74` (cookbook
  pointer ripple).
- Directions master (`Xpycode/LLM-Directions`): `3d10e3c` (Rule 1b + guard), `5255d19` (cookbook
  #92-98 + #00 §0.2).
