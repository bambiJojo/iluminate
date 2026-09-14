# App Review reply — submission 98358163-4be9-43b2-968e-9f1437675929

**Reference draft. A condensed 3,960-character version covering all sections was sent September 11, 2026, to fit Apple’s 4,000-character limit. Build 10030 resubmitted; status WAITING_FOR_REVIEW.**

---

Thank you for reviewing LumeSync 1.0 (10029). Our replacement build is 1.0 (10030). Below are the changes and the requested information.

## Guideline 5.1.1(iv) — Camera permission

We removed the optional Reader attention-check feature, including the custom camera explanation with “Enable Attention Check” and “Not Now.” The replacement app requests no camera permission. Its camera usage descriptions and macOS camera entitlement have been removed. Reading now uses manual pause and resume.

## Guideline 2.1 — Face data

**What face data does the app collect?** The replacement build does not use the camera or collect, process, store, or transmit face data.

For the reviewed build 10029, the optional attention check used ARKit on-device face tracking while Reader was open and camera access was granted. The app used face-tracking status, head position/orientation and left/right eye-blink coefficients to derive attention and eyes-closed scores and decide whether to pause or resume reading. Camera frames and ARKit face observations were processed locally; they were not used for identification, advertising, profiling, or analytics.

**Use, sharing, storage, retention and deletion:** In build 10029, these observations and derived attention state were temporary runtime data used only for that reading feature. The app did not record camera images or persist face observations to disk, and did not upload or share them. Monitoring stopped when Reader closed or the app left the foreground. There was no stored face-data record requiring later deletion. The feature and its code have been removed from the replacement build, so it has no face-data use, storage, retention, sharing, or deletion workflow.

**Third parties and storage location:** No face data was sent to third parties or external servers. Processing in 10029 occurred only on the device during the optional feature. The replacement build performs no face processing.

**Privacy-policy location:** The “Camera and Face Data” section, immediately after “Information Processed on Your Device,” explains removal of the feature and the earlier build's practices. The section states:

> LumeSync does not use the camera and does not collect, process, store, or transmit face data of any kind. The app requests no camera permission, contains no camera or face-tracking code, and declares no camera usage description or entitlement.
>
> An earlier pre-release build included an optional Reader "attention check" that used on-device face tracking to pause reading when you looked away. That feature and all of its code were removed before release. No face data was ever stored, shared, or transmitted by any version of the app.

Privacy policy: https://quineent.wixsite.com/lumesync/privacy-policy

## Guideline 5.1.2(i) — Tracking and analytics

LumeSync does not track users as Apple defines tracking. It does not access the advertising identifier, link app data with third-party data for advertising, or share data with data brokers. There is no advertising SDK.

Optional TelemetryDeck analytics measure product usage and stability: screens and features used, completion buckets, activation/retention events and non-content error categories. They exclude audio, transcripts, imported documents, generated text, filenames and reading-source URLs. App Store Connect declares non-linked Device ID and Product Interaction used for Analytics, without tracking.

We removed the standalone analytics alert. Onboarding now has an off-by-default “Share anonymous analytics” toggle and one Continue button. The user can proceed with analytics off and can change the choice in Settings. The SDK is not initialized for analytics before opt-in. This setting controls optional product analytics; it does not request permission for tracking. Because the app does not perform tracking, it does not use AppTrackingTransparency.

## Guideline 2.5.1 — TrueDepth

The removed Reader attention check was the only feature using ARKit face tracking. The replacement build removes that feature and its ARKit/TrueDepth API use, including ARFaceTrackingConfiguration and ARFaceAnchor. There is no camera-dependent feature for reviewers to locate.

## Guideline 2.5.4 — Background audio

LumeSync plays user-imported audio. The audio background mode is used for user-started audible playback when the app is backgrounded or the screen locks. The replacement build adds Now Playing metadata and play, pause, toggle, seek and 15-second skip handlers. The toggle uses the player's own state on iOS.

To reproduce from a fresh installation:

1. Save and unzip the attached LumeSync-1.0-10030-Review-Evidence.zip in Files.
2. Complete onboarding. In Library, tap + > Import from Files and select LumeSync-Review-Sample.m4a.
3. Open the imported item and press Play. Once narration is audible, go to the Home Screen.
4. Verify continued audio and use Control Center/Lock Screen playback controls. Use this audio-backed session for the demonstration; visual-only sessions do not demonstrate background audio.

The attached LumeSync-1.0-10030-Review-Evidence.zip includes the unedited physical-iPhone recording ScreenRecording_09-10-2026 16-37-42_1.MP4, the audio/text samples, and a README. The recording shows playback in LumeSync, continued narration on the Home Screen (approximately 6–16 seconds), and Control Center pause/resume (approximately 19–30 seconds).

The app behaves the same across its available countries and regions. Thank you for reviewing the replacement build.
