LumeSync 1.0 (10031) — App Review Notes

No account, login, purchase, or subscription is required. This version is intended for public App Store distribution in the United States, United Kingdom, Canada, Australia, and New Zealand. App behavior does not vary by country.

Changes following review of builds 10029 and 10030:
- Removed Reader attention checking, its camera pre-permission screen, and all camera/ARKit/TrueDepth use. No camera permission is requested.
- Removed the onboarding analytics screen shown in Screenshot-0914-141626.png. Fresh installs have optional product analytics disabled. Users can enable or disable it in Settings; onboarding does not request analytics consent.
- Added system Now Playing metadata and remote playback controls for user-started audio.

REVIEW PATH
1. Complete onboarding and acknowledge the flashing-light warning. The next screen offers a welcome session or Explore App; no analytics screen appears.
2. Save and unzip the attached LumeSync-1.0-10030-Review-Evidence.zip in Files. In Library, tap + > Import from Files and select LumeSync-Review-Sample.m4a. Open the imported audio and press Play. The sample is original, non-explicit narration; the ZIP includes rights/instructions and a text sample.
3. While the narration is audible, go to the Home Screen. Audio should continue. Check Control Center or the Lock Screen for LumeSync, play/pause, scrubbing and 15-second skips. Background audio applies to sessions with audible audio; a visual-only session does not demonstrate it.
4. Open Reader and use the bundled Calm Boundaries script, or import the attached LumeSync-Review-Sample.txt. Reading uses manual pause/resume; there is no camera attention check.
5. Open Create to configure visual sessions. Close/Stop session ends playback. Flashing effects remain behind the safety acknowledgement.
6. In Settings, inspect analytics controls, Privacy Policy and Clear All Data. Clear All Data removes local content, settings, models, browser data and analytics state, and revokes analytics consent.

PRIVACY AND PROCESSING
Core transcription and analysis run on-device. Initial analysis may download the ~140 MB WhisperKit base model from Hugging Face; audio is not uploaded with it. Compatible iOS 26 devices may also use on-device Foundation Models. A public-metadata lookup may send only an inferred track title and creator to Apple's iTunes Search API, not audio or the full transcript. Core features work on iOS 18 and later.

Optional TelemetryDeck analytics measure usage and stability. They exclude audio, transcripts, imported documents, generated text, filenames and reading-source URLs. There is no advertising identifier use, third-party advertising linkage or data-broker sharing, so the app does not use ATT. App Privacy declares non-linked Device ID and Product Interaction for analytics.

The audio background mode supports user-started audible playback. The processing mode supports user-started local analysis when iOS grants execution time, with durable checkpoints. Neither mode records audio or keeps an analytics service running.

CONTENT AND SAFETY
Users import their own authorized files and websites. The app contains no explicit media, adult-site links or content-provider recommendations. LumeSync is an entertainment experience, not medical care. Photosensitive users should not use flashing modes.

Privacy: https://quineent.wixsite.com/lumesync/privacy-policy
Support: https://quineent.wixsite.com/lumesync/support

RECORDING EVIDENCE
The attachment is carried over from the previous submission, so its name still reads 10030. It includes ScreenRecording_09-10-2026 16-37-42_1.MP4, an unedited physical-iPhone recording. It shows continued sample narration on the Home Screen at approximately 6–16 seconds and Control Center pause/resume at approximately 19–30 seconds. The ZIP also contains the regenerated original narration sample, text, and README.
