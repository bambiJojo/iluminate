# LumeSync resubmission review — September 10, 2026

> Update September 10: the findings below describe the original audit. See [current status](RESUBMISSION_STATUS_10030.md) for completed fixes and remaining device evidence.

**Decision: not ready to resubmit.** The local fixes address much of the rejection, but the submission materials have not caught up, a remote-control implementation needs correction, and the current branch contains personal-build functionality that conflicts with the review notes.

Scope: reviewed the supplied HTML and Markdown response, working-tree changes on `fix/app-review-rejection-1.0`, relevant playback/analytics code and manifests, the logged-in App Store Connect version and privacy pages, and both public policy URLs. No App Store Connect changes, messages, uploads, or submission were made. Existing source and reply files were left unchanged.

## Findings requiring action

### 1. Replace the selected build before claiming the fixes are attached

App Store Connect still selects **1.0 (10029)**, build ID `67c90e1d-d525-440c-bb79-9d8337eae842`, in the rejected iOS version. Project build settings also still contain 10029. The response currently says a new build is attached.

Archive the intended release source with a new build number, validate its actual iOS binary and privacy report, upload it, wait for processing, and select it. Identify that new build explicitly in the reply. Local source changes do not change the already-uploaded 10029 binary.

### 2. Publish the face-data policy at the URLs reviewers and users actually see

The local `PRIVACY_POLICY.md` has the new “Camera and Face Data” section. Neither public copy inspected contains it:

- App Store Connect points to the [Wix privacy policy](https://quineent.wixsite.com/lumesync/privacy-policy), dated September 1. It still describes optional front-camera attention checking and revoking camera/microphone permissions.
- The response and the app's `AppSupportLink.privacyPolicy` point to the [GitHub policy](https://github.com/bambiJojo/iluminate/blob/main/PRIVACY_POLICY.md), also still dated September 1 and describing attention checking.

Publish consistent current text to both, or deliberately consolidate the policy URL in the app, metadata, and reply. The quoted section must be publicly visible before replying. Preserve the Wix private support contact when updating that page; the local policy instead routes privacy requests through public GitHub issues.

### 3. Supply physical-device background-audio evidence and fix the toggle

The visible App Review Information attachment is only `LumeSync-1.0-App-Review-Samples-v2.zip`. The project plan also marks the requested recording as outstanding. The response must not yet say the recording is attached.

Record the replacement build on a physical iPhone: import the supplied M4A, start audible playback, navigate to the Home Screen while playback continues, and demonstrate Control Center/Lock Screen controls. Check the saved recording actually contains audible app output. Give precise import/playback instructions so an empty first-launch Library is not a dead end. Include the recording with review information, preserving the useful samples, and name it in the notes. Test an iPad too, plus lock/unlock, interruptions, headphone disconnect, pause/resume, seeking, and completion.

There is a concrete implementation concern in `Ilumionate/SystemNowPlayingCenter.swift`: `togglePlayPauseCommand` decides whether to pause or play by reading `MPNowPlayingInfoCenter.default().playbackState`. Apple documents that property as [applying only to macOS](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter/playbackstate); the installed iPhoneOS SDK header says the same. Route toggle directly through the player's actual state, or maintain explicit app-owned state. Restrict the macOS playback-state setter appropriately. The existing tests exercise metadata publication policy, not iOS remote-command behavior.

The draft's explanation that two identified defects caused the reviewer to hear no audio is not established. The normal Library audio path in root-level `AudioLightSyncPlayer.swift` already uses a non-mixable playback session. Now Playing controls improve discoverability, but their presence is not proof of audible background playback. Describe the changes and demonstrated behavior, without asserting an unverified root cause.

### 4. Remove obsolete attention-check marketing assets

The iPhone screenshot list in App Store Connect still includes `07-attention-in-sync.png`. The corresponding local campaign asset advertises “Keeps pace when you look away” and shows the deleted camera onboarding screen. Remove or replace this asset wherever uploaded. Inspect the other device sizes/localizations and app preview for the same removed feature. Its continued presence contradicts both the new app and the reply.

### 5. Keep the personal BambiCloud functionality out of the intended neutral release

The current branch contains an unconditional “Browse BambiCloud” action in `Ilumionate/LibraryAddMenu.swift:46`, a browser defaulting to that host in `PlaylistImport/PlaylistLinkBrowserView.swift:28`, and service-specific playlist conversion/download support.

This conflicts with the review notes claiming there are no links to adult websites or recommendations for where to obtain content. The repository already records this release-branch problem in ERR-035. I reproduced the existing failing test `PlaylistSourceDocumentTests.noHardcodedPlaylistHost()`.

Prepare the release from the intended neutral source, carrying over the rejection fixes without the personal integration. Do not merely delete the test or hide the integration from reviewers. If retaining service-specific downloads is intentional, accurately disclose the behavior and resolve content/authorization requirements before submission. Apple's [review guidelines](https://developer.apple.com/app-store/review/guidelines/) cover accurate metadata, objectionable content, and third-party media downloading.

### 6. Reconcile and shorten review notes

Live review notes still tell reviewers to choose “Not Now” for camera attention checking. `app-store/review-notes-public.md` also retains that old instruction.

The replacement `APP_REVIEW_NOTES.md` is **5,164 characters**, exceeding the live Notes field's 4,000-character capacity. It also describes **unlisted distribution**, whereas the live notes specify **public distribution in the US, UK, Canada, Australia, and New Zealand**, and App Store Connect currently shows public distribution with five available territories.

Use one concise, accurate version under 4,000 characters. Preserve the actual chosen distribution plan, current website/support links, sample import instructions, no-camera explanation, non-tracking analytics explanation, and the physical-device video filename. Do not paste the current local notes unchanged.

## What the local fixes do address

- Camera onboarding and the Reader attention monitor are deleted. Searches of current project Swift/configuration files found no remaining ARKit/ARFace/TrueDepth/camera-permission usage. iOS/macOS camera usage descriptions and the macOS camera entitlement are removed. Validate the final archived iOS binary separately.
- The post-launch analytics alert is removed. Onboarding uses a false-initialized analytics toggle and Continue. `UsageAnalytics` gates SDK initialization and sending on consent.
- App Store Connect privacy currently shows Device ID and Product Interaction, used for Analytics and not linked to identity, with no tracking category displayed. The inspected TelemetryDeck privacy manifest also declares those categories without tracking. The app's own manifest separately declares Product Interaction for App Functionality; review the final aggregated report for accurate purposes.
- I found no advertising SDK or IDFA integration in the inspected project configuration and analytics code. Apple ties ATT to its definition of [tracking](https://developer.apple.com/app-store/user-privacy-and-data-use/), not to all optional analytics. An off-by-default analytics toggle can remain an ordinary privacy choice when the underlying processing is genuinely non-tracking.

## Improve the reply's accuracy and tone

- Replace “We have addressed every item. A new build is attached” with the actual replacement build number only after it is selected.
- Distinguish the replacement build from 10029 in the face-data answers. For 10029, explain on-device camera/ARKit processing, face-presence/tracking state, head pose and left/right eye-blink coefficients used for attention decisions, temporary runtime use, no persistent recording, no transmission/sharing, and stopping monitoring when leaving the Reader/backgrounding. “Only two values” describes the final derived scores, not all ARKit inputs or intermediate state. Do not imply ARKit itself produced only two pieces of face data.
- Remove “the question is moot going forward.” State that the feature is removed from the replacement build, then answer the original-build questions respectfully.
- Remove the offer to add ATT merely if Apple prefers it. Explain the actual non-tracking data practices and consent controls directly.
- Replace “used solely to find crashes and broken flows” with “used for product usage and stability analytics.” The event catalog also measures activation, retention, screens, and feature usage.
- Remove or qualify “Neither mode ... runs background analytics” in the notes: `handleScenePhase(.background)` emits an optional `player.lifecycle` analytics event. It is accurate to explain that background modes are used for playback/analysis, not to keep an analytics service running.
- Do not claim physical-device behavior or attachments are verified until they are.

## Verification completed and remaining limits

- macOS build/test run: **216 test cases passed**, targeting analytics consent, Reader mode/gating/resume/quick-start/session changes, and Now Playing publication policy. Log: `/tmp/lumesync-rejection-review-tests.log`.
- Separate release-neutrality regression: **1 test failed**, `PlaylistSourceDocumentTests.noHardcodedPlaylistHost()`. Log: `/tmp/lumesync-host-review-test.log`.
- Greenlight ran at the repository root and again on `Ilumionate/`. It is **not GREENLIT**. Its reported Amplitude/ATT finding points to an audio-amplitude comment, not an Amplitude SDK. The root disk-space finding points to dependency test fixtures in build caches/worktrees. The StoreKit warning is triggered by the app-rating import, not an identified purchase flow. These are scanner false positives/scope contamination, not reasons to add ATT or restore purchases. Do not treat the scanner's status as an approval prediction.
- No replacement iOS archive was built or uploaded in this review. No physical-device playback, network capture, full screenshot/video audit, or final aggregate privacy report was validated. Those remain release checks.

## Resubmission sequence

1. Prepare the neutral release source and correct the iOS remote toggle.
2. Run the relevant release checks, archive with a new build number, and inspect the archive's APIs, entitlements, and privacy report.
3. Test and record audible background playback on a physical device.
4. Publish the policy updates and remove obsolete attention-check assets.
5. Select the processed replacement build; attach evidence and concise consistent review notes.
6. Send the corrected point-by-point reply and resubmit only when all claims match the selected build and live metadata.
