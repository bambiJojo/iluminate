# LumeSync Unlisted App Store Release Checklist

Last audited: 2026-09-01
App Store Connect app: [LumeSync (6760121072)](https://appstoreconnect.apple.com/apps/6760121072)  
Intended distribution: Apple's **Unlisted App** distribution (available by direct link, absent from App Store search, charts, categories, and recommendations)

Use this as the release source of truth. Check an item only when there is evidence for it (a tested build, screenshot, URL, App Store Connect state, or written decision).

Legend:

- `[x]` verified during an audit or release check recorded in this file
- `[ ]` not complete or not yet verified
- **BLOCKER** must be resolved before submitting to App Review

> Important: an unlisted link is not access control. Anyone who obtains the link can install the app. Unlisted apps must pass the same App Review Guidelines as searchable apps.

## Recommended working order

1. Remove unlicensed bundled content and unauthorized third-party download paths; retain the
   user-requested adult analysis features and disclose/rate them accurately.
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
- [x] An unsigned iOS 18.5 Simulator **Release** build compiled without diagnostics on 2026-08-31.
- [x] An unsigned native macOS **Release** build compiled successfully on 2026-08-04.
- [x] The iOS Release build emits no Swift warnings. LumeLabel still has one Swift 6 isolation warning, but macOS tooling is outside the iOS-first launch scope.
- [x] A signed iOS App Store archive was produced and exported successfully on 2026-09-01; App Store Connect accepted build `1.0 (10027)` and reports it `VALID`.
- [ ] Produce and validate a signed macOS App Store archive if macOS is part of launch scope.
- [x] Ran Greenlight against the exact build `10027` IPA: no critical findings. Its launch-storyboard warning is a false positive because the archived app has a modern `UILaunchScreen` dictionary.

Current App Store Connect validation state:

- [ ] **iOS 1.0:** clear the sole remaining strict-validation blocker: storefront availability. Support URL, Privacy Policy URL, screenshots, age declarations, and build attachment are populated.
- [ ] **macOS 1.0:** clear all validation findings if shipping it (audit found 33 errors and 1 warning).
- [ ] Reach `asc validate --strict` with zero blocking errors for each platform being submitted.

## 1. Lock the launch plan

- [x] **Launch decision:** ship iOS/iPadOS first; macOS is not part of this release gate.
- [x] Leave the macOS version unsubmitted and create a separate Mac release plan later.
- [x] Marketing version is `1.0`, matching the existing App Store version record.
- [x] Build number is `10027` for both the app and share extension; this exact build is uploaded, valid, and attached to iOS version `1.0` in App Store Connect.
- [x] The older TestFlight builds `0.7.4 (10018)`, `1.0 (10024)`, and `1.0 (10026)` are superseded by build `1.0 (10027)`.
- [ ] Decide whether the app is free or paid. If paid, complete contracts, tax, banking, and pricing work before submission.
- [ ] Decide the countries/regions where the app will be available.
- [ ] Define the intended unlisted audience and write a short, specific justification for Apple (for example, members of a named organization or event).
- [ ] Confirm that direct-link access is sufficient. If membership must be private, add authentication/authorization or choose Apple Business Manager/Apple School Manager custom distribution instead.
- [x] App Store release control is set to **manual** so the app cannot accidentally become publicly searchable before the unlisted request is approved.
- [ ] Freeze the release branch/commit after blockers are fixed and record the commit SHA here: `________________`.
- [ ] Reconcile or intentionally preserve every pre-existing dirty-worktree change before archiving.

## 2. Explicit content and App Review policy

- [x] Removed the curated reading-source directory. `ReadingSourceCatalog.curatedSources` is empty and the app contains no named adult-story sites or site adapters.
- [x] Removed the retired `Show Adult Content (18+)` source switch. Only one migration key remains so old installs forget the setting.
- [x] Deleted `Ilumionate/KnownAudioCatalog.json`; the 2026-08-31 Release product contains no catalog resource or its third-party titles/transcripts.
- [ ] **POLICY RISK — adult analysis remains by product decision.** The binary and UI include labels such as `Erotic Hypnosis` / `Erotic Suggestions`, and `AnalyzerKnowledge_default.json` contains aggregate adult phrase vocabulary that can appear in Phrase Library. Preserve this functionality, but do not claim the archive contains no explicit strings.
- [x] Inspected build `10027`: it contains no known-audio catalog resource, known third-party titles, bundled third-party explicit transcripts/stories, named adult-site links, or curated explicit media. Inert `KnownAudioCatalog` type names and retired SoundCloud credential-cleanup keys remain in the executable; adult/hypnosis classification resources intentionally remain.
- [x] The uploaded iPhone/iPad screenshots, App Store metadata, and reviewer notes contain no explicit sample content or links to adult websites.
- [ ] Do not treat unlisted distribution or a high age rating as an exception to Apple's content rules.
- [ ] **BLOCKER — obtain specialist policy advice for the retained adult analysis and user-added web sources.** Apple's current [Guideline 1.1.4/1.2](https://developer.apple.com/app-store/review/guidelines/) exception for incidental mature web UGC says it must be hidden by default and enabled via the developer's website; this app intentionally has no account or website control plane.

## 3. Third-party content, intellectual property, and downloads

- [ ] **BLOCKER — inventory every third-party item shipped or accessed:** transcripts, audio, scripts, titles, creator names, metadata, artwork, icons, fonts, websites, APIs, and model assets.
- [ ] Record the license or written permission for every retained third-party asset and keep proof ready for App Review.
- [ ] Remove third-party transcripts or metadata for which redistribution rights cannot be demonstrated.
- [x] Removed the named BambiCloud integration, schemas, fixtures, and curated host knowledge. Generic playlist parsing remains.
- [x] Removed the SoundCloud integration; startup only deletes credentials left by older builds.
- [ ] **BLOCKER — direct audio URL and generic playlist-track downloads still save third-party media.** Apple Guideline 5.2.3 requires explicit authorization from those sources; a user rights acknowledgement alone does not establish source authorization.
- [x] Reader web access is retained as user-managed Custom Sources: no websites are preloaded or recommended, navigation is limited to HTTP(S), downloads/non-displayable responses are blocked, and importing requires a separate rights acknowledgement on the visible current page.
- [ ] Set App Store Connect **Content Rights** truthfully:
  - [x] Selected that the app uses third-party content because user-added web sources and imported media remain.
  - [ ] Select that it does not only after the final rights audit proves that statement.
- [ ] Add authorization documents and explanatory notes to App Review when a retained service could appear to violate Guideline 5.2.2 or 5.2.3.
- [ ] Verify app name, icon, screenshots, metadata, and domains do not infringe another party's trademarks or copyrights.

## 4. Recreational positioning and claim removal

- [x] **Product decision:** LumeSync is purely recreational/entertainment software. It does not provide medical care, therapy, diagnosis, treatment, prevention, health monitoring, or guaranteed mental/physical outcomes.
- [x] Removed user-facing medical, therapy-treatment, and physiological-effect claims while preserving hypnosis and mature-content classification features.
- [x] Removed or replaced these audited examples:
  - [x] “syncing your brainwaves” for “deep restorative sleep”
  - [x] “synchronize your brain, safely guiding your mental state”
  - [x] “washing away stress”
  - [x] “light therapy” and “therapy recommendations”
  - [x] treatment-like session labels such as `Anxiety Dissolve` and `Insomnia`
  - [x] claims such as “serotonin production,” “anti-anxiety,” “optimal focus,” “healing,” “entrainment,” or named frequency bands causing a particular state
- [x] Audited and rewrote user-visible onboarding, analysis preferences/status, generated-analysis prompts and fallbacks, session metadata, bundled session names, and bundled text scripts.
- [ ] Ensure internal enum/phase names such as `therapy` or `brainwave` never leak into UI, accessibility labels, notifications, logs shown to users, exported files, generated copy, or App Review screenshots. Rename internal terminology where that is the safest way to prevent leakage.
- [x] Describe only observable features: user-selected audio playback, audio-reactive visuals, adjustable light patterns, reading tools, and recreational sessions.
- [x] Removed claims that a frequency, binaural beat, visual pattern, hypnosis feature, or session changes brainwaves, sleep, stress, anxiety, focus, mood, health, or mental state.
- [x] Removed “safe” and “safely” as product-performance claims. Safety warnings and risk-reduction controls are described factually without guaranteeing safety.
- [ ] Keep App Store metadata, onboarding, in-app copy, website, screenshots, support material, privacy policy, generated text, and reviewer notes consistent with entertainment-only use.
- [x] Retained the concise disclaimer: “LumeSync is a recreational entertainment experience, not medical care or therapy.”
- [x] App Store Connect's medical/treatment age-rating declaration is `NONE`; health/wellness topics remain declared because the app's subject matter requires that truthful answer.
- [x] Ran the retired-claim scan against the exact build `10027` archive on 2026-09-01. Exact removed claims were absent; internal `brainwaveentrainment` / `EntrainmentBackground` symbol names and the adult/hypnosis classification resources are intentional and are not user-facing claims.

## 5. Flashing-light and physical-safety gate

- [x] Completed a code-path review of every mode that drives `LightEngine` or `FlashController`; tests require each path to have a safety gate. Physical-device flash measurement remains a blocker below.
- [x] Require a clear first-use safety acknowledgement before any flashing feature can start. Audio Light Sync has a separate acknowledgement because it starts with lights disabled.
- [x] Route every entry point that can start full-screen flashing through the shared acknowledgement gate or the separate Audio Light Sync gate.
- [x] Warn people with photosensitivity, epilepsy or seizure history, light-triggered migraines, or another light-sensitive condition not to use flashing modes.
- [x] Warn users not to use the experience while driving, operating machinery, or anywhere they cannot stop immediately.
- [x] The unified player exposes Close/Pause while full controls are visible and a persistent, text-labelled **Stop session** control after they hide. The stop path was unit-tested and exercised live in a flashing session on iPadOS 18.5 on 2026-09-01.
- [ ] Verify app backgrounding, phone calls, audio interruptions, crashes, and scene changes stop flashing and restore the user's prior screen brightness.
- [x] Enforce a conservative 3 Hz full-screen ceiling in `LightSafety`, generated sessions, UI ranges, `LightEngine`, and `FlashController`. Direct engine/controller and invalid-input tests pass. This follows the simple three-flashes-per-second W3C boundary because the full-screen output has not been certified with a flash-analysis tool.
- [ ] Measure and document actual flash frequency, contrast, duty cycle, full-screen brightness changes, red-flash behavior, and transitions on physical devices.
- [ ] Confirm Reduce Motion and other accessibility settings produce an appropriately reduced experience.
- [ ] Test warnings and safety controls on iPhone and iPad, in light/dark environments, with brightness and Reduce White Point variations.
- [x] App Review notes describe the safety acknowledgement, Close behavior, and persistent **Stop session** control.
- [ ] Keep the existing flashing-light warning visible in App Store description/screenshot context where appropriate.

## 6. Privacy, analytics, permissions, and security

### Public privacy/support presence

- [x] App Store Connect Privacy Policy URL points to the public policy on the project's GitHub repository; it returned HTTP 200 without authentication on 2026-09-01.
- [x] App Store Connect Support URL points to the project's public GitHub Issues page; it returned HTTP 200 without authentication on 2026-09-01.
- [x] Published the updated `PRIVACY_POLICY.md` at GitHub commit `bb0c18b`; the live policy and shipping app both use the public Issues workflow and no longer reference `support@ilumionate.app`.
- [x] Added an easy-to-find in-app Privacy Policy link in Settings.
- [x] Added an easy-to-find in-app Help & Support link in Settings; it no longer relies on a `mailto:` action.
- [x] Verified both in-app links on iPadOS 18.5 on 2026-09-01; Safari opened the exact public HTTPS destinations without an authentication gate or TLS error.

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
- [x] `NSAllowsArbitraryLoadsInWebContent` is retained and documented as necessary only for HTTP sites the user explicitly adds. Reader navigation is restricted to HTTP(S), begins at the exact saved URL, and blocks downloads; HTTPS is the default when a scheme is omitted.
- [ ] Verify SoundCloud or other credentials are never logged, included in screenshots, sent to unrelated services, or left in plaintext storage.
- [ ] Confirm `BGTaskSchedulerPermittedIdentifiers`, background modes (`audio`, `processing`), app groups, camera, network, and file entitlements are all required and used exactly as declared.
- [ ] Document why export compliance is exempt/non-exempt and confirm `ITSAppUsesNonExemptEncryption = false` remains accurate for the final binary and dependencies.

## 7. Age rating and parental/content controls

- [x] Completed the current App Store Connect age-rating declarations after the browser/adult-content decisions were finalized.
- [ ] Do **not** reuse the old 4+ assumption; it is incompatible with the current pre-cleanup claims, flashing content, unrestricted web access, and adult-content code.
- [x] Answered **Unrestricted Web Access = Yes** in App Store Connect; Apple's current [age-rating definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/) map this capability to at least 16+ under the new rating system.
- [x] Answered sexual/mature-content questions from the retained adult analysis vocabulary and UI and set the v2 age-rating override to `EIGHTEEN_PLUS` (`SEVENTEEN_PLUS` in the legacy field). Graphic sexual content remains `NONE`.
- [x] Set medical/treatment content to `NONE` after the user-facing claim audit; no treatment or medical functionality is declared.
- [x] Set profanity/crude humor, sexual content/nudity, and mature/suggestive themes to `FREQUENT_OR_INTENSE`; graphic sexual content is `NONE`.
- [ ] If explicit/pornographic content remains, stop submission and remove it; a higher rating does not cure Guideline 1.1.4.
- [ ] Verify parental controls, mature-content defaults, and website restrictions behave consistently on all supported platforms.
- [x] The 18+ override is consistent with the reviewer notes' adult-audience disclosure and the absence of explicit sample material in screenshots/metadata.

## 8. Engineering release quality

### Build and archive

- [ ] Remove all blocker content and create a clean release candidate from the frozen commit.
- [x] Set `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 10027` for the app and share extension.
- [x] Verified build `10027` display name, app/extension bundle IDs, signing team, app group entitlement, deployment target, and distribution signing in the exported IPA.
- [x] Created and exported the signed iOS **Release** archive for build `1.0 (10027)` with Xcode 26.6 / iOS 26.5 SDK on 2026-09-01. macOS is not in this release scope.
- [ ] Run Xcode Organizer/App Store validation and resolve every error and actionable warning.
- [x] Inspected build `10027`'s exported `.app` for retired claims, the removed known-audio catalog resource/titles, explicit bundled samples, version alignment, and signing integrity.
- [x] App and share-extension dSYMs are present in the build `10027` archive and match their binaries' UUIDs.
- [x] Recorded the exact uploaded IPA: 30,082,095 bytes, SHA-256 `ed6b3472e4aa566bfe6cb73f3c076252429e04969c7d7d4d8ff438f14da447e8`.
- [ ] Verify bitcode-related settings and legacy submission configuration are not present where unsupported.
- [ ] Check archive and install size, including WhisperKit/model behavior; disclose any large post-install model download before it starts.

### Automated tests and static checks

- [x] Complete serial iOS 18.5 suite passed on 2026-09-01 after the persistent-stop and support-link changes: **1698 tests / 260 suites / 0 failures** in 37.348 seconds.
- [ ] Run the macOS unit-test suite if macOS is shipping.
- [ ] Run UI tests for onboarding, consent, import, analysis, reading, playback, flashing safety, Settings, and deletion.
- [ ] Run Swift concurrency/static analysis and fix data-race, main-actor, force-unwrap, and crash findings that affect release paths.
- [x] Greenlight reported no critical findings for the exact build `10027` IPA; its launch-storyboard warning is a false positive because `UILaunchScreen` is present. The source-tree Amplitude/ATT result was manually identified as a DSP-word false positive.
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
- [x] Entered the live public Privacy Policy URL.
- [x] Content Rights declares that the app uses third-party content because user-imported media and websites remain.
- [x] Completed the age-rating questionnaire after content cleanup and applied the iOS 18+ override.
- [ ] Complete EU Digital Services Act trader/non-trader status and provide any required public contact information.
- [ ] Review App Store agreements and business/contact information; resolve any account-level banners or expiring agreements.

### iOS/iPadOS 1.0

- [x] Existing description, keywords, subtitle, and categories are substantially aligned with an entertainment positioning and already state that the app is not medical treatment.
- [ ] Re-review all copy after the claims/content changes; remove any feature no longer present in the App Store build.
- [x] Entered the public GitHub Issues Support URL.
- [ ] Confirm subtitle, description, keywords, promotional text (optional), copyright, and version text.
- [x] Uploaded four genuine iPhone 6.9-inch screenshots (1320×2868); App Store Connect reports every asset `COMPLETE`.
- [x] Uploaded four genuine iPad Pro 13-inch screenshots (2064×2752); App Store Connect reports every asset `COMPLETE`.
- [x] Uploaded screenshots use the shipping UI and contain no explicit material or unverifiable outcome claims.
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

- [x] Uploaded build `1.0 (10027)`, whose marketing version exactly matches the App Store version.
- [x] Build `10027` is higher than `10018`, `10024`, and `10026`.
- [x] App Store Connect finished processing build `10027` with state `VALID`; the internal Alpha group has automatic access to every valid build.
- [x] The processed build reports `usesNonExemptEncryption = false`; this matches the current app declaration.
- [ ] Complete TestFlight smoke testing with the exact uploaded build.
- [x] Attached build `10027` to the iOS 1.0 version after the persistent-stop and in-app support/privacy-link changes.
- [x] Published the complete English (U.S.) TestFlight “What to Test” notes on build `10027`.
- [ ] Upload, test, and attach a matching macOS build only if Mac is in launch scope.
- [x] Ran strict App Store Connect validation after build attachment, URLs, screenshots, and age declarations; only Pricing and Availability remains blocking.

## 12. App Review information

- [x] Entered a monitored review contact name, phone, and email.
- [x] Review notes state that no account/login is required and `demoAccountRequired` is false.
- [ ] Attach or provide a small, rights-cleared sample audio/text file so the reviewer can exercise import, analysis, reading, and playback without third-party content.
- [ ] Give concise steps to reach every non-obvious feature: imports, share extension, camera attention monitoring, analysis/model download, reading mode, audio-reactive visuals, and flashing-light controls.
- [ ] Explain any first-run model download, its approximate size/time, and what the reviewer should expect.
- [x] Review notes explain that optional TelemetryDeck analytics defaults off and where to inspect the privacy controls.
- [x] Review notes explain on-device analysis, the optional model download, and that imported audio is not uploaded with it.
- [x] Review notes explain the flashing-light warning, acknowledgement, and persistent stop control.
- [ ] Explain background audio/processing modes and why they are required.
- [ ] Declare all retained third-party services and attach permissions/authorizations where needed.
- [x] Review notes disclose the iOS 18 fallback and optional iOS 26 Foundation Models enhancement.
- [x] Review notes state that the app is intended for unlisted distribution for a limited adult community using its own authorized material.
- [x] Review notes provide a complete no-login path and do not rely on contacting the developer for basic access.

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
