# LumeSync resubmission status — September 10, 2026

## Completed

- Wix privacy policy corrected, published, and verified at https://quineent.wixsite.com/lumesync/privacy-policy. It includes the removed attention-check feature and face-data statement, optional analytics, local processing/deletion, and private support communications.
- App support/privacy URLs, App Store Connect privacy URL, and review drafts use Wix. GitHub's policy file now only links to Wix (remote commit `eab1c364fefefd1b58bb3ec17707179c03122c4d`).
- Camera/attention feature and permission strings removed. Release archive contains no ARKit dependency, ARFaceTrackingConfiguration or ARFaceAnchor strings. App and extension are build 10030.
- Standalone analytics prompt replaced by an off-by-default onboarding toggle; no tracking declared in packaged privacy manifests. App Privacy labels were checked earlier in this session: Device ID and Product Interaction, Analytics, not linked, no tracking. A later browser session expired; the API cannot verify publication status.
- Personal BambiCloud integration removed from the release working tree.
- Now Playing controls added, including an iOS-safe play/pause toggle with regression coverage.
- Obsolete attention-check screenshots removed from both iPhone galleries. Remaining screenshot galleries and preview inspected.
- Targeted tests passed: 105 iOS regression tests, 1 remote-transport test, 2 Wix-link tests. Release clean archive, signature verification, and IPA export succeeded.
- App Store Connect review notes updated to build 10030 instructions. Draft Apple reply includes historical face-data practices and the published policy quotation; it has not been sent.
- Metadata validation returned zero errors and zero warnings, with informational notes about manual release and API inability to verify App Privacy publication.

## Build artifacts

- Archive: `/tmp/LumeSync-10030-final.xcarchive`
- IPA: `/tmp/LumeSync-10030-export/Ilumionate.ipa`
- Upload log: `/tmp/lumesync-10030-upload.log`
- Build `7906ee59-348a-4560-8b0b-d42ce8b25da0` is VALID, encryption exempt, selected for version 1.0, and IN_BETA_TESTING for internal testing. Final metadata validation: zero errors and zero warnings. Version is PREPARE_FOR_SUBMISSION.

## Recording evidence completed

The developer supplied `AppReviewSamples/ScreenRecording_09-10-2026 16-37-42_1.MP4` (33.58 seconds). Sampled video frames show playback in LumeSync, the Home Screen, and Control Center pause/resume. The Home Screen audio excerpt at 8–12 seconds correlates with the known narration at 0.8735; Home Screen audio RMS is -18.8 dBFS. The pause interval is silent and narration resumes afterward. The original video was not edited.

Apple's API rejected a second attachment because it allows one attachment. Replaced the old sample-only ZIP with `LumeSync-1.0-10030-Review-Evidence.zip`, including this video, regenerated sample audio, text, and instructions. Attachment `25c4e285-c1b2-4c01-80a8-246ede1bdf9f` is COMPLETE (60,957,681 bytes). Live review notes and the draft reply now name the evidence and timestamps. Validation remains zero errors and zero warnings.

## Remaining

- App Privacy publication verified in the signed-in UI on September 11: “Published 7 days ago by Byron Quine”; Device ID and Product Interaction for Analytics, not linked to identity, and Wix policy URL.
- Incoming-call interruptions, headphone disconnection and lock-screen behavior are not established by this recording.
- Apple reply sent and resubmission completed; awaiting Apple review.

## Resubmitted September 11, 2026 (Europe/Athens)

User authorized sending the reply and resubmitting. Sent a 3,960-character response through App Store Connect covering all five guidelines, historical face-data practices, the exact Wix policy quotation and recording evidence. UI confirmed Messages (2) with the new Byron Quine reply. Marked the corrected review item resolved, then resubmitted submission `98358163-4be9-43b2-968e-9f1437675929`. Apple returned WAITING_FOR_REVIEW at `2026-09-10T22:35:58.453Z` (September 11, 01:35 Athens). Build 10030 remains selected. Manual release remains configured.
