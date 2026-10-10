# Tasks

Completed execution detail: `docs/plans/output-safety-1.0.6.md`. Review evidence and R1–R12 definitions:
`docs/reviews/2026-09-05/app-code-review.md`. Prior GoPro progress and wave commentary are preserved
in `tasks-archive.md`; its plan and specs remain available.

## Current Sprint — 1.0.6 release blockers (6/6 groups closed)

Repair plan `plans/release-blockers-1.0.6.md` closed: 1.0.6 published on 2026-10-10.
E3 GUI acceptance was explicitly waived by the user, not performed. Completed groups are in
`tasks-archive.md`; physical active-read device-loss acceptance remains in the 1.1 backlog.

## Backlog — 1.1 acceptance (1 group)

- [ ] **Device loss during active discovery — 1.1** — Physically disconnect/reconnect disposable
      test media while discovery is in flight; verify stale results cannot enqueue, recovery resumes,
      and a healthy watcher continues. Unverified, not a known failure: macOS refused graceful
      unmount while Conjoyn read its fixture. User deferred this 1.0.6 gate on 2026-10-10.
      Preserve fixed-SSD versus removable-card and OS mount-cycle versus cable-loss distinctions.
      Evidence: `reviews/2026-10-10/physical-mount-acceptance.md`; decision in `decisions.md`.

## Backlog — review follow-up (remaining scope)

Code-established unless the report records runtime reproduction. No remedy below is marked
implemented; only the four targeted portions above have moved into the planned sprint.

- [ ] **R2** — Remove two unimplemented output options; honor the SRT switch and clarify telemetry scope.
- [ ] **R3** — Separate filtering/selection, expose hidden selection, preserve displayed enqueue/rename order.
- [ ] **R4 remainder** — Improve scan progress and user-facing cancellation beyond stale-result protection.
- [ ] **R8** — Propagate Stop through copying, sidecars and verification; prevent cancelled→completed races.
- [ ] **R9** — Restore accessible names, selected/expanded values, and a semantic console disclosure.
- [ ] **R10 remainder** — Surface actionable scan/join failures beyond queue persistence recovery.
- [ ] **R11** — Retire ineffective watch state and unused verification orchestration after compatibility checks.
- [ ] **R12** — Simplify output/naming layout and direct rename editing; correct shortcuts/Help and drop feedback.
      E2 minor follow-up: suppress a stale Apply prompt if pending jobs disappear during its 400 ms delay
      (source-established presentation edge; Apply still targets current pending jobs).

## Backlog — pre-existing footage and product work (9 groups)

- [ ] **G8.1** — Hero 11 H.264 probe: capture ~30 s GH clip. Last negative archive search was
      2026-08-09, not repeated this session. Historical execution detail: IMPLEMENTATION_PLAN-gopro.md.
- [ ] **Output re-ingest guard** — GUI outputs without rename can retain a parseable camera stem;
      separate from the current overwrite fix. Trace grouping/watch interaction before changing names.
- [ ] **More cameras** — Osmo Action 1 and GoPro 7; footage-gated.
- [ ] **SD-card photos** — detect/surface, then optional verified copy; preserve, do not process
      (2026-07-14 decision; no HDR/RAW/panorama scope).
- [ ] **Localization** — English-only today; target languages and string catalog work deferred.
- [ ] **DMG polish** — optional custom background.
- [ ] **Footage-gated engine slivers** — reader polish, TS-remux fallback, Apple Keys creationdate;
      preserve the 2026-06-24 caveats and historical v1 plan.
- [ ] **Owed live checks** — adaptive ETA, AppCitizenshipKit surfaces, SRT mismatch/slow-mo integrity chips;
      not covered by this review's narrow live workflow.
- [ ] **Scratch-folder guidance/UI** — error mentions File → Temp Folder, which is not exposed;
      user deferred it on 2026-06-25. Do not silently expand this safety sprint to add that feature.

## Backlog — runtime follow-up (1 confirmed)

- [ ] **Picker initialization timeout** — 60-second NSOpenPanel/ViewBridge hang captured on macOS 27.0; underlying cause unresolved. See `reviews/2026-09-17/output-folder-recovery.md`.

## Inbox

No unconfirmed observations awaiting triage. Design remedies in R11/R12 remain proposals, not
approved implementations or evidence that every custom control must be replaced.
