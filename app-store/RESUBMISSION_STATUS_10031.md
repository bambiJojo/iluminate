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

## Validation

- macOS full suite: 1,691 passed, 10 skipped, zero failures (1,848 passed executions including parameterized cases). Result: `/tmp/LumeSync-takeover-fixed-mac.xcresult`.
- iOS full suite: running; update this entry after completion.
- `git diff --check`: clean.
- No camera permission, ARKit or ATT symbols found in current app source/project scan.
- Greenlight scanned a copy of tracked current app/project source, excluding old worktrees. Its critical Amplitude/ATT result is a false positive from `AudioEnergyAnalyzer.swift`’s “Near-zero amplitude” comment; the dependency is absent. Its IAP warning is a false positive from StoreKit imported for `requestReview`. No ATT or purchase UI was added to appease these matches. Raw scan: `/tmp/LumeSync-10031-preflight.json`. The scanner itself did not report GREENLIT.

## Before submission

Finish platform verification and archive/export. On a physical device, walk the new onboarding flow and verify Settings analytics defaults/opt-in behavior. Review the final uploaded binary and send the updated reply with the existing recording evidence. Local source edits do not change the rejected 10030 binary. App Review approval remains Apple’s decision.
