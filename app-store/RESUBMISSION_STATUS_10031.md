# LumeSync 1.0 (10031) — local remediation status

September 14, 2026. User authorized takeover on `main`. Existing staged recovery work and local review evidence have been preserved. This session has not sent a reviewer reply or resubmitted the app.

## Changes

- Removed the analytics onboarding phase and its consent control. Safety warning now proceeds to completion; welcome-session and Explore App actions remain.
- Fresh-install analytics remain disabled under the existing consent gate. Settings → Privacy & Data → Anonymous Usage Analytics remains available. Existing explicit preferences are preserved.
- Updated app and share-extension build numbers to 10031, confirmed available through App Store Connect.
- Updated both review-notes drafts and replaced the speculative/stale 10031 plan with evidence-based instructions. Policy hosting remains Wix. Existing 10030 recording/sample attachment remains relevant.

## Transport failure diagnosis

The prior full macOS suite failed because the player was still in countdown at the test’s wall-clock deadline. Two isolated runs had passed. We reproduced the full-suite failure twice. Temporary instrumentation confirmed `usesNumericCountdown == false` and just one polling suspension before failure: the nominal 20 ms suspension resumed over 12 seconds later, exceeding the eight-second deadline by 4.20 seconds. The full suite contended for MainActor execution.

The test now allows 400 polling attempts, retains all state-transition assertions, pins a three-second countdown for the VoiceOver fallback, and has a one-minute test limit. Production transport code is unchanged. Temporary instrumentation was removed. The full macOS suite then passed, including the transport test under contention (33.561 seconds).

## Validation — completed September 15, 2026

- **macOS full suite: 1,705 test cases, zero failures** (serial).
- **iOS 26 full suite: 1,706 test cases, zero failures** (serial). This closes the
  gap the earlier entry left open — the iOS run had previously stalled in
  CoreSimulator and was never completed.
- Run both suites with `-parallel-testing-enabled NO`. Under parallel simulator
  load, analysis-pipeline and MainActor-bound tests hit their time limits and
  abort the run; `SystemNowPlayingTransportTests` and `TabBarClearanceTests` each
  flaked this way and both pass in isolation and serially. See ERRORS.md ERR-001.
- Builds succeed on macOS, iOS 26, and iOS 18.5 (the back-compatibility floor).
- Built binary inspected, not just the source: `otool -L` shows **no ARKit
  linkage**, MediaPlayer is linked, and the bundle contains zero
  `ARFaceTracking` / `ARFaceAnchor` / `ReaderAttentionMonitor` strings. Info.plist
  carries no camera or tracking keys; `UIBackgroundModes` is `["audio","processing"]`.
- App and share-extension `CFBundleVersion` both read **10031** in the built bundle.
- `git diff --check`: clean.
- No camera permission, ARKit or ATT symbols found in current app source/project scan.
- Greenlight scanned a copy of tracked current app/project source, excluding old worktrees. Its critical Amplitude/ATT result is a false positive from `AudioEnergyAnalyzer.swift`’s “Near-zero amplitude” comment; the dependency is absent. Its IAP warning is a false positive from StoreKit imported for `requestReview`. No ATT or purchase UI was added to appease these matches. Raw scan: `/tmp/LumeSync-10031-preflight.json`. The scanner itself did not report GREENLIT.

## Completed September 15, 2026

- **Source committed** as `48967e7d` on `main`. Until then the entire 10029/10030
  remediation existed only in `stash@{0}` plus untracked files, and the working
  tree had already silently regressed to the pre-fix state once. That risk is gone.
- **`OnboardingConsentInvariantTests` added** — four source invariants asserting
  onboarding declares no analytics phase, carries no consent copy, never writes
  the analytics preference, and that analytics stay off until Settings enables
  them. Verified to actually fail when a consent screen is reintroduced, rather
  than passing vacuously.
- **App Store Connect review notes updated** to the 10031 text (3,933 characters,
  under Apple's 4,000 limit). The live notes previously still described the
  deleted analytics screen and told the reviewer to interact with it.
- Review attachment confirmed intact: `LumeSync-1.0-10030-Review-Evidence.zip`,
  60,957,681 bytes, COMPLETE.
- `asc validate` for the iOS version: **0 errors, 0 warnings, 0 blocking.**
- Review media (~118 MB of ZIP and MP4) moved to `.gitignore`; the provenance and
  README files stay tracked as the record of what was sent.

## Before submission — still outstanding

1. **Upload build 10031.** App Store Connect's newest build is still 10030, the
   rejected one. Nothing can be resubmitted until 10031 is uploaded and selected.
2. **Confirm App Privacy is published** in the App Store Connect UI. The public
   API cannot verify this and it can silently block submission.
3. **On a physical device**, walk the new onboarding flow end to end and confirm
   Settings → Anonymous Usage Analytics defaults to off and toggles correctly.
4. **Send the reviewer reply**, then resubmit.

Local source edits do not change the rejected 10030 binary. App Review approval
remains Apple's decision; removing the cited screen addresses the cited issue but
does not guarantee acceptance. If 5.1.2(i) is cited a third time, the objection is
unambiguously the Device ID rather than any screen — escalate via the App Review
appointment Apple offers in the rejection message rather than guessing again.
