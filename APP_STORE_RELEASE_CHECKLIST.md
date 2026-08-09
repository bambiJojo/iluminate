# LumeSync Unlisted App Store Release Checklist

Last audited: 2026-08-04  
App Store Connect app: [LumeSync (6760121072)](https://appstoreconnect.apple.com/apps/6760121072)  
Intended distribution: Apple's **Unlisted App** distribution (available by direct link, absent from App Store search, charts, categories, and recommendations)

Use this as the release source of truth. Check an item only when there is evidence for it (a tested build, screenshot, URL, App Store Connect state, or written decision).

Legend:

- `[x]` verified during the 2026-08-04 audit
- `[ ]` not complete or not yet verified
- **BLOCKER** must be resolved before submitting to App Review

> Important: an unlisted link is not access control. Anyone who obtains the link can install the app. Unlisted apps must pass the same App Review Guidelines as searchable apps.

## Recommended working order

1. Remove or license the explicit and third-party content/download features.
2. Publish working privacy and support pages, then add them inside the app.
3. Remove medical/therapy positioning and complete the flashing-light safety review.
4. Freeze the launch scope/version and complete device QA.
5. Finish App Store Connect metadata, privacy, rating, screenshots, and build attachment.
6. Submit for review, request unlisted distribution, and release only after Apple marks the app Unlisted.

## Current audit snapshot

- [x] App Store Connect record exists for **LumeSync**, bundle ID `com.byronquine.lumenSync`.
- [x] iOS and macOS version `1.0` records exist in `PREPARE_FOR_SUBMISSION`.
- [x] Primary category is Entertainment; secondary category is Music.
- [x] No in-app purchases or subscriptions are configured or found in the app.
- [x] Optional TelemetryDeck analytics is off until the user opts in.
- [x] The privacy manifest declares no tracking and includes required-reason API declarations.
- [x] `ITSAppUsesNonExemptEncryption` is currently `false`.
- [x] Xcode/SDK meet Apple's current upload requirement (Xcode 26.6, iOS 26.5 SDK observed).
- [x] An unsigned iOS Simulator **Release** build compiled successfully on 2026-08-04.
- [x] An unsigned native macOS **Release** build compiled successfully on 2026-08-04.
- [ ] Resolve the Swift concurrency warnings emitted by the Release build, particularly in `PlaylistLinkBrowserView.swift` and `LibraryBrowseFilter.swift`.
- [ ] Produce and validate a signed App Store archive; a simulator build is not submission evidence.
- [ ] Produce and validate a signed macOS App Store archive if macOS is part of launch scope.
- [ ] Re-run the compliance scanner against the final archive/IPA or a clean checkout. The current source-tree scan is noisy because it scans `.claude/worktrees`, tests, and build products.

Current App Store Connect validation state:

- [ ] **iOS 1.0:** clear all validation findings (audit found 29 errors and 1 warning).
- [ ] **macOS 1.0:** clear all validation findings if shipping it (audit found 33 errors and 1 warning).
- [ ] Reach `asc validate --strict` with zero blocking errors for each platform being submitted.

## 1. Lock the launch plan

- [ ] **BLOCKER — choose launch platforms:** ship iOS/iPadOS first (recommended), or include macOS in the initial submission.
- [ ] If shipping iOS/iPadOS first, leave the macOS version unsubmitted and create a separate Mac release plan.
- [ ] **BLOCKER — choose the marketing version.** Recommended: change the app to `1.0` to match the existing App Store version record.
- [ ] Increment the build number above the uploaded build `10018` and use a consistent version/build across the app and share extension.
- [ ] Note that the existing TestFlight build `0.7.4 (10018)` is valid and beta-review approved but cannot be selected for the `1.0` App Store version because its marketing version does not match.
- [ ] Decide whether the app is free or paid. If paid, complete contracts, tax, banking, and pricing work before submission.
- [ ] Decide the countries/regions where the app will be available.
- [ ] Define the intended unlisted audience and write a short, specific justification for Apple (for example, members of a named organization or event).
- [ ] Confirm that direct-link access is sufficient. If membership must be private, add authentication/authorization or choose Apple Business Manager/Apple School Manager custom distribution instead.
- [ ] Keep App Store release control set to **manual** so the app cannot accidentally become publicly searchable before the unlisted request is approved.
- [ ] Freeze the release branch/commit after blockers are fixed and record the commit SHA here: `________________`.
- [ ] Reconcile or intentionally preserve every pre-existing dirty-worktree change before archiving.

## 2. Explicit content and App Review policy

- [ ] **BLOCKER — remove the curated adult/pornographic source directory from the App Store build.** `ReadingSource.swift` currently links directly to erotic-hypnosis and pornographic sites.
- [ ] **BLOCKER — remove the in-app `Show Adult Content (18+)` switch and any code path that enables those sources.** An 18+ acknowledgement does not make pornographic material acceptable under App Review Guideline 1.1.4.
- [ ] **BLOCKER — remove or replace `Ilumionate/KnownAudioCatalog.json`.** The audited iOS and macOS Release apps both bundle this 811 KB catalog, and it contains explicit third-party sexual transcripts and metadata.
- [ ] Confirm the final archive contains no explicit transcripts, sample text, thumbnails, cached pages, test data, search suggestions, or links intended to lead users to pornographic content.
- [ ] Confirm screenshots, preview videos, metadata, reviewer notes, and sample files contain no prohibited explicit content.
- [ ] Do not treat unlisted distribution or a high age rating as an exception to Apple's content rules.
- [ ] If users can still encounter mature material incidentally through general web access, hide it by default, add suitable controls, and document the exact behavior for review. Obtain specialist policy advice before relying on the narrow web-content exception.

## 3. Third-party content, intellectual property, and downloads

- [ ] **BLOCKER — inventory every third-party item shipped or accessed:** transcripts, audio, scripts, titles, creator names, metadata, artwork, icons, fonts, websites, APIs, and model assets.
- [ ] Record the license or written permission for every retained third-party asset and keep proof ready for App Review.
- [ ] Remove third-party transcripts or metadata for which redistribution rights cannot be demonstrated.
- [ ] Review the BambiCloud playlist importer/downloader and obtain written authorization for downloading/streaming its media, or remove/disable the flow in the App Store build.
- [ ] Review SoundCloud integration against SoundCloud's current developer and content terms; obtain any required authorization or remove/disable it.
- [ ] Review the in-app browser's arbitrary audio download/import behavior. Remove the ability to save third-party media unless the relevant service and rights holder explicitly authorize it.
- [ ] Decide whether to remove or tightly restrict the general-purpose browser. If retained, test navigation safety, download restrictions, fraudulent/deceptive pages, and external-link handling.
- [ ] Set App Store Connect **Content Rights** truthfully:
  - [ ] Select that the app uses third-party content if any third-party content/service remains.
  - [ ] Select that it does not only after the final rights audit proves that statement.
- [ ] Add authorization documents and explanatory notes to App Review when a retained service could appear to violate Guideline 5.2.2 or 5.2.3.
- [ ] Verify app name, icon, screenshots, metadata, and domains do not infringe another party's trademarks or copyrights.

## 4. Recreational positioning and claim removal

- [x] **Product decision:** LumeSync is purely recreational/entertainment software. It does not provide medical care, therapy, diagnosis, treatment, prevention, health monitoring, or guaranteed mental/physical outcomes.
- [ ] **BLOCKER — remove every user-facing medical, therapy, wellness-treatment, or physiological-effect claim.** We will not retain or attempt to substantiate such claims.
- [ ] Remove or replace these audited examples:
  - [ ] “syncing your brainwaves” for “deep restorative sleep”
  - [ ] “synchronize your brain, safely guiding your mental state”
  - [ ] “washing away stress”
  - [ ] “light therapy” and “therapy recommendations”
  - [ ] treatment-like session labels such as `Anxiety Dissolve` and `Insomnia`
  - [ ] claims such as “serotonin production,” “anti-anxiety,” “optimal focus,” “healing,” “entrainment,” or named frequency bands causing a particular state
- [ ] Audit and rewrite user-visible strings in at least `Models/OnboardingData.swift`, `welcome_introduction.json`, `AnalysisProgressView.swift`, `StreamingSettingsView.swift`, `AnalyzerConfig/AnalyzerConfig.swift`, `AnalysisPreferences.swift`, `LightSession+Metadata.swift`, bundled session JSON, and any generated-analysis output.
- [ ] Ensure internal enum/phase names such as `therapy` or `brainwave` never leak into UI, accessibility labels, notifications, logs shown to users, exported files, generated copy, or App Review screenshots. Rename internal terminology where that is the safest way to prevent leakage.
- [ ] Describe only observable features: user-selected audio playback, audio-reactive visuals, adjustable light patterns, reading tools, and recreational sessions.
- [ ] Do not claim that a frequency, binaural beat, visual pattern, hypnosis feature, or session changes brainwaves, sleep, stress, anxiety, focus, mood, health, or mental state.
- [ ] Do not use “safe” or “safely” as a product-performance claim. Safety warnings and risk-reduction controls may be described factually without guaranteeing safety.
- [ ] Keep App Store metadata, onboarding, in-app copy, website, screenshots, support material, privacy policy, generated text, and reviewer notes consistent with entertainment-only use.
- [ ] Retain a concise disclaimer: “LumeSync is a recreational entertainment experience, not medical care or therapy.” Do not rely on the disclaimer to neutralize conflicting claims elsewhere.
- [ ] Select no medical-device or health functionality in App Store Connect unless the final shipping behavior genuinely requires otherwise; answer every questionnaire based on the final binary.
- [ ] Run a final case-insensitive release-string scan for `therapy`, `therapeutic`, `medical`, `treat`, `diagnose`, `cure`, `prevent`, `healing`, `anxiety`, `insomnia`, `brainwave`, `entrainment`, and similar claims, then manually review every match.

## 5. Flashing-light and physical-safety gate

- [ ] **BLOCKER — complete a documented photosensitivity/seizure-risk review of every flashing or brightness-changing mode.** Apple may reject apps that risk physical harm.
- [ ] Require a clear first-use safety acknowledgement before any flashing feature can start.
- [ ] Show an immediately visible warning at every entry point that can start flashing, not only during onboarding.
- [ ] Warn people with epilepsy, seizure history, photosensitivity, migraines, or related concerns not to use flashing modes without appropriate medical guidance.
- [ ] Warn users not to use the experience while driving, operating machinery, or in another unsafe setting.
- [ ] Provide an obvious, always-available stop/pause control and verify it works during every visual state.
- [ ] Verify app backgrounding, phone calls, audio interruptions, crashes, and scene changes stop flashing and restore the user's prior screen brightness.
- [ ] Verify conservative default intensity/frequency values and enforce safe upper bounds in `LightSafety` and all alternate visual engines.
- [ ] Measure and document actual flash frequency, contrast, duty cycle, full-screen brightness changes, red-flash behavior, and transitions on physical devices.
- [ ] Confirm Reduce Motion and other accessibility settings produce an appropriately reduced experience.
- [ ] Test warnings and safety controls on iPhone and iPad, in light/dark environments, with brightness and Reduce White Point variations.
- [ ] Put the safety flow and stop control in App Review notes so the reviewer can test without surprise.
- [ ] Keep the existing flashing-light warning visible in App Store description/screenshot context where appropriate.

## 6. Privacy, analytics, permissions, and security

### Public privacy/support presence

- [ ] **BLOCKER — publish the privacy policy at a stable HTTPS URL.** The repository has `PRIVACY_POLICY.md`, but `ilumionate.app` did not resolve during this audit.
- [ ] **BLOCKER — publish a working Support URL** with app name, contact method, basic help, and response expectations.
- [ ] **BLOCKER — make `support@ilumionate.app` deliverable**, or replace it everywhere with a working address.
- [ ] Add an easy-to-find in-app Privacy Policy link (Settings/About and any consent screen).
- [ ] Add an easy-to-find in-app Support link; do not rely only on a `mailto:` action.
- [ ] Confirm Privacy Policy and Support URLs load on-device without authentication, redirects to broken pages, TLS errors, or region restrictions.

### Privacy policy and App Privacy label

- [ ] Reconcile `PRIVACY_POLICY.md` with the exact final release behavior and publish the same current text online.
- [ ] Describe local audio, transcripts, imported documents, reading state, settings, camera attention monitoring, model downloads, browser/network access, retention, deletion, and support contact accurately.
- [ ] If external integrations remain, name their roles and explain what URLs/metadata/content are sent to them.
- [ ] Confirm TelemetryDeck behavior in a release build. Expected declaration from the current SDK/configuration:
  - [ ] Product Interaction: collected for Analytics, not linked to the user, not used for tracking.
  - [ ] Device ID/app-install identifier: collected for Analytics, not linked to the user, not used for tracking.
- [ ] Verify no analytics event is emitted before explicit opt-in.
- [ ] Verify turning analytics off stops future transmission and that the consent choice persists correctly.
- [ ] Capture release-build network traffic for opt-out and opt-in sessions and reconcile every endpoint with the policy and App Privacy answers.
- [ ] Do not show an AppTrackingTransparency prompt unless behavior changes to cross-app/company tracking. Re-audit if a new advertising, attribution, or tracking SDK is added.
- [ ] Complete and **publish** App Privacy answers in App Store Connect; the public API could not verify a published privacy state during this audit.
- [ ] Recheck privacy answers whenever code, SDKs, endpoints, or data practices change.

### Privacy manifests and required-reason APIs

- [x] The app privacy manifest currently declares no tracking and declares Product Interaction for App Functionality.
- [x] The app manifest currently lists required reasons for UserDefaults, file timestamps, and system boot time APIs.
- [x] TelemetryDeck 2.14.1 includes its own privacy manifest.
- [ ] Generate the archive privacy report and inspect the **merged** app/extension/SDK declaration.
- [ ] Verify every required-reason API used by the final binary has an approved reason matching actual behavior.
- [ ] Verify all third-party SDKs are current, signed where required, and include valid privacy manifests.
- [ ] Remove unused SDKs and dependencies before archiving.

### Permissions, retention, and security

- [ ] Confirm the camera is requested only when the user intentionally enables attention monitoring, with a just-in-time explanation before the system prompt.
- [ ] Verify camera frames/biometric observations remain on-device, are not saved, and stop when the feature/session stops.
- [ ] Remove the Speech Recognition usage description if no shipping feature uses Apple's Speech framework; otherwise test the permission flow and document its purpose accurately.
- [ ] Audit the final binary for every protected-resource API and ensure each corresponding purpose string is specific and accurate.
- [ ] Test all features after permission denial, restriction, and later Settings changes; the app must remain usable and explain degraded behavior.
- [ ] Verify “clear/delete all” removes local audio, transcripts, imported documents, generated sessions, caches, browser data where promised, and analytics identifiers where applicable.
- [x] No user account system was found; Apple's in-app account-deletion requirement is therefore not applicable unless accounts are added.
- [ ] Verify sensitive user content is stored with appropriate iOS/macOS file protection and excluded from backups where appropriate.
- [ ] Review logs, crash reports, and analytics payloads to ensure they never contain transcript text, local filenames, imported URLs, credentials, tokens, or other sensitive content.
- [ ] Audit Keychain handling and remove any bundled API keys, developer credentials, test accounts, or secrets.
- [ ] Remove `NSAllowsArbitraryLoadsInWebContent` or document why it is narrowly necessary; prefer HTTPS and a restricted navigation policy.
- [ ] Verify SoundCloud or other credentials are never logged, included in screenshots, sent to unrelated services, or left in plaintext storage.
- [ ] Confirm `BGTaskSchedulerPermittedIdentifiers`, background modes (`audio`, `processing`), app groups, camera, network, and file entitlements are all required and used exactly as declared.
- [ ] Document why export compliance is exempt/non-exempt and confirm `ITSAppUsesNonExemptEncryption = false` remains accurate for the final binary and dependencies.

## 7. Age rating and parental/content controls

- [ ] Complete the current App Store Connect age-rating questionnaire only after explicit-content and browser decisions are final.
- [ ] Do **not** reuse the old 4+ assumption; it is incompatible with the current pre-cleanup claims, flashing content, unrestricted web access, and adult-content code.
- [ ] If the general-purpose browser remains, answer **Unrestricted Web Access = Yes**.
- [ ] After section 4 is complete, verify the final app no longer presents medical, health, or therapy functionality; answer all rating questions from the final binary rather than the product intention.
- [ ] Answer fear, mature themes, sexual content, and all other content-frequency questions based on what a user can actually encounter.
- [ ] If explicit/pornographic content remains, stop submission and remove it; a higher rating does not cure Guideline 1.1.4.
- [ ] Verify parental controls, mature-content defaults, and website restrictions behave consistently on all supported platforms.
- [ ] Confirm the resulting rating is consistent across metadata, screenshots, website, and reviewer notes.

## 8. Engineering release quality

### Build and archive

- [ ] Remove all blocker content and create a clean release candidate from the frozen commit.
- [ ] Set final `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for app and extensions.
- [ ] Verify display name, bundle IDs, signing team, app groups, entitlements, capabilities, deployment targets, and provisioning profiles.
- [ ] Create signed **Release** archives for every submitted platform using the current required Xcode/SDK.
- [ ] Run Xcode Organizer/App Store validation and resolve every error and actionable warning.
- [ ] Inspect the archived `.app`, not only the source tree, for prohibited/test assets, explicit catalog data, secrets, sample credentials, debug menus, and oversized resources.
- [ ] Verify dSYMs and symbol files are included/uploaded for crash symbolication.
- [ ] Verify bitcode-related settings and legacy submission configuration are not present where unsupported.
- [ ] Check archive and install size, including WhisperKit/model behavior; disclose any large post-install model download before it starts.

### Automated tests and static checks

- [ ] Run the complete iOS unit-test suite in Release-compatible conditions and record the result/date.
- [ ] Run the macOS unit-test suite if macOS is shipping.
- [ ] Run UI tests for onboarding, consent, import, analysis, reading, playback, flashing safety, Settings, and deletion.
- [ ] Run Swift concurrency/static analysis and fix data-race, main-actor, force-unwrap, and crash findings that affect release paths.
- [ ] Re-run Greenlight/compliance scanning on the final archive or clean checkout; manually disposition every finding with evidence.
- [ ] Run dependency/vulnerability and license checks for Swift packages and model assets.
- [ ] Run `git diff --check` and ensure the release commit contains no merge markers, generated junk, or accidentally committed secrets.

### Device and scenario QA

- [ ] Test a fresh install on physical iPhone and iPad devices supported by the deployment target.
- [ ] Test update from the latest TestFlight build while preserving compatible user data.
- [ ] Test portrait/landscape, Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, Increased Contrast, and keyboard navigation where applicable.
- [ ] Test offline mode, slow/interrupted network, low storage, low memory, low battery, thermal pressure, and background/foreground transitions.
- [ ] Test audio routes: speaker, headphones, Bluetooth, AirPlay where supported, route changes, phone calls, Siri, alarms, and Control Center interruptions.
- [ ] Test audio import, document import, share extension, large files, corrupt/unsupported files, duplicate imports, cancellation, and deletion.
- [ ] Test Whisper/model download failure, retry, cancellation, storage requirements, airplane mode, and first-run latency.
- [ ] Test every browser/external-service flow retained in the release with invalid links, redirects, authentication failure, and service downtime.
- [ ] Test all permission states: not determined, allow, deny, restricted, and later changed in Settings.
- [ ] Test repeated launch/termination for crashes, hangs, data corruption, leaked brightness, stuck audio, and unfinished background tasks.
- [ ] Profile launch time, memory, CPU, energy, animations, audio synchronization, and long-session thermal behavior.
- [ ] Run a no-debugger TestFlight smoke test of the exact candidate build before App Store submission.
- [ ] Have at least one person who did not build the feature complete the full first-run and reviewer journey.

### Accessibility declarations

- [ ] Test any accessibility features before claiming them in App Store Connect.
- [ ] Add truthful Accessibility Nutrition Labels for iPhone/iPad and Mac if shipping. These are currently voluntary, but Apple says they will become required over time.
- [ ] Do not claim VoiceOver, Voice Control, Larger Text, sufficient contrast, reduced motion, captions, or other support until the complete core experience passes that criterion.

## 9. Store assets and metadata

### App-wide information

- [x] App name: `LumeSync`.
- [x] Bundle ID: `com.byronquine.lumenSync`.
- [x] Primary category: Entertainment; secondary: Music.
- [ ] Confirm primary language and all localization choices.
- [ ] Enter and publish the live Privacy Policy URL.
- [ ] Complete the Content Rights declaration after the rights audit.
- [ ] Complete the age-rating questionnaire after content cleanup.
- [ ] Complete EU Digital Services Act trader/non-trader status and provide any required public contact information.
- [ ] Review App Store agreements and business/contact information; resolve any account-level banners or expiring agreements.

### iOS/iPadOS 1.0

- [x] Existing description, keywords, subtitle, and categories are substantially aligned with an entertainment positioning and already state that the app is not medical treatment.
- [ ] Re-review all copy after the claims/content changes; remove any feature no longer present in the App Store build.
- [ ] Enter a working Support URL.
- [ ] Confirm subtitle, description, keywords, promotional text (optional), copyright, and version text.
- [ ] Supply current App Store Connect-required iPhone screenshots (1–10 per required set) showing the real shipping UI.
- [ ] Supply current App Store Connect-required iPad screenshots because the app supports iPad.
- [ ] Use only genuine in-app UI in screenshots; disclose flashing-light behavior clearly and avoid prohibited content or unverifiable claims.
- [ ] Add an app preview video only if it improves review/listing quality; it is optional and must show actual app use.

### macOS 1.0, if included

- [ ] Enter description and keywords (currently missing).
- [ ] Enter copyright (currently missing).
- [ ] Enter a working Support URL and the shared Privacy Policy URL.
- [ ] Supply required Mac screenshots of the real shipping app.
- [ ] Complete Mac App Review contact/details and all other platform metadata.
- [ ] Verify Mac App Sandbox, user-selected file access, camera, network client, and app-group entitlements against actual features.
- [ ] Test Mac menu commands, keyboard access, window resizing, full screen, file import, audio routes, camera denial, sandbox access, and app relaunch.

### Metadata quality check

- [ ] Verify every screenshot/caption and every metadata claim matches the submitted binary.
- [ ] Remove “beta,” placeholders, old product names, test text, pricing claims, unsupported platform claims, and references to hidden features.
- [ ] Confirm URLs, email addresses, legal entity name, copyright year, and spelling.
- [ ] Confirm the icon and screenshots remain legible and accurate in light/dark storefront contexts.
- [ ] Have a second person proofread the final storefront and safety/privacy copy.

## 10. Pricing, availability, and distribution

- [ ] Create the missing Pricing and Availability resource in App Store Connect.
- [ ] Set price (likely Free) and verify any agreements required by that choice.
- [ ] Select intended countries/regions and confirm local legal/content availability.
- [ ] Set distribution method to **Public** before submitting the unlisted-app request, as Apple requires.
- [ ] Keep release type **Manual** for every platform/version involved.
- [ ] Do not select Private/custom distribution unless changing away from the unlisted plan.
- [ ] Confirm the app is not already publicly released/searchable before Apple approves the unlisted request.

## 11. Select the final build

- [ ] Upload a new build whose marketing version exactly matches the App Store version (`1.0` if following the recommendation).
- [ ] Use a build number higher than `10018`.
- [ ] Wait for processing and resolve export compliance, privacy manifest, signing, asset, or SDK warnings.
- [ ] Confirm the processed build reports `usesNonExemptEncryption = false` only if the documented exemption remains correct.
- [ ] Complete TestFlight smoke testing with the exact uploaded build.
- [ ] Attach the build to the iOS 1.0 version.
- [ ] Upload, test, and attach a matching macOS build only if Mac is in launch scope.
- [ ] Run strict App Store Connect validation again after build attachment.

## 12. App Review information

- [ ] Enter a monitored review contact name, phone, and email.
- [ ] State that no account/login is required. If that changes, provide a durable full-access demo account and keep it active through review.
- [ ] Attach or provide a small, rights-cleared sample audio/text file so the reviewer can exercise import, analysis, reading, and playback without third-party content.
- [ ] Give concise steps to reach every non-obvious feature: imports, share extension, camera attention monitoring, analysis/model download, reading mode, audio-reactive visuals, and flashing-light controls.
- [ ] Explain any first-run model download, its approximate size/time, and what the reviewer should expect.
- [ ] Explain that optional TelemetryDeck analytics defaults off and how to inspect the consent toggle.
- [ ] Explain on-device processing and what data, if any, leaves the device.
- [ ] Explain the flashing-light warning, acknowledgement, conservative defaults, and emergency stop.
- [ ] Explain background audio/processing modes and why they are required.
- [ ] Declare all retained third-party services and attach permissions/authorizations where needed.
- [ ] Disclose feature flags, region/device limitations, special hardware requirements, and temporary service dependencies.
- [ ] Explicitly write in **Review Notes** that the app is intended for **unlisted distribution** and identify its limited audience/use case.
- [ ] Ensure review notes do not rely on contacting the developer for basic access or missing instructions.

## 13. Submission and unlisted-request sequence

Follow this order exactly to avoid accidentally publishing a searchable app:

- [ ] Confirm every **BLOCKER** above is checked.
- [ ] Confirm Pricing and Availability is configured as **Public** distribution and release remains **Manual**.
- [ ] Confirm the final build, privacy answers, age rating, content rights, URLs, screenshots, and review information are complete.
- [ ] Run `asc validate --strict` and save the zero-blocker output with the release records.
- [ ] Submit the app/version to App Review.
- [ ] Confirm Review Notes say the app is intended for unlisted distribution.
- [ ] Immediately submit Apple's separate [Unlisted App Distribution Request](https://developer.apple.com/contact/request/unlisted-app/) using an Account Holder, Admin, or App Manager account.
- [ ] Monitor both the App Review submission and the unlisted-distribution request; answer Apple promptly and consistently.
- [ ] **Do not manually release the approved app while distribution still says Public.**
- [ ] Wait until Apple approves the unlisted request and App Store Connect shows distribution as **Unlisted**.
- [ ] Manually release only after the Unlisted state is confirmed.
- [ ] Test the generated direct App Store link on signed-out devices and in every intended country/region.
- [ ] Confirm the app is installable from the link and absent from App Store search, charts, categories, and recommendations.
- [ ] If access is meant to be restricted, test the app's own authorization; secrecy of the App Store link is not sufficient.
- [ ] Share the final link only through the intended audience channel and record who owns future link/access support.

## 14. Post-release readiness

- [ ] Prepare a support runbook for install problems, camera/audio permissions, imports, model downloads, safety concerns, deletion, and privacy requests.
- [ ] Assign owners for App Store Connect, review communication, privacy, security, safety incidents, and customer support.
- [ ] Monitor crashes, hangs, launch failures, model-download failures, and support contacts after release.
- [ ] Verify TelemetryDeck receives data only from opted-in users and never receives sensitive content.
- [ ] Create a rapid kill-switch/update plan for unsafe flashing behavior or a compromised third-party integration.
- [ ] Keep the direct-link landing/support page current and test it periodically.
- [ ] Re-test that the app remains unlisted after every metadata/version change.
- [ ] Treat future versions as unlisted, but still complete normal App Review, privacy, rating, rights, QA, and release checks.
- [ ] Update the privacy policy and App Privacy answers before—not after—shipping any new data collection or SDK.
- [ ] Track dependency/security updates, Apple SDK deadlines, certificate/profile changes, agreements, and Developer Program renewal.
- [ ] Archive the submitted source SHA, Xcode version, archive, dSYMs, privacy report, test evidence, screenshots, metadata, authorizations, validation output, review notes, and final direct link.

## Final go/no-go sign-off

- [ ] Product/content owner: `________________` Date: `__________`
- [ ] Engineering/QA owner: `________________` Date: `__________`
- [ ] Privacy/legal/rights owner: `________________` Date: `__________`
- [ ] App Store Connect owner: `________________` Date: `__________`
- [ ] Final decision: `[ ] GO` `[ ] NO-GO`
- [ ] Submitted build/version: `________________`
- [ ] Release commit SHA: `________________`
- [ ] App Review submission ID: `________________`
- [ ] Unlisted request confirmation: `________________`
- [ ] Final unlisted App Store link: `________________`

## Authoritative references

- [Apple: Unlisted app distribution](https://developer.apple.com/support/unlisted-app-distribution/)
- [Apple: Set distribution methods](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/set-distribution-methods)
- [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple: Required, localizable, and editable properties](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/)
- [Apple: Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Apple: Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Apple: User privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [Apple: Set an app age rating](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)
- [Apple: Age-rating values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/)
- [Apple: Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)
- [Apple: Upcoming SDK minimum requirements](https://developer.apple.com/news/?id=ueeok6yw)
- [TelemetryDeck: Privacy FAQ](https://telemetrydeck.com/docs/guides/privacy-faq/)
