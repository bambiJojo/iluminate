# LumeSync 1.0 TestFlight Notes

LumeSync is an audio and reading player with synchronized, adjustable visual
patterns. This release candidate supports iPhone and iPad on iOS 18 or later.

## What to test

- Complete onboarding and confirm the flashing-light warning is clear.
- Import an MP3 or M4A file, run local analysis, and play the resulting visual
  session.
- Import a text document or add a website of your choice, then save and read a
  page in the Reader.
- Create a custom visual session and verify that play, pause, and stop remain
  easy to reach.
- Enable and disable anonymous analytics in Settings. It must remain off until
  you opt in.
- Relaunch the app and confirm that imported content, progress, and settings are
  preserved.

User-provided hypnosis and mature-content classification remain supported. The
app does not include or recommend a directory of adult websites, stories, or
audio. Only import content you are authorized to use.

## iOS 18 and iOS 26

The complete reader, library, player, custom visual tools, and local audio
analysis work on iOS 18. On iOS 26, compatible devices can additionally use
Apple's on-device Foundation Models during analysis. On iOS 18, LumeSync uses
local keyword, metadata, and audio heuristics instead.

## Privacy

Audio, transcripts, documents, reading history, and generated session data stay
on the device. Optional TelemetryDeck analytics are off by default and do not
include imported content, filenames, transcripts, or reading-source URLs.

## Visual-safety reminder

Some modes display flashing or rapidly changing patterns. Do not use flashing
modes if you have photosensitivity, epilepsy, or a history of seizures. Stop
immediately if you feel unwell. Do not use the app while driving or operating
machinery.

LumeSync is a recreational entertainment experience, not medical care or
therapy.

## Feedback

Please send feedback through TestFlight and include:

- Device model and iOS version
- The feature you were using
- Clear reproduction steps for a crash, freeze, or incorrect result
- A screenshot when it does not expose private imported content
