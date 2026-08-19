# structure-harness

Runs `Ilumionate/Structure/` over a real exported analysis cache and prints one
report per file, so boundaries can be checked against audio somebody knows.

This is a standalone binary rather than a test. The macOS test host is sandboxed:
it can read an exported container but cannot write a report to `~/Downloads` or
`/tmp`, and `xcodebuild test` does not surface test stdout either — so a harness
living in the test target produces an expensive silence.

`Shim.swift` supplies minimal stand-ins for `WordTimestamp`, `ProsodicProfile`,
`DetectedPause` and the word-timestamp approximation. The algorithm sources are
compiled from their real paths, not copied, so the harness exercises shipping
code. The shim mirrors `AudioFile.swift` and
`HypnosisPhaseAnalyzer.approximateWordTimestamps(from:)` — if those change, this
must follow.

## Getting a cache

Xcode → Window → Devices and Simulators → the device → LumeSync →
Download Container. Inside the `.xcappdata`:

- `AppData/Library/Application Support/LumeSync/Analysis/AnalysisCache.json`
- `AppData/Library/Application Support/AudioLibrary/library.json` (optional —
  maps content fingerprints to filenames, so reports name files instead of
  hashes)

## Running

```sh
./Tools/structure-harness/run.sh <AnalysisCache.json> [minimumNovelty] [minimumSegmentSeconds] [library.json]
```

Both parameters default to the values in `StructuralSegmenter`. Passing them
explicitly is how the defaults were chosen — see the sweep note there.
