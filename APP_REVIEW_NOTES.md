# LumeSync 1.0 App Review Notes

LumeSync does not require an account or login. All shipping features are available after onboarding.

The review attachment **LumeSync-1.0-App-Review-Samples-v2.zip** contains an original text sample, a macOS-synthesized M4A narration of that text, and a rights/instructions note. It contains no third-party or explicit material.

## Suggested review path

1. Complete onboarding. The flashing-light warning is required. Camera attention checking and anonymous analytics are both optional; choose **Not Now** to continue without either.
2. Open **Library** and tap **+** to import the attached `LumeSync-Review-Sample.m4a` (or another MP3/M4A). Core transcription, timing, and structure analysis run on the device. The first analysis may download the approximately 140 MB WhisperKit `base` model from Hugging Face; download time depends on the network and progress appears in the Analysis Queue. Imported audio is not uploaded with that download.
3. Open **Reader**. The bundled **Calm Boundaries** script lets you test paced reading immediately. Tap **+** to import the attached `LumeSync-Review-Sample.txt`, another text document, or a user-chosen HTTP(S) website. The app has no curated website directory, search recommendations, or bundled explicit stories. Saving a visible web page requires a separate acknowledgement that the user has permission to import it.
4. Open **Create** to configure Flash, Colour, Bilateral, or Visuals sessions. Flashing modes remain behind the safety acknowledgement. The Close control stops a running session; after the full controls hide, a persistent **Stop session** button remains on-screen.
5. Open **Settings** to inspect privacy controls. Anonymous TelemetryDeck analytics are off until the user opts in and never include imported content, filenames, transcripts, or reading-source URLs. **Clear All Data** removes local content, settings, downloaded models, browser website data, and local analytics state, and revokes analytics consent.

## Platform behavior

The complete reader, library, player, custom visual tools, and local audio analysis work on iOS 18 and later. On compatible iOS 26 devices, analysis may additionally use Apple's on-device Foundation Models. On iOS 18, local keyword, metadata, and audio heuristics provide the fallback.

On iOS 26, when the on-device analysis identifies both a spoken track title and creator, the app may send only those two inferred strings to Apple's iTunes Search API to verify public catalog metadata. It does not send the audio file or full transcript.

The `audio` background mode keeps user-started playback active when the app is backgrounded or the screen locks. The `processing` mode lets user-started on-device analysis continue when iOS grants time and resume from durable checkpoints after suspension. Neither mode records audio or runs background analytics.

## Content disclosure

LumeSync is intended for adults and supports classification of user-imported hypnosis and mature material. The app preserves labels such as hypnosis and mature-content categories, but it does not ship explicit audio, stories, thumbnails, third-party transcripts, or links to adult websites. It does not recommend where to obtain adult content. Users choose and remain responsible for their own local files and websites.

LumeSync is a recreational entertainment experience, not medical care or therapy. It does not diagnose, treat, prevent, or monitor a condition.

## Distribution

This version is intended for Unlisted App distribution for a limited adult community using its own authorized audio and reading material. It is not intended for App Store search or broad public discovery. The separate unlisted-distribution request will be filed when the final version is submitted.

Privacy policy: https://github.com/bambiJojo/iluminate/blob/main/PRIVACY_POLICY.md

Support: https://github.com/bambiJojo/iluminate/issues
