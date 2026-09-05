# LumeSync pages for the QuineEnt Wix site

Paste-ready copy for two new pages on `https://quineent.wixsite.com/quineent`,
written to match the house style already used by `privacy-nocattoe` and
`privacy-iORMPro`.

- **Source of truth:** `PRIVACY_POLICY.md`. This file is a rendering of it, not a
  second policy. If one changes, change both in the same commit — the drift
  between the markdown and the unpublished `lumesync-support-site` copy is
  logged as ERR-033.
- **Suggested page names:** `privacy-LumeSync` and `support-LumeSync`, matching
  the existing `privacy-<AppName>` naming.

## Before publishing — three things to settle

1. **The house template does not fit.** NoCatToe and iORM Pro both say "does not
   collect any personal information." LumeSync cannot say that: it has optional
   TelemetryDeck analytics, opt-in front-camera attention checking, a Hugging
   Face model download, and an iTunes Search lookup. The copy below is adapted
   accordingly. Do not paste the zero-collection template over it.
2. **Pick one support channel.** `PRIVACY_POLICY.md:47-49` currently says support
   runs through public GitHub Issues. The copy below says email
   `quineent@gmail.com`. Publishing both creates the contradiction described in
   ERR-032/ERR-033. Choose, then make the app, App Store Connect, the markdown,
   and this page agree.
3. **Settle the developer name.** `PRIVACY_POLICY.md:8` says "the app developer,
   Byron Quine." The house style says QuineEnt. The copy below uses QuineEnt for
   consistency with the site; whichever is chosen must match the App Store
   Connect seller name.

---

## Page 1 — `privacy-LumeSync`

**Page title:** Privacy Policy - LumeSync

### PRIVACY POLICY FOR LUMESYNC

Last updated September 1, 2026

This privacy policy describes how QuineEnt ("we," "us," or "our") handles
information in our applications for iOS and macOS - LumeSync.

#### SUMMARY

LumeSync keeps your audio and session content on your device. There is no
account. We do not sell personal information, serve behavioral advertising, or
track you across apps and websites. Anonymous usage analytics exist, but they are
off until you turn them on.

#### WHAT INFORMATION DOES LUMESYNC STORE?

LumeSync stores the following information locally on your device only:

- Audio Files: Audio you import, and its local metadata
- Analysis Results: Transcripts and analysis created from your audio
- Sessions: Playlists, visual-session settings, and playback history
- Reading Content: Documents, imported text, and reading preferences
- App Settings: Preferences and your analytics-consent choice

This information:

- Stays on your device
- Is never uploaded to LumeSync servers
- Is not shared with any third parties
- Is deleted by Clear All Data in Settings, or by deleting the app

Audio transcription and analysis run on your device. Some features download a
speech-recognition model before local processing begins. Your audio is not sent
with that model download.

#### CAMERA AND READER ATTENTION CHECKING

Reader attention checking is optional and begins only after you choose to enable
it. When it is on, front-camera frames and face-tracking observations are
processed on your device while the Reader is open. LumeSync does not record,
save, or transmit those images or observations, and monitoring stops when the
Reader closes or the app leaves the foreground.

#### OPTIONAL ANONYMOUS ANALYTICS

Anonymous Usage Analytics are OFF until you opt in. If you enable them, LumeSync
uses TelemetryDeck to receive limited, non-linked analytics for app functionality
and stability. Those analytics may include:

- Product interactions such as screens and features used
- Coarse completion buckets and non-content error categories
- A randomly generated app-installation or device identifier used to distinguish
  anonymous usage over time

#### WHAT WE DON'T COLLECT

LumeSync analytics do NOT include:

- Your name or email address
- Advertising identifiers
- Your audio, transcripts, or imported documents
- Generated text or file names
- Reading-source URLs

Analytics are not used for advertising or cross-app tracking.

#### THIRD-PARTY SERVICES

When you choose to open a website, import an external playlist or audio address,
or download a model, your device connects directly to that provider. The provider
receives normal network information such as your IP address and is governed by
its own privacy policy.

- The on-device WhisperKit speech-recognition model is downloaded from the
  `argmaxinc/whisperkit-coreml` repository hosted by Hugging Face.
- On compatible iOS 26 devices, LumeSync may verify a spoken track title and
  creator against Apple's iTunes Search API. That lookup sends only the inferred
  title and creator strings — not the audio file or full transcript.

LumeSync does not send your locally stored audio, full transcripts, imported
documents, reading-source URLs, or session content to TelemetryDeck, Hugging
Face, or Apple.

#### DATA SECURITY AND DELETION

Local app data is protected by Apple platform security and remains until you
remove it in the app or delete the app.

Clear All Data in LumeSync Settings removes imported content, transcripts and
analysis results, playlists, custom reading sources and presets, playback
progress and history, app settings, downloaded model files, browser cookies and
website data, cached network data, and locally stored analytics state. It also
revokes analytics consent, so no new analytics are sent unless you opt in again.

Clear All Data cannot recall anonymous analytics that were already transmitted to
TelemetryDeck.

No system is perfectly secure, but we limit collection and use standard platform
safeguards to reduce risk.

#### YOUR CONTROL

You can:

- Decline or disable analytics at any time in LumeSync Settings
- Delete locally stored content with Clear All Data
- Revoke camera, microphone, or speech permissions in iOS or macOS System Settings
- Delete the app

Depending on where you live, you may also have legal rights concerning personal
information you send to support.

#### CHILDREN'S PRIVACY

LumeSync is not designed for children and is intended for adult users. We do not
knowingly collect personal information from children.

#### VISUAL SAFETY

LumeSync is a recreational entertainment experience, not medical care or therapy.
Visual effects may include flashing or rapidly changing patterns. Do not use these
effects if you have photosensitivity, epilepsy, or a history of seizures. Stop
immediately if you experience discomfort, dizziness, nausea, visual disturbance,
or unusual symptoms.

#### CHANGES TO THIS POLICY

We may update this policy as needed. Check this page for the latest version. The
"Last updated" date shows when changes were made.

#### CONTACT US

Questions about this privacy policy? Contact us at:

Email: quineent@gmail.com

Mail:
QuineEnt
3864 W Argo St
Tucson, AZ 85742
United States

---

## Page 2 — `support-LumeSync`

**Page title:** Support - LumeSync

### SUPPORT FOR LUMESYNC

#### CONTACT SUPPORT

Email quineent@gmail.com with a short description of the problem. Helpful details
include:

- Your LumeSync version and iOS or macOS version
- Your device model
- The steps that led to the problem
- Any visible error message
- A screenshot, when it does not contain private content

Please do not attach private audio, transcripts, or imported documents unless you
deliberately want support to review them.

#### QUICK TROUBLESHOOTING

**Audio will not import.** Confirm the file is fully downloaded to your device,
then try importing it from the Files app again. LumeSync supports M4A and MP3.

**Analysis will not start.** Keep the app open, connect to the internet for any
first-time model download, and make sure the device has free storage.

**Playback is interrupted.** Restart LumeSync, confirm the original audio file is
still available, and check that another app has not taken audio control.

**Visual effects feel uncomfortable.** Stop the session immediately. Do not resume
flashing effects if you have photosensitivity, epilepsy, or a history of seizures.

#### DELETING YOUR DATA

Clear All Data in LumeSync Settings removes imported content, transcripts and
analysis results, playlists, custom reading sources, playback history, app
settings, downloaded model files, and locally stored analytics state, and revokes
analytics consent.

#### VISUAL SAFETY

LumeSync may display flashing or rapidly changing visual patterns. Do not use
these effects if you have photosensitivity, epilepsy, or a history of seizures.
Stop immediately if you experience discomfort, dizziness, nausea, visual
disturbance, or unusual symptoms.

LumeSync is a recreational entertainment experience. It is not a medical device
and is not intended to diagnose, treat, cure, or prevent any condition.

#### PRIVACY

For detail on how LumeSync handles your information, read the LumeSync Privacy
Policy on this site.
