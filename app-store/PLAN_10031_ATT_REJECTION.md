# LumeSync — build 10031 remediation

Updated September 14, 2026. Work is on `main`; the recovered build 10030 changes are staged. The earlier branch/stash recovery instructions are obsolete.

## Review evidence

Apple rejected build 10030 under guideline 5.1.2(i). Its screenshot shows the onboarding “Anonymous analytics” screen, with an off-by-default toggle and Continue. The other four guidelines from build 10029 are no longer cited in this message; that is not a guarantee of future acceptance.

The screenshot establishes which screen Apple flagged. It does not establish that all analytics consent screens are prohibited, or that the Device ID privacy label caused the decision.

## Implemented change

Remove the analytics screen, state, navigation case and unused helper from `OnboardingView.swift`. The flow is now welcome → questionnaire → personalized response → safety warning → completion. Completion still applies goal preferences and offers the welcome session or Explore App.

Fresh installs keep analytics disabled. `UsageAnalytics` requires both an answered-consent flag and an enabled preference before emitting events. App launch passes that preference to SDK configuration. The existing Settings control remains the place to enable or disable analytics. Existing explicit opt-ins are preserved.

Keep the accurate Device ID and Product Interaction disclosures while TelemetryDeck remains. Do not suppress the dependency’s Device ID manifest or claim that hashed identifiers are not identifiers. TelemetryDeck receives opted-in analytics as a service provider; do not tell Apple that no third party receives them.

Apple explicitly permits IDFV for analytics across apps from the same content provider without ATT, provided it is not combined with other data for cross-company tracking. See [Apple’s user privacy and data use guidance](https://developer.apple.com/app-store/user-privacy-and-data-use/). ATT applicability depends on actual data use, including SDK practices, rather than the presence of an identifier alone.

## Verification and release work

- Transport failure fixed: full-suite MainActor contention exhausted the test’s wall-clock wait after one poll. Bounded polling plus a test-level time limit passes the full macOS suite; production transport code is unchanged.
- Full macOS suite passed: 1,691 tests, 10 skipped, zero failures. iOS simulator verification is in progress; its first test launch stalled in CoreSimulator and was interrupted. See `RESUBMISSION_STATUS_10031.md` for final results.
- Verify fresh-install onboarding and the Settings control on a device before submission.
- App and share-extension build numbers are now 10031 (confirmed unused on App Store Connect). Prepare the archive after source validation. Build 10030 is already rejected; local source changes do not update that binary.
- Retain the existing review attachment containing the physical-device background-audio recording and samples. Apple requested that evidence for future submissions.
- Update App Review notes and reply for the actual uploaded build. Do not claim runtime or archive checks that have not been performed.

## Draft reviewer explanation — review before sending

We removed the onboarding analytics screen shown in Screenshot-0914-141626.png. Fresh installs have optional product analytics disabled. Users can enable or disable analytics in Settings; onboarding does not ask for analytics consent.

LumeSync does not use app data for cross-company advertising or advertising measurement, and does not share data with data brokers. The optional analytics integration is TelemetryDeck. Device ID and Product Interaction remain disclosed for analytics, not linked to identity and not used for tracking. TelemetryDeck receives analytics when enabled; the SDK hashes its vendor-based identifier before transmission. This identifier is not the advertising identifier.

The privacy policy remains hosted on the LumeSync website: https://quineent.wixsite.com/lumesync/privacy-policy. The review attachment continues to include the physical-device background-audio demonstration and sample files.

## Remaining uncertainty

Removing the cited screen addresses the visible prompt issue. App Review may still request further evidence about data practices. Approval cannot be guaranteed. If the same issue persists, request clarification about the specific tracking behavior or SDK practice Apple identified.
