# Execution Plan — Source↔Target Verification

> Full design: `docs/plans/source-target-verification.md`. Branch: `feature/source-target-verification`.
> Goal: every join gets a green/orange/red seal proving (cheaply) nothing was lost, with a one-click
> byte-exact cryptographic proof on demand. Replaces the dead decode-only verification wiring.

## Waves (sequential — each compiles + green before the next)

### Wave 1 — Models
- [ ] **1.1** `Models/SourceTargetModels.swift` (new): `CheckSeverity`, `CheckOutcome`,
  `VerificationCheck`, `SourceTargetResult`. Add `VerificationStatus.warning(String)` to
  `Models/VerificationModels.swift` (Codable round-trip). Add `var sourceTargetResult` to
  `Models/ConversionJob.swift` (+ CodingKey). Codable tests. → commit `feat(verify): models`

### Wave 2 — Verifier service
- [ ] **2.1** `Services/SourceTargetVerifier.swift` (new): Tier 0/1/2, pure comparators,
  dedicated stdout runner, reuse `buildConcatList`/`probeStreamInfo`. Add
  `sourceTargetVerifier` to `QueueManager`. Pure-comparator unit tests. `xcodegen generate`.
  → commit `feat(verify): SourceTargetVerifier`

### Wave 3 — Trigger wiring
- [ ] **3.1** `QueueManager+Processing.swift` auto-verify hook; repurpose
  `QueueManager+Verification.swift` (`autoVerifyJoin`/`runThoroughVerify`/`verifyJobThorough`/
  `makeVerifierInput`/`mapStatus`). Integration test (skips w/o ffmpeg) + negative case.
  → commit `feat(verify): auto fast-verify + manual thorough wiring`

### Wave 4 — UI
- [ ] **4.1** `Views/QueuePanel.swift` (`QueueRow`): seal badge, `VerificationChip` row,
  "Thorough verify" button + progress, `statusText` "Verifying…", console glyphs.
  → commit `feat(verify): queue seal + chips + thorough button`

### Wave 5 — Verify
- [ ] **5.1** Full test suite green; clean build cycle; live eyeball seal on a real join.
