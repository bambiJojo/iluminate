# App Store update — 1.0.3 (10035)

Built from `release/1.0.3` = `main` (the accepted 10031 source) + player feedback commits
`f3e488e7` and `7f589202`. **No BambiCloud code**; unlike the internal-only 1.0.1 (10033)
and 1.0.2 (10034) builds, this one is safe to submit for App Review.

Uploaded 2026-09-26 via `Scripts/release-testflight.sh --version 1.0.3`.
App Store Connect build ID: `f2d911f1-bf0d-4ff5-a322-684a414f01a2`. Processing: **VALID**.
Encryption: exempt. Internal group: **Alpha internal** (automatic). **Not yet submitted for review.**
Exported IPA checked: the app and share extension both declare 1.0.3 (10035), and there are
zero `bambicloud` matches in the app bundle.
Artifacts: `/tmp/Ilumionate-TestFlight-1.0.3-10035.KXk1gn`; log `/tmp/ilumionate-release-10035.log`.

Build number note: App Store Connect suggested 10030 for the empty 1.0.3 version. The project was
based on 10034 so builds stay monotonic above the internal 10033/10034.

## What's New (App Store Connect, en-US)

```
Thanks for the feedback! This update is all about the player.

• See your progress your way: tap the time to switch between elapsed, time remaining, and percent complete. You can also set it in Settings → Session Defaults → Time Display.
• Sessions and playlists now show your progress in the player too.
• Longer files show hours, so a 75-minute track reads 1:15:00.
• The Stop button stays out of your way: after a few quiet seconds it shrinks to a small stop icon, and it's still one tap to end a session.
• "Swipe up to show controls" now disappears once you've used it.
```

## Review notes

No change needed. The live notes say "Close/Stop session ends playback", which is still true:
a Stop control is always on screen while the controls are hidden, in icon form after 8 s idle.

## Verification

- Full `IlumionateTests` on iOS 26.0 (iPhone 17 Pro): 1718 passed.
- Affected suites on iOS 18.5 (iPhone 16 Pro): 32 passed.
- Rendered the Stop button (hint / expanded / icon) over bright, pink, and dark fields, plus the
  Settings card, on the iOS 26 simulator. The hint needed a dark backing to be readable on
  a bright field; fixed in `7f589202`.
- Not verified: gesture timing on a physical device (no device access in this environment), and
  macOS (not shipping; deprioritised by the owner 2026-09-26).
