# LumeSync

LumeSync is a native SwiftUI app for synchronized audio, reading, and visual
photoentrainment sessions. iOS and macOS are first-class targets built from the
same feature code.

## Supported platforms

| Platform | Status | Navigation |
| --- | --- | --- |
| iOS 18+ | First class | Four-tab compact interface |
| macOS 26+ | First class, native AppKit/SwiftUI destination | Resizable window with a native sidebar and Settings scene |
| Mac Catalyst | Compatibility destination | Compact interface in a desktop window |

iOS 18 runs the complete app. On-device AI analysis needs iOS 26 (Foundation
Models); below that, audio is analysed with keyword, metadata, and audio
heuristics and background analysis is deferred rather than continued. See the
[beta tester guide](BETA_TESTER_GUIDE.md) for the user-visible differences.

The native Mac app is not a separate copy of the product. The `Ilumionate`
scheme compiles the same models, stores, analysis pipeline, player, and feature
views for iOS and macOS. Small platform adapters isolate lifecycle, display-link,
audio-session, haptics, WebKit, and presentation differences. A feature or bug
fix made in shared code therefore reaches both first-class platforms.

This keeps the applications' **code and behavior** in sync. It does not yet sync
a user's library or settings between devices: those remain local to each app
installation. Cross-device data sync will require a separate CloudKit or other
sync implementation.

## Build

Open `Ilumionate.xcodeproj` in Xcode and select either **My Mac** or an iOS
simulator. Command-line equivalents are:

```bash
# Native macOS
xcodebuild -project Ilumionate.xcodeproj \
  -scheme Ilumionate \
  -destination 'platform=macOS,arch=arm64' \
  build

# iOS Simulator
xcodebuild -project Ilumionate.xcodeproj \
  -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# Mac Catalyst compatibility check
xcodebuild -project Ilumionate.xcodeproj \
  -scheme Ilumionate \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  build
```

Use an installed simulator name when it differs from the example above.

## Test

Run the shared unit suite on both first-class destinations before merging
cross-platform feature work:

```bash
xcodebuild -project Ilumionate.xcodeproj \
  -scheme Ilumionate \
  -destination 'platform=macOS,arch=arm64' \
  test -only-testing:IlumionateTests

xcodebuild -project Ilumionate.xcodeproj \
  -scheme Ilumionate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:IlumionateTests
```

See [`Ilumionate/TESTING_GUIDE.md`](Ilumionate/TESTING_GUIDE.md) for the broader
test strategy and [`PRIVACY_POLICY.md`](PRIVACY_POLICY.md) for platform privacy
details.
