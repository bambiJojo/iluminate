# Duplicate Detection on Audio Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognise audio the library already has *before* the bytes are spent, so importing a BambiCloud playlist never re-downloads a track and saves it as `Name (1).mp3`.

**Architecture:** Two identity signals are added to `AudioFile` — a content fingerprint (already computed, never read) and a new remote provenance record. A pure `DuplicateAudioIndex` turns a library snapshot into verdicts, and that index is consulted at three import doors: before the network request, on the downloaded temp file before it enters `Documents`, and in the Files-picker path. A separate merge-based cleanup screen resolves duplicates already in the library.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing, CryptoKit (SHA-256), AVFoundation. Targets iOS 26 / macOS 26, strict concurrency.

**Spec:** [`docs/superpowers/specs/2026-08-10-audio-duplicate-detection-design.md`](../specs/2026-08-10-audio-duplicate-detection-design.md)

---

## Before you start

**Read the spec first.** It documents five compounding root causes; this plan implements the fix for each.

**Xcode target membership is automatic.** The project uses `PBXFileSystemSynchronizedRootGroup` (`Ilumionate.xcodeproj/project.pbxproj:189`). Any `.swift` file created under `Ilumionate/` or `IlumionateTests/` joins its target with no `.pbxproj` edit. Do not hand-edit the project file.

**Build and test commands** — every task uses these.

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

To run one test, append the type and function name — **with the trailing `()`**. Without it
the filter matches nothing, no tests run, and `xcodebuild` still prints `** TEST SUCCEEDED **`
(ERRORS.md ERR-002). `Scripts/run-tests.sh` wraps `xcodebuild` and fails when zero tests ran,
which is the safer way to invoke any filtered run.

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/AudioTitleNormalizerTests/numberedSeriesStayDistinct()
```

Run the iOS Simulator destination too before the final commit of each phase:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

**House conventions that matter here** (from `CLAUDE.md`): Swift Testing only, never XCTest. `@Observable` + `@State`, never `ObservableObject`. `async`/`await`, never `DispatchQueue`. `foregroundStyle`, never `foregroundColor`. One primary type per file. No force unwraps.

---

## File structure

**New — `Ilumionate/LibraryDedupe/`**

| File | Responsibility |
|---|---|
| `RemoteAudioSource.swift` | Value type recording which publisher and track a file was fetched from |
| `AudioTitleNormalizer.swift` | The single normalisation used by both the matcher and the detector |
| `DuplicateAudioCandidate.swift` | What is known about a not-yet-imported file |
| `DuplicateAudioVerdict.swift` | The verdict enum |
| `DuplicateAudioIndex.swift` | Library snapshot → verdict |

> **Naming note.** The spec calls this component `DuplicateAudioDetector` and lists it as one file. The plan splits it into three — candidate, verdict, index — to honour the project's one-primary-type-per-file rule, and names the queryable type `DuplicateAudioIndex` because that is what it is: a prepared lookup over a library snapshot, not a stateful detector. Wherever the spec says `DuplicateAudioDetector`, read `DuplicateAudioIndex`.
| `DuplicateAudioGroup.swift` | Grouping and merge policy for cleanup |
| `DuplicateAudioReviewViewModel.swift` | Cleanup screen state |
| `DuplicateAudioReviewView.swift` | Cleanup screen |

**New — `IlumionateTests/`**

`AudioTitleNormalizerTests.swift`, `DuplicateAudioIndexTests.swift`, `DuplicateAudioMergeTests.swift`

**Modified** — listed per task.

---

## Phase 1 — Identity primitives

Pure value types. No UI, no I/O, no behaviour change yet.

### Task 1: `AudioTitleNormalizer`

Extracts the normaliser out of `BambiCloudPlaylistImporter` and fixes the numbered-series collapse (spec root cause 5).

**Files:**
- Create: `Ilumionate/LibraryDedupe/AudioTitleNormalizer.swift`
- Create: `IlumionateTests/AudioTitleNormalizerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/AudioTitleNormalizerTests.swift`:

```swift
//
//  AudioTitleNormalizerTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct AudioTitleNormalizerTests {
    @Test("Strips path, extension, case and punctuation")
    func reducesToComparableTokens() {
        #expect(AudioTitleNormalizer.normalize("/tmp/Deep_Relaxation!.mp3") == "deep relaxation")
        #expect(AudioTitleNormalizer.normalize("Deep   Relaxation") == "deep relaxation")
        #expect(AudioTitleNormalizer.normalize("Déjà Calm") == "deja calm")
    }

    @Test("Drops disposable production suffixes")
    func dropsDisposableSuffixes() {
        #expect(AudioTitleNormalizer.normalize("Deep Relaxation official") == "deep relaxation")
        #expect(AudioTitleNormalizer.normalize("Deep Relaxation HQ remastered") == "deep relaxation")
    }

    // The old normaliser stripped a leading number of up to three digits, so
    // every entry in a numbered series reduced to the same key and the importer
    // could not tell track 01 from track 02.
    @Test("Numbered series stay distinct")
    func numberedSeriesStayDistinct() {
        let first = AudioTitleNormalizer.normalize("01 Bambi Sleep")
        let second = AudioTitleNormalizer.normalize("02 Bambi Sleep")

        #expect(first != second)
        #expect(first == "01 bambi sleep")
    }

    @Test("Reads the leading track number when there is one")
    func readsLeadingTrackNumber() {
        #expect(AudioTitleNormalizer.leadingTrackNumber("02 Bambi Sleep") == 2)
        #expect(AudioTitleNormalizer.leadingTrackNumber("Bambi Sleep") == nil)
        // Four digits is a year or a catalogue code, not a track position.
        #expect(AudioTitleNormalizer.leadingTrackNumber("2024 Bambi Sleep") == nil)
    }

    @Test("An empty or punctuation-only name normalizes to empty")
    func emptyNameNormalizesToEmpty() {
        #expect(AudioTitleNormalizer.normalize("") == "")
        #expect(AudioTitleNormalizer.normalize("---.mp3") == "")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/AudioTitleNormalizerTests
```

Expected: build failure, `cannot find 'AudioTitleNormalizer' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Ilumionate/LibraryDedupe/AudioTitleNormalizer.swift`:

```swift
//
//  AudioTitleNormalizer.swift
//  Ilumionate
//
//  One normalisation, shared by playlist matching and duplicate detection.
//
//  These two used to normalise separately, and the extension-stripping half of
//  the job was open-coded in six or more places (see the note at
//  `IlumionateTests.swift:824`). Two callers disagreeing about what counts as
//  the same title is exactly how a duplicate slips through.
//

import Foundation

nonisolated enum AudioTitleNormalizer {

    /// Production noise that says nothing about which recording this is.
    private static let disposableSuffixes: Set<String> = [
        "audio", "final", "hq", "official", "remastered",
        "mp3", "m4a", "wav", "aac", "flac", "v2", "320kbps"
    ]

    /// A filename or title reduced to lowercase, unaccented, punctuation-free
    /// tokens.
    ///
    /// A leading track number is **kept**. Stripping it — which is what this
    /// code used to do — collapsed `01 Bambi Sleep` and `02 Bambi Sleep` onto
    /// the same key, so the importer could not tell one entry of a numbered
    /// series from another and downloaded a second copy of a track it had.
    static func normalize(_ value: String) -> String {
        tokens(in: value).joined(separator: " ")
    }

    /// The track position a name opens with, when it opens with one.
    ///
    /// Capped at three digits: four or more is a year or a catalogue number,
    /// not a position in a playlist.
    static func leadingTrackNumber(_ value: String) -> Int? {
        guard let first = tokens(in: value).first,
              first.count <= 3,
              first.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(first)
    }

    private static func tokens(in value: String) -> [String] {
        let base = URL(filePath: value)
            .deletingPathExtension()
            .lastPathComponent
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        var tokens = base
            .replacing(/[^a-z0-9]+/, with: " ")
            .split(separator: " ")
            .map(String.init)

        while let last = tokens.last, disposableSuffixes.contains(last) {
            tokens.removeLast()
        }
        return tokens
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/AudioTitleNormalizerTests
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/LibraryDedupe/AudioTitleNormalizer.swift IlumionateTests/AudioTitleNormalizerTests.swift
git commit -m "feat(dedupe): add a shared title normalizer that keeps track numbers

The importer's normalizer stripped a leading number of up to three
digits, so every entry in a numbered series reduced to the same key."
```

---

### Task 2: `RemoteAudioSource` on `AudioFile`

**Files:**
- Create: `Ilumionate/LibraryDedupe/RemoteAudioSource.swift`
- Modify: `Ilumionate/AudioFile.swift` (property, `CodingKeys`, `init`)
- Create: `IlumionateTests/RemoteAudioSourceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/RemoteAudioSourceTests.swift`:

```swift
//
//  RemoteAudioSourceTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct RemoteAudioSourceTests {
    @Test("Round-trips through the library encoding")
    func roundTripsThroughCoding() throws {
        let url = try #require(URL(string: "https://cdn.bambicloud.com/a.mp3"))
        var file = AudioFile(filename: "a.mp3", duration: 60, fileSize: 1_000)
        file.remoteSource = RemoteAudioSource(
            service: "bambicloud",
            trackID: "c311778b-d79b-4f3a-8729-3474cda134b4",
            url: url
        )

        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(AudioFile.self, from: data)

        #expect(decoded.remoteSource == file.remoteSource)
    }

    // Every library already stored on disk predates this field. Decoding must
    // not start failing for them.
    @Test("A stored file without provenance still decodes")
    func absentProvenanceDecodes() throws {
        let json = Data(
            """
            {"id":"\(UUID().uuidString)","filename":"a.mp3","duration":60,
             "fileSize":1000,"createdDate":0}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(AudioFile.self, from: json)

        #expect(decoded.remoteSource == nil)
        #expect(decoded.filename == "a.mp3")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/RemoteAudioSourceTests
```

Expected: build failure, `cannot find 'RemoteAudioSource' in scope`.

- [ ] **Step 3a: Create the value type**

Create `Ilumionate/LibraryDedupe/RemoteAudioSource.swift`:

```swift
//
//  RemoteAudioSource.swift
//  Ilumionate
//
//  Where a library file came from, when it was fetched rather than imported.
//
//  Without this, a second playlist sharing tracks with the first has nothing to
//  match on but the track's title, and a title that fails the importer's
//  similarity threshold becomes a download the user already has.
//

import Foundation

nonisolated struct RemoteAudioSource: Codable, Sendable, Equatable {
    /// The publisher, so two services cannot collide on a track identifier.
    let service: String
    /// The publisher's own identifier for the track. Survives every rename.
    let trackID: String
    let url: URL

    static let bambiCloudService = "bambicloud"
}
```

- [ ] **Step 3b: Add the property to `AudioFile`**

In `Ilumionate/AudioFile.swift`, add the stored property immediately after `contentFingerprint` (currently line 38):

```swift
    var contentFingerprint: String?
    /// Set when the file was fetched from a publisher rather than imported by
    /// the user. Optional so every previously stored library decodes unchanged.
    var remoteSource: RemoteAudioSource?
```

Add the coding key to the existing `CodingKeys` (currently line 68):

```swift
    enum CodingKeys: String, CodingKey {
        case id, filename, duration, fileSize, createdDate, contentFingerprint
        case remoteSource
        case transcription, analysisResult, deadTimeProfile
        case trackMetadata, userTitle
        case creator, isFavorite, rating, detailedRating, tags
        case lastPlayedDate, playCount, sessionNotes
    }
```

Add the parameter to the memberwise `init` (currently ends at line 80 with `contentFingerprint: String? = nil`):

```swift
         contentFingerprint: String? = nil,
         remoteSource: RemoteAudioSource? = nil) {
```

and assign it in the body, immediately after `self.contentFingerprint = contentFingerprint`:

```swift
        self.remoteSource = remoteSource
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/RemoteAudioSourceTests
```

Expected: PASS, 2 tests.

- [ ] **Step 5: Run the whole suite to check nothing regressed**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

Expected: PASS. `AudioFile` is constructed in many tests; the new parameter is defaulted, so none should need changing.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/LibraryDedupe/RemoteAudioSource.swift Ilumionate/AudioFile.swift IlumionateTests/RemoteAudioSourceTests.swift
git commit -m "feat(dedupe): record where a downloaded file came from

A publisher's own track identifier survives renames and re-encodes,
so a second playlist sharing tracks matches exactly instead of
falling back to fuzzy title comparison."
```

---

### Task 3: `DuplicateAudioIndex`

**Files:**
- Create: `Ilumionate/LibraryDedupe/DuplicateAudioCandidate.swift`
- Create: `Ilumionate/LibraryDedupe/DuplicateAudioVerdict.swift`
- Create: `Ilumionate/LibraryDedupe/DuplicateAudioIndex.swift`
- Create: `IlumionateTests/DuplicateAudioIndexTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/DuplicateAudioIndexTests.swift`:

```swift
//
//  DuplicateAudioIndexTests.swift
//  IlumionateTests
//
//  The rules that decide whether the library already holds a file are pinned
//  here — including the negatives, which are what keep a false positive from
//  silently binding a playlist to the wrong audio.
//

import Foundation
import Testing
@testable import Ilumionate

struct DuplicateAudioIndexTests {

    private func makeFile(
        filename: String = "Deep Relaxation.mp3",
        duration: TimeInterval = 600,
        fileSize: Int64 = 5_000_000,
        fingerprint: String? = nil,
        remoteSource: RemoteAudioSource? = nil,
        analyzed: Bool = false
    ) -> AudioFile {
        var file = AudioFile(
            filename: filename,
            duration: duration,
            fileSize: fileSize,
            contentFingerprint: fingerprint,
            remoteSource: remoteSource
        )
        if analyzed {
            file.transcription = "seeded"
        }
        return file
    }

    private func bambiSource(_ trackID: String) -> RemoteAudioSource {
        RemoteAudioSource(
            service: RemoteAudioSource.bambiCloudService,
            trackID: trackID,
            url: URL(string: "https://cdn.bambicloud.com/\(trackID).mp3")!
        )
    }

    // MARK: - Identical

    @Test("Same publisher track is identical, with no bytes fetched")
    func samePublisherTrackIsIdentical() {
        let source = bambiSource("track-1")
        let existing = makeFile(remoteSource: source)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                remoteSource: source,
                duration: 600,
                title: "Something Else Entirely"
            )
        )

        #expect(verdict == .identical(existing: existing.id))
    }

    @Test("A different publisher with the same track id does not match")
    func differentServiceDoesNotMatch() {
        let existing = makeFile(remoteSource: bambiSource("track-1"))
        let index = DuplicateAudioIndex([existing])

        let other = RemoteAudioSource(
            service: "someotherservice",
            trackID: "track-1",
            url: URL(string: "https://example.com/a.mp3")!
        )
        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                remoteSource: other,
                duration: 90,
                title: "Unrelated"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("Same fingerprint is identical, case-insensitively")
    func sameFingerprintIsIdentical() {
        let existing = makeFile(fingerprint: "ABCDEF123456")
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                contentFingerprint: "abcdef123456",
                duration: 12,
                title: "Renamed Completely"
            )
        )

        #expect(verdict == .identical(existing: existing.id))
    }

    // MARK: - Likely

    @Test("Byte-identical size with matching duration is a likely duplicate")
    func sameSizeAndDurationIsLikely() {
        let existing = makeFile(duration: 600, fileSize: 5_000_000)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 5_000_000,
                duration: 600.4,
                title: "Totally Different Name"
            )
        )

        #expect(verdict == .likely(existing: existing.id, reason: .sizeAndDuration))
    }

    @Test("Same normalized title with matching duration is a likely duplicate")
    func sameTitleAndDurationIsLikely() {
        let existing = makeFile(filename: "Deep Relaxation.mp3", duration: 600)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 9_999,
                duration: 601.5,
                title: "deep_relaxation"
            )
        )

        #expect(verdict == .likely(existing: existing.id, reason: .titleAndDuration))
    }

    // MARK: - Negatives

    @Test("Equal duration alone is not a duplicate")
    func equalDurationAloneIsDistinct() {
        let existing = makeFile(filename: "Morning Calm.mp3", duration: 600, fileSize: 1)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 2,
                duration: 600,
                title: "Evening Descent"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("Equal title with a clearly different duration is not a duplicate")
    func equalTitleDifferentDurationIsDistinct() {
        let existing = makeFile(filename: "Deep Relaxation.mp3", duration: 600, fileSize: 1)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 2,
                duration: 1_800,
                title: "Deep Relaxation"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("Numbered series entries are not duplicates of each other")
    func numberedSeriesAreDistinct() {
        let existing = makeFile(filename: "01 Bambi Sleep.mp3", duration: 600, fileSize: 1)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 2,
                duration: 600,
                title: "02 Bambi Sleep"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("An unreadable file with no fingerprint degrades rather than matching")
    func missingFingerprintDoesNotMatch() {
        let existing = makeFile(filename: "A.mp3", fingerprint: nil, analyzed: false)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                contentFingerprint: nil,
                fileSize: 1,
                duration: 3,
                title: "B"
            )
        )

        #expect(verdict == .distinct)
    }

    @Test("A zero file size never matches on size")
    func zeroSizeDoesNotMatchOnSize() {
        let existing = makeFile(filename: "A.mp3", duration: 600, fileSize: 0)
        let index = DuplicateAudioIndex([existing])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(
                fileSize: 0,
                duration: 600,
                title: "B"
            )
        )

        #expect(verdict == .distinct)
    }

    // MARK: - Determinism

    // Two stored entries can hold the same audio — that is the mess this
    // feature exists to clean up. Resolving to the analyzed copy matches how
    // `PlaylistTrackBinding` heals an orphaned playlist item.
    @Test("With two matches, the analyzed copy wins")
    func prefersTheAnalyzedCopy() {
        let plain = makeFile(filename: "A.mp3", fingerprint: "aa", analyzed: false)
        let analyzed = makeFile(filename: "A (1).mp3", fingerprint: "aa", analyzed: true)
        let index = DuplicateAudioIndex([plain, analyzed])

        let verdict = index.verdict(
            for: DuplicateAudioCandidate(contentFingerprint: "aa", duration: 600, title: "A")
        )

        #expect(verdict == .identical(existing: analyzed.id))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/DuplicateAudioIndexTests
```

Expected: build failure, `cannot find 'DuplicateAudioIndex' in scope`.

- [ ] **Step 3a: Create the candidate**

Create `Ilumionate/LibraryDedupe/DuplicateAudioCandidate.swift`:

```swift
//
//  DuplicateAudioCandidate.swift
//  Ilumionate
//
//  What is known about a file that has not entered the library yet.
//
//  Deliberately partial. Before a download only the publisher's identity, the
//  advertised size and the published duration exist; the fingerprint arrives
//  only once the bytes do. One type covers both moments so the caller does not
//  need two lookup methods that could disagree.
//

import Foundation

nonisolated struct DuplicateAudioCandidate: Sendable {
    var remoteSource: RemoteAudioSource?
    var contentFingerprint: String?
    /// Nil when the server did not report a length.
    var fileSize: Int64?
    var duration: TimeInterval
    /// A filename or a track title — `AudioTitleNormalizer` handles both.
    var title: String

    init(
        remoteSource: RemoteAudioSource? = nil,
        contentFingerprint: String? = nil,
        fileSize: Int64? = nil,
        duration: TimeInterval,
        title: String
    ) {
        self.remoteSource = remoteSource
        self.contentFingerprint = contentFingerprint
        self.fileSize = fileSize
        self.duration = duration
        self.title = title
    }
}
```

- [ ] **Step 3b: Create the verdict**

Create `Ilumionate/LibraryDedupe/DuplicateAudioVerdict.swift`:

```swift
//
//  DuplicateAudioVerdict.swift
//  Ilumionate
//

import Foundation

nonisolated enum DuplicateAudioVerdict: Equatable, Sendable {
    /// The library holds this exact audio. Safe to reuse without asking.
    case identical(existing: AudioFile.ID)
    /// Strong but circumstantial. Always shown to the user before acting.
    case likely(existing: AudioFile.ID, reason: Reason)
    case distinct

    nonisolated enum Reason: Equatable, Sendable {
        case sizeAndDuration
        case titleAndDuration
    }

    var existingID: AudioFile.ID? {
        switch self {
        case .identical(let id): id
        case .likely(let id, _): id
        case .distinct: nil
        }
    }
}
```

- [ ] **Step 3c: Create the index**

Create `Ilumionate/LibraryDedupe/DuplicateAudioIndex.swift`:

```swift
//
//  DuplicateAudioIndex.swift
//  Ilumionate
//
//  Answers one question: does the library already hold this audio?
//
//  A pure value over a library snapshot — no actor, no file access, no network.
//  Everything expensive (hashing, HEAD requests) happens in the caller, which
//  is what lets the cheap signals run before a download rather than after.
//

import Foundation

nonisolated struct DuplicateAudioIndex: Sendable {

    /// How far two durations may drift and still describe the same recording.
    /// Tighter for the size rule, because an exact byte-count match is already
    /// nearly conclusive and the duration only guards against coincidence.
    private static let sizeMatchDurationTolerance: TimeInterval = 1
    private static let titleMatchDurationTolerance: TimeInterval = 2

    private let entries: [Entry]

    init(_ files: [AudioFile]) {
        entries = files.map(Entry.init)
    }

    func verdict(for candidate: DuplicateAudioCandidate) -> DuplicateAudioVerdict {
        if let source = candidate.remoteSource,
           let match = best(where: { $0.file.remoteSource == source }) {
            return .identical(existing: match.file.id)
        }

        if let fingerprint = candidate.contentFingerprint?.lowercased(),
           !fingerprint.isEmpty,
           let match = best(where: { $0.fingerprint == fingerprint }) {
            return .identical(existing: match.file.id)
        }

        if let size = candidate.fileSize,
           size > 0,
           let match = best(where: {
               $0.file.fileSize == size
                   && abs($0.file.duration - candidate.duration) <= Self.sizeMatchDurationTolerance
           }) {
            return .likely(existing: match.file.id, reason: .sizeAndDuration)
        }

        let title = AudioTitleNormalizer.normalize(candidate.title)
        if !title.isEmpty,
           let match = best(where: {
               $0.title == title
                   && abs($0.file.duration - candidate.duration) <= Self.titleMatchDurationTolerance
           }) {
            return .likely(existing: match.file.id, reason: .titleAndDuration)
        }

        return .distinct
    }

    /// The richest entry satisfying `predicate`.
    ///
    /// The library can legitimately hold two rows for one recording — that is
    /// the state this feature cleans up — so a match must resolve the same way
    /// every time. Preferring the analyzed copy matches how
    /// `PlaylistTrackBinding.resolve` heals an orphaned playlist item, and
    /// keeps a rebind from landing on the copy with no light session.
    private func best(where predicate: (Entry) -> Bool) -> Entry? {
        entries
            .filter(predicate)
            .min { lhs, rhs in
                if lhs.file.isAnalyzed != rhs.file.isAnalyzed {
                    return lhs.file.isAnalyzed
                }
                if lhs.file.hasTranscription != rhs.file.hasTranscription {
                    return lhs.file.hasTranscription
                }
                return lhs.file.createdDate < rhs.file.createdDate
            }
    }

    /// Normalisation is done once per library entry rather than once per
    /// comparison — a playlist import queries this for every unmatched row.
    private struct Entry {
        let file: AudioFile
        let fingerprint: String?
        let title: String

        init(_ file: AudioFile) {
            self.file = file
            fingerprint = file.contentFingerprint?.lowercased()
            title = AudioTitleNormalizer.normalize(file.filename)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/DuplicateAudioIndexTests
```

Expected: PASS, 11 tests.

- [ ] **Step 5: Run both destinations**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

Expected: PASS on both.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/LibraryDedupe/ IlumionateTests/DuplicateAudioIndexTests.swift
git commit -m "feat(dedupe): add the duplicate verdict index

Four signals in priority order: publisher track identity, content
fingerprint, byte size with duration, normalized title with duration.
The first two are conclusive; the last two are always reviewed."
```

---

## Phase 2 — Enforcement at the import doors

Now the index is wired in, and behaviour changes.

### Task 4: The downloader records identity

Fixes spec root cause 3. Split from Task 5 so the reordering lands on its own.

**Files:**
- Modify: `Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift`
- Modify: `IlumionateTests/PlaylistTrackDownloaderTests.swift`

- [ ] **Step 1: Write the failing test**

Append to the `PlaylistTrackDownloaderTests` struct in `IlumionateTests/PlaylistTrackDownloaderTests.swift`:

```swift
    @Test("A saved download carries its fingerprint and its provenance")
    func savedDownloadCarriesIdentity() async throws {
        let track = try makeTrack(audioURL: "https://cdn.bambicloud.com/a.mp3")
        let documents = try temporaryDirectory()
        let payload = Data("audio-bytes".utf8)

        let downloader = PlaylistTrackDownloader(documentsURL: documents) { _ in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try payload.write(to: temp)
            return (temp, URLResponse())
        }

        let audioFile = try await downloader.download(track)

        #expect(audioFile.contentFingerprint?.count == 64)
        #expect(audioFile.remoteSource?.service == RemoteAudioSource.bambiCloudService)
        #expect(audioFile.remoteSource?.trackID == track.id.uuidString)
        #expect(audioFile.remoteSource?.url.absoluteString == "https://cdn.bambicloud.com/a.mp3")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PlaylistTrackDownloaderTests/savedDownloadCarriesIdentity()
```

Expected: FAIL — `contentFingerprint` is nil, so `.count == 64` is false.

- [ ] **Step 3: Write minimal implementation**

In `Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift`, replace the `return AudioFile(...)` at the end of `download` (currently lines 106–110) with:

```swift
        return AudioFile(
            filename: destination.lastPathComponent,
            duration: await measuredDuration(of: destination, fallback: track.duration),
            fileSize: Int64(byteCount),
            contentFingerprint: AudioFingerprintService.computeFingerprint(for: destination),
            remoteSource: RemoteAudioSource(
                service: RemoteAudioSource.bambiCloudService,
                trackID: track.id.uuidString,
                url: source
            )
        )
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PlaylistTrackDownloaderTests
```

Expected: PASS, all existing tests plus the new one.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift IlumionateTests/PlaylistTrackDownloaderTests.swift
git commit -m "feat(dedupe): fingerprint downloaded tracks and record their source

A downloaded file previously carried no content identity at all until
some later library scan backfilled it."
```

---

### Task 5: The downloader checks before writing to Documents

Fixes spec root causes 2 and 3. **This is the task that stops `Name (1).mp3` existing.**

**Files:**
- Modify: `Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift`
- Modify: `IlumionateTests/PlaylistTrackDownloaderTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `PlaylistTrackDownloaderTests`:

```swift
    // The whole point of the feature: identical bytes must not become a second
    // file on disk. The old code called `uniqueDestination` first and so had
    // already created "Rapid Induction (1).mp3" before anything could object.
    @Test("Downloading content the library already holds writes nothing")
    func identicalContentIsNotSavedTwice() async throws {
        let track = try makeTrack(audioURL: "https://cdn.bambicloud.com/a.mp3")
        let documents = try temporaryDirectory()
        let payload = Data("audio-bytes".utf8)

        let downloader = PlaylistTrackDownloader(documentsURL: documents) { _ in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try payload.write(to: temp)
            return (temp, URLResponse())
        }

        let first = try await downloader.download(track)
        guard case .saved(let savedFile) = first else {
            Issue.record("First download should save")
            return
        }

        let second = try await downloader.download(
            track,
            existing: DuplicateAudioIndex([savedFile])
        )

        #expect(second == .alreadyInLibrary(existing: savedFile.id))

        let contents = try FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: nil
        )
        #expect(contents.count == 1)
        #expect(contents.contains { $0.lastPathComponent.contains("(1)") } == false)
    }

    @Test("A distinct track still saves normally")
    func distinctContentStillSaves() async throws {
        let track = try makeTrack(audioURL: "https://cdn.bambicloud.com/a.mp3")
        let documents = try temporaryDirectory()

        let downloader = PlaylistTrackDownloader(documentsURL: documents) { _ in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data("unique-bytes".utf8).write(to: temp)
            return (temp, URLResponse())
        }

        let outcome = try await downloader.download(
            track,
            existing: DuplicateAudioIndex([])
        )

        guard case .saved(let file) = outcome else {
            Issue.record("A distinct track should save")
            return
        }
        #expect(file.filename == "Rapid Induction.mp3")
    }
```

The first test uses `case .saved(...)` on the result of a plain `download(track)` call, so `download` must return the outcome enum for every caller. Update the two existing tests that bind the result directly — `savedDownloadCarriesIdentity` from Task 4 becomes:

```swift
    @Test("A saved download carries its fingerprint and its provenance")
    func savedDownloadCarriesIdentity() async throws {
        let track = try makeTrack(audioURL: "https://cdn.bambicloud.com/a.mp3")
        let documents = try temporaryDirectory()

        let downloader = PlaylistTrackDownloader(documentsURL: documents) { _ in
            let temp = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try Data("audio-bytes".utf8).write(to: temp)
            return (temp, URLResponse())
        }

        guard case .saved(let audioFile) = try await downloader.download(track) else {
            Issue.record("Expected the track to be saved")
            return
        }

        #expect(audioFile.contentFingerprint?.count == 64)
        #expect(audioFile.remoteSource?.service == RemoteAudioSource.bambiCloudService)
        #expect(audioFile.remoteSource?.trackID == track.id.uuidString)
        #expect(audioFile.remoteSource?.url.absoluteString == "https://cdn.bambicloud.com/a.mp3")
    }
```

Tests that assert a `throws` behaviour (`trackWithoutAudioURLReportsNoSource`, `offDomainSourceIsRefusedWithoutRequesting`) need no change.

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PlaylistTrackDownloaderTests
```

Expected: build failure — `download` has no `existing:` parameter and returns `AudioFile`, not a pattern-matchable enum.

- [ ] **Step 3a: Add the outcome type**

At the top of `Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift`, after the imports:

```swift
/// What a download resolved to.
///
/// A download that turns out to duplicate audio the library already holds is a
/// success, not a failure — the playlist row it was fetched for gets the copy
/// that already carries the user's analysis, rating and play count.
nonisolated enum PlaylistTrackDownloadOutcome: Sendable, Equatable {
    case saved(AudioFile)
    case alreadyInLibrary(existing: AudioFile.ID)
}
```

`AudioFile` must be `Equatable` for this. If the compiler complains that it is not, add the conformance to the declaration in `Ilumionate/AudioFile.swift`:

```swift
nonisolated struct AudioFile: Identifiable, Codable, Sendable, Equatable {
```

If any nested stored property blocks synthesis, implement equality on identity instead, which is all this enum needs:

```swift
extension AudioFile: Equatable {
    nonisolated static func == (lhs: AudioFile, rhs: AudioFile) -> Bool {
        lhs.id == rhs.id
    }
}
```

- [ ] **Step 3b: Reorder `download` so the check precedes the move**

Replace the body of `download` in `Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift` (currently lines 64–111) with:

```swift
    /// Fetches a track, unless the library already holds it.
    ///
    /// The duplicate check sits between the transfer and the move into
    /// `Documents`. It used to sit nowhere at all: `uniqueDestination` ran
    /// first, so a file the user already had was written a second time as
    /// "Name (1).mp3" before anything had a chance to object.
    func download(
        _ track: BambiCloudPlaylist.Track,
        allowingLargeFile: Bool = false,
        existing: DuplicateAudioIndex = DuplicateAudioIndex([])
    ) async throws -> PlaylistTrackDownloadOutcome {
        let source = try validatedSource(for: track)

        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await load(source)
        } catch let error as PlaylistTrackDownloadError {
            throw error
        } catch {
            throw PlaylistTrackDownloadError.networkUnavailable
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PlaylistTrackDownloadError.networkUnavailable
        }
        if !allowingLargeFile,
           response.expectedContentLength > Self.confirmationThresholdBytes {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PlaylistTrackDownloadError.confirmationRequired(
                byteCount: response.expectedContentLength
            )
        }

        let temporaryByteCount = Int64(
            (try? temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        )
        if !allowingLargeFile, temporaryByteCount > Self.confirmationThresholdBytes {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PlaylistTrackDownloadError.confirmationRequired(
                byteCount: temporaryByteCount
            )
        }

        let fingerprint = AudioFingerprintService.computeFingerprint(for: temporaryURL)
        let remoteSource = RemoteAudioSource(
            service: RemoteAudioSource.bambiCloudService,
            trackID: track.id.uuidString,
            url: source
        )

        let verdict = existing.verdict(
            for: DuplicateAudioCandidate(
                remoteSource: remoteSource,
                contentFingerprint: fingerprint,
                fileSize: temporaryByteCount,
                duration: track.duration,
                title: track.name
            )
        )
        // Only a conclusive verdict discards bytes already paid for. A merely
        // likely one is the user's call, and reaches them as a review row.
        if case .identical(let existingID) = verdict {
            try? FileManager.default.removeItem(at: temporaryURL)
            return .alreadyInLibrary(existing: existingID)
        }

        let destination = uniqueDestination(for: track, source: source)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw PlaylistTrackDownloadError.couldNotSave
        }

        return .saved(
            AudioFile(
                filename: destination.lastPathComponent,
                duration: await measuredDuration(of: destination, fallback: track.duration),
                fileSize: temporaryByteCount,
                contentFingerprint: fingerprint,
                remoteSource: remoteSource
            )
        )
    }
```

Note the size ceiling now reads the temp file *before* the move, so the "server under-reported" path no longer needs a file already sitting in `Documents` to be removed.

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PlaylistTrackDownloaderTests
```

Expected: PASS. If the app target fails to build, `BambiCloudPlaylistImportViewModel.downloadRow` is still binding `AudioFile` from `download` — Task 6 fixes that. Complete Task 6 before committing if so.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/PlaylistImport/PlaylistTrackDownloader.swift Ilumionate/AudioFile.swift IlumionateTests/PlaylistTrackDownloaderTests.swift
git commit -m "fix(dedupe): check for a duplicate before writing to Documents

uniqueDestination ran first, so a track the user already had was
written as 'Name (1).mp3' before anything could object. The check now
sits between the transfer and the move, and identical bytes are
discarded with the row bound to the copy already in the library."
```

---

### Task 6: The import view model checks before the request

**Files:**
- Modify: `Ilumionate/PlaylistImport/BambiCloudPlaylistImportViewModel.swift`
- Modify: `IlumionateTests/BambiCloudPlaylistImportTests.swift`

- [ ] **Step 1: Write the failing test**

Append to the `BambiCloudPlaylistImportTests` struct:

```swift
    // The user's actual complaint: a second playlist sharing tracks with the
    // first re-downloaded every one of them. Provenance makes that free.
    @Test func aPreviouslyDownloadedTrackIsNotRequestedAgain() async throws {
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let trackID = try #require(UUID(uuidString: "c311778b-d79b-4f3a-8729-3474cda134b4"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"Second",
             "files":[{"uuid":"\(trackID.uuidString.lowercased())","name":"Shared Track",
             "duration":600000,"audioURL":"https://cdn.bambicloud.com/shared.mp3","trackNum":1}]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        var owned = AudioFile(
            filename: "Something The Matcher Will Never Guess.mp3",
            duration: 600,
            fileSize: 5_000_000
        )
        owned.remoteSource = RemoteAudioSource(
            service: RemoteAudioSource.bambiCloudService,
            trackID: trackID.uuidString,
            url: try #require(URL(string: "https://cdn.bambicloud.com/shared.mp3"))
        )

        let model = BambiCloudPlaylistImportViewModel(
            availableAudioFiles: [owned],
            downloader: PlaylistTrackDownloader(
                documentsURL: URL.temporaryDirectory
            ) { _ in
                Issue.record("A track already in the library was downloaded again")
                throw PlaylistTrackDownloadError.networkUnavailable
            },
            isAutoAnalyseEnabled: { false }
        )
        model.adoptPlanForTesting(
            BambiCloudPlaylistImporter().makePlan(
                for: playlist,
                availableAudioFiles: [owned]
            )
        )

        let row = try #require(model.plan?.rows.first)
        await model.downloadRow(row)

        #expect(model.plan?.rows.first?.selectedAudioFileID == owned.id)
        #expect(model.plan?.rows.first?.status == .exact)
        #expect(model.downloadErrors.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/BambiCloudPlaylistImportTests/aPreviouslyDownloadedTrackIsNotRequestedAgain()
```

Expected: FAIL — `Issue.record` fires, the loader was called.

- [ ] **Step 3: Write minimal implementation**

In `Ilumionate/PlaylistImport/BambiCloudPlaylistImportViewModel.swift`, replace `downloadRow` (currently lines 160–198) with:

```swift
    /// Fills a row the matcher could not resolve — from the library when the
    /// track is already there, and from the publisher only when it is not.
    func downloadRow(
        _ row: BambiCloudPlaylistImportPlan.Row,
        allowingLargeFile: Bool = false
    ) async {
        guard !downloadingRowIDs.contains(row.id) else { return }

        let index = DuplicateAudioIndex(availableAudioFiles)

        // Free, and it runs before any request: a track fetched from a previous
        // playlist is recognised by the publisher's own identifier.
        if let audioURL = row.track.audioURL {
            let verdict = index.verdict(
                for: DuplicateAudioCandidate(
                    remoteSource: RemoteAudioSource(
                        service: RemoteAudioSource.bambiCloudService,
                        trackID: row.track.id.uuidString,
                        url: audioURL
                    ),
                    duration: row.track.duration,
                    title: row.track.name
                )
            )
            if case .identical(let existingID) = verdict {
                plan?.select(audioFileID: existingID, forRow: row.id)
                plan?.markResolvedAsExisting(rowID: row.id)
                return
            }
        }

        downloadingRowIDs.insert(row.id)
        downloadErrors[row.id] = nil
        defer { downloadingRowIDs.remove(row.id) }

        do {
            let outcome = try await downloader.download(
                row.track,
                allowingLargeFile: allowingLargeFile,
                existing: index
            )

            switch outcome {
            case .alreadyInLibrary(let existingID):
                plan?.select(audioFileID: existingID, forRow: row.id)
                plan?.markResolvedAsExisting(rowID: row.id)

            case .saved(let audioFile):
                // Re-read the library so a download never clobbers changes made
                // elsewhere while this sheet has been open.
                var library = AudioLibraryStore.load()
                library.insert(audioFile, at: 0)
                await AudioLibraryStore.save(library)

                availableAudioFiles.insert(audioFile, at: 0)
                plan?.adopt(downloadedFile: audioFile, forRow: row.id)
                await queueForAnalysis(audioFile)
            }
        } catch PlaylistTrackDownloadError.confirmationRequired(let byteCount) {
            // The server under-reported the size up front; ask rather than fail.
            pendingDownload = PendingLargeDownload(
                scope: .row(id: row.id, name: row.track.name),
                byteCount: byteCount
            )
        } catch let error as PlaylistTrackDownloadError {
            downloadErrors[row.id] = error.errorDescription
        } catch {
            downloadErrors[row.id] = PlaylistTrackDownloadError
                .networkUnavailable
                .localizedDescription
        }
    }
```

Add the supporting mutator to `Ilumionate/PlaylistImport/BambiCloudPlaylistImportPlan.swift`, after `select(audioFileID:forRow:)`:

```swift
    /// Marks a row filled from audio the library already held.
    ///
    /// `select` reports `.manual` because it is the user's own choice; a
    /// duplicate resolved automatically is an exact match, and reads as one.
    mutating func markResolvedAsExisting(rowID: Row.ID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }),
              rows[index].selectedAudioFileID != nil else {
            return
        }
        rows[index].status = .exact
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/BambiCloudPlaylistImportTests
```

Expected: PASS.

- [ ] **Step 5: Run the whole suite on both destinations**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

Expected: PASS on both.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/PlaylistImport/BambiCloudPlaylistImportViewModel.swift Ilumionate/PlaylistImport/BambiCloudPlaylistImportPlan.swift IlumionateTests/BambiCloudPlaylistImportTests.swift
git commit -m "feat(dedupe): resolve known tracks before any network request

A track fetched from an earlier playlist is recognised by the
publisher's own identifier, so a second playlist sharing tracks
costs no bytes."
```

---

### Task 7: The Files picker stops inventing `(1)` names

Fixes spec root cause 2 on the second import door.

**Files:**
- Modify: `Ilumionate/AudioImportWorker.swift`
- Modify: `Ilumionate/AudioManager.swift`
- Modify: `IlumionateTests/AudioImportWorkerTests.swift`

- [ ] **Step 1: Write the failing test**

Append to the test struct in `IlumionateTests/AudioImportWorkerTests.swift`:

```swift
    @Test("Importing the same file twice does not create a second copy")
    func identicalImportIsRecognized() async throws {
        let documents = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)

        let source = documents.appending(path: "source.mp3")
        try Data("audio-bytes".utf8).write(to: source)

        let first = try await AudioImportWorker.prepareAudioFile(
            from: source,
            targetFilename: "Track.mp3",
            transferMode: .copy,
            durationTimeout: .seconds(1),
            documentsURL: documents
        )
        guard case .imported(let importedFile) = first else {
            Issue.record("The first import should produce a file")
            return
        }

        let second = try await AudioImportWorker.prepareAudioFile(
            from: source,
            targetFilename: "Track.mp3",
            transferMode: .copy,
            durationTimeout: .seconds(1),
            documentsURL: documents,
            existing: DuplicateAudioIndex([importedFile])
        )

        #expect(second == .alreadyInLibrary(existing: importedFile.id))

        let stored = try FileManager.default.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: nil
        )
        #expect(stored.contains { $0.lastPathComponent == "Track (1).mp3" } == false)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/AudioImportWorkerTests
```

Expected: build failure — `prepareAudioFile` has no `documentsURL:` or `existing:` parameter and returns `AudioFile`.

- [ ] **Step 3a: Add the outcome and the check**

In `Ilumionate/AudioImportWorker.swift`, add after the `AudioFileTransferOperation` typealias:

```swift
/// What an import resolved to.
nonisolated enum AudioImportOutcome: Sendable, Equatable {
    case imported(AudioFile)
    case alreadyInLibrary(existing: AudioFile.ID)
}
```

Replace `prepareAudioFile` (currently lines 26–70) with:

```swift
    @concurrent
    static func prepareAudioFile(
        from sourceURL: URL,
        targetFilename: String,
        transferMode: AudioFileTransferMode,
        durationTimeout: Duration,
        documentsURL: URL = .documentsDirectory,
        existing: DuplicateAudioIndex = DuplicateAudioIndex([]),
        transferOperation: AudioFileTransferOperation? = nil
    ) async throws -> AudioImportOutcome {
        // Hashed at the source, before anything is written. Copying first and
        // checking after is how `Track (1).mp3` used to come into existence.
        let sourceFingerprint = AudioFingerprintService.computeFingerprint(for: sourceURL)
        let sourceSize = Int64(
            (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        )
        let verdict = existing.verdict(
            for: DuplicateAudioCandidate(
                contentFingerprint: sourceFingerprint,
                fileSize: sourceSize,
                duration: 0,
                title: targetFilename
            )
        )
        if case .identical(let existingID) = verdict {
            Log.audio.info("↩️ Already in the library, not copied: \(targetFilename, privacy: .public)")
            return .alreadyInLibrary(existing: existingID)
        }

        let destinationURL = uniqueDestinationURL(for: targetFilename, in: documentsURL)

        do {
            if let transferOperation {
                try transferOperation(sourceURL, destinationURL, transferMode)
            } else {
                switch transferMode {
                case .copy:
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                case .move:
                    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                }
            }
            Log.audio.info("📁 Audio stored at: \(destinationURL.path)")

            try Task.checkCancellation()
            let resources = try destinationURL.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Int64(resources.fileSize ?? 0)

            async let duration = loadDuration(
                from: destinationURL,
                timeout: durationTimeout
            )
            async let metadata = AudioMetadataExtractor.metadata(from: destinationURL)

            return await .imported(
                AudioFile(
                    filename: destinationURL.lastPathComponent,
                    duration: duration,
                    fileSize: fileSize,
                    trackMetadata: metadata,
                    contentFingerprint: sourceFingerprint
                        ?? AudioFingerprintService.computeFingerprint(for: destinationURL)
                )
            )
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }
```

Update `uniqueDestinationURL` to take the directory, so tests are not writing into the real `Documents`:

```swift
    /// Still needed: a genuinely different recording can share a filename with
    /// one already stored. What changed is that a *duplicate* no longer reaches
    /// this function — it is resolved before anything is written.
    private static func uniqueDestinationURL(for filename: String, in documentsURL: URL) -> URL {
        let originalURL = documentsURL.appending(path: filename)
        var candidate = originalURL
        var counter = 1

        while FileManager.default.fileExists(atPath: candidate.path) {
            let baseName = originalURL.deletingPathExtension().lastPathComponent
            let fileExtension = originalURL.pathExtension
            let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
            candidate = originalURL.deletingLastPathComponent()
                .appending(path: "\(baseName) (\(counter))\(suffix)")
            counter += 1
        }
        return candidate
    }
```

Delete the now-unused private `fingerprint(for:)` helper at the end of the file (currently lines 118–121) — the fingerprint is computed from the source above.

- [ ] **Step 3b: Update the two callers in `AudioManager`**

In `Ilumionate/AudioManager.swift`, `importAudio` becomes:

```swift
    func importAudio(from url: URL) async -> AudioFile? {
        do {
            let outcome = try await AudioImportWorker.prepareAudioFile(
                from: url,
                targetFilename: url.lastPathComponent,
                transferMode: .copy,
                durationTimeout: .seconds(3),
                existing: DuplicateAudioIndex(AudioLibraryStore.load())
            )

            switch outcome {
            case .alreadyInLibrary(let existingID):
                Log.audio.info("↩️ Already in the library: \(url.lastPathComponent, privacy: .public)")
                return AudioLibraryStore.load().first { $0.id == existingID }

            case .imported(let audioFile):
                let restoredAudioFile = AnalysisStateManager.shared.restoringCachedData(in: audioFile)
                if restoredAudioFile.isAnalyzed {
                    Log.audio.info("⚡ Restored cached analysis for: \(audioFile.filename)")
                }

                Log.audio.info("✅ Imported audio: \(audioFile.filename) (Duration: \(audioFile.duration)s)")
                UsageAnalytics.shared.audioImported(source: .files)
                return restoredAudioFile
            }
        } catch {
            Log.audio.info("❌ Failed to import audio: \(error)")
            UsageAnalytics.shared.errorOccurred(.audioFileImportFailed)
            return nil
        }
    }
```

In `downloadAudio`, the `prepareAudioFile` call (currently lines 205–210) becomes:

```swift
            let outcome = try await AudioImportWorker.prepareAudioFile(
                from: tempURL,
                targetFilename: targetName,
                transferMode: .move,
                durationTimeout: .seconds(5),
                existing: DuplicateAudioIndex(AudioLibraryStore.load())
            )

            guard case .imported(let audioFile) = outcome else {
                if case .alreadyInLibrary(let existingID) = outcome {
                    try? FileManager.default.removeItem(at: tempURL)
                    Log.audio.info("↩️ Downloaded audio was already in the library")
                    return AudioLibraryStore.load().first { $0.id == existingID }
                }
                return nil
            }
```

The remainder of `downloadAudio` after that point is unchanged and still refers to `audioFile`.

`addAudioFile` in `Ilumionate/AudioLibraryView+Actions.swift` must not insert a file that is already present. Replace it with:

```swift
    func addAudioFile(_ file: AudioFile) async {
        guard !audioFiles.contains(where: { $0.id == file.id }) else {
            Log.audio.info("↩️ Already in the library, not added again: \(file.filename)")
            return
        }
        let reviewedFile = KnownAudioCatalog.shared.applyingReviewedAnalysis(to: file) ?? file
        audioFiles.insert(reviewedFile, at: 0)
        await saveAudioFiles()
        Log.audio.info("✅ Added audio file: \(reviewedFile.filename)")
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

Expected: PASS. Existing `AudioImportWorkerTests` that bind the return value directly need the `case .imported(let file)` pattern — update each one you find.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AudioImportWorker.swift Ilumionate/AudioManager.swift Ilumionate/AudioLibraryView+Actions.swift IlumionateTests/AudioImportWorkerTests.swift
git commit -m "fix(dedupe): recognise a duplicate in the Files picker path

The source file is hashed before anything is copied, so re-importing
a file resolves to the library copy instead of writing 'Track (1).mp3'."
```

---

## Phase 3 — Matcher corrections

### Task 8: Use the shared normaliser and the CDN filename

Fixes spec root causes 4 and 5 in the matcher itself.

**Files:**
- Modify: `Ilumionate/PlaylistImport/BambiCloudPlaylistImporter.swift`
- Modify: `IlumionateTests/BambiCloudPlaylistImportTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `BambiCloudPlaylistImportTests`:

```swift
    // With the old normalizer both local files reduced to "bambi sleep", so
    // row 01 claimed one, row 02 found it taken, and row 02 was downloaded.
    @Test func aNumberedSeriesMatchesRowForRow() throws {
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"Series","files":[
             {"uuid":"\(UUID().uuidString)","name":"01 Bambi Sleep","duration":600000,"trackNum":1},
             {"uuid":"\(UUID().uuidString)","name":"02 Bambi Sleep","duration":600000,"trackNum":2}
            ]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        let first = AudioFile(filename: "01 Bambi Sleep.mp3", duration: 600, fileSize: 1)
        let second = AudioFile(filename: "02 Bambi Sleep.mp3", duration: 600, fileSize: 2)

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: [first, second]
        )

        #expect(plan.rows[0].selectedAudioFileID == first.id)
        #expect(plan.rows[1].selectedAudioFileID == second.id)
        #expect(plan.downloadableRows.isEmpty)
    }

    @Test func theSourceFilenameMatchesWhenTheTitleDoesNot() throws {
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"P","files":[
             {"uuid":"\(UUID().uuidString)","name":"Bambi Sleep — Uniform Acceptance",
              "duration":600000,
              "audioURL":"https://cdn.bambicloud.com/bs-uniform-acceptance.mp3","trackNum":1}
            ]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        let local = AudioFile(
            filename: "bs-uniform-acceptance.mp3",
            duration: 600,
            fileSize: 1
        )

        let plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: [local]
        )

        #expect(plan.rows[0].selectedAudioFileID == local.id)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/BambiCloudPlaylistImportTests
```

Expected: FAIL — `aNumberedSeriesMatchesRowForRow` leaves row 1 unselected; `theSourceFilenameMatchesWhenTheTitleDoesNot` leaves row 0 unselected.

- [ ] **Step 3: Write minimal implementation**

In `Ilumionate/PlaylistImport/BambiCloudPlaylistImporter.swift`:

Delete the private `normalize(_:)` function entirely (currently lines 172–204) and replace every `normalize(` call with `AudioTitleNormalizer.normalize(`.

Replace `matchScore` (currently lines 96–135) with:

```swift
    private func matchScore(
        track: BambiCloudPlaylist.Track,
        audioFile: AudioFile
    ) -> Double {
        let remoteTitle = AudioTitleNormalizer.normalize(track.name)
        guard remoteTitle.count >= 4 else { return 0 }
        guard !hasTrackNumberConflict(track: track, audioFile: audioFile) else { return 0 }

        var localTitles = [
            audioFile.filename,
            audioFile.displayName,
            audioFile.userTitle,
            audioFile.trackMetadata?.embeddedTitle,
            audioFile.trackMetadata?.generatedTitle,
            // The name the publisher's own CDN uses. A file fetched from that
            // URL usually carries exactly this, and it was previously ignored.
            track.audioURL?.lastPathComponent
        ]
        if let catalogTitle = KnownAudioCatalog.shared
            .match(audioFile: audioFile)?
            .entry.title {
            localTitles.append(catalogTitle)
        }

        let titleScore = localTitles
            .compactMap { $0 }
            .map(AudioTitleNormalizer.normalize)
            .map { titleSimilarity(remote: remoteTitle, local: $0) }
            .max() ?? 0
        guard titleScore >= 0.55 else { return 0 }

        let allowedDifference = max(3, track.duration * 0.01)
        let durationDifference = abs(track.duration - audioFile.duration)
        let durationBonus: Double
        if durationDifference <= allowedDifference {
            durationBonus = 0.06
        } else if durationDifference <= max(10, track.duration * 0.03) {
            durationBonus = 0.03
        } else {
            durationBonus = 0
        }

        return min(titleScore + durationBonus, 1)
    }

    /// True when both sides state a track position and the positions disagree.
    ///
    /// A numbered series is otherwise near-indistinguishable: every entry
    /// shares the same words, so title similarity alone ranks the wrong file
    /// as highly as the right one.
    private func hasTrackNumberConflict(
        track: BambiCloudPlaylist.Track,
        audioFile: AudioFile
    ) -> Bool {
        let localNumber = AudioTitleNormalizer.leadingTrackNumber(audioFile.filename)
            ?? AudioTitleNormalizer.leadingTrackNumber(audioFile.displayName)
        guard let localNumber else { return false }

        let remoteNumber = AudioTitleNormalizer.leadingTrackNumber(track.name)
            ?? track.trackNumber
        guard let remoteNumber else { return false }

        return localNumber != remoteNumber
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/BambiCloudPlaylistImportTests
```

Expected: PASS, including the pre-existing `duplicateLocalTitlesWaitForManualSelection`.

- [ ] **Step 5: Run both destinations, then commit**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

```bash
git add Ilumionate/PlaylistImport/BambiCloudPlaylistImporter.swift IlumionateTests/BambiCloudPlaylistImportTests.swift
git commit -m "fix(import): match numbered series and the publisher's filename

Track positions on both sides must agree, and the CDN filename joins
the candidate titles. A numbered series previously matched only its
first entry and downloaded the rest."
```

---

## Phase 4 — Review row for probable matches

### Task 9: `.possibleDuplicate` status

**Files:**
- Modify: `Ilumionate/PlaylistImport/BambiCloudPlaylistImportPlan.swift`
- Modify: `Ilumionate/PlaylistImport/BambiCloudPlaylistImportViewModel.swift`
- Modify: `IlumionateTests/BambiCloudPlaylistImportTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `BambiCloudPlaylistImportTests`:

```swift
    @Test func aLikelyDuplicateIsOfferedRatherThanDownloaded() async throws {
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"P","files":[
             {"uuid":"\(UUID().uuidString)","name":"Renamed Beyond Recognition","duration":600000,
              "audioURL":"https://cdn.bambicloud.com/x.mp3","trackNum":1}
            ]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        // Same byte size and duration — strong, but not conclusive.
        let owned = AudioFile(
            filename: "Original Name.mp3",
            duration: 600,
            fileSize: 5_000_000
        )

        let model = BambiCloudPlaylistImportViewModel(
            availableAudioFiles: [owned],
            downloader: PlaylistTrackDownloader(
                documentsURL: URL.temporaryDirectory,
                probe: { _ in
                    (Data(), URLResponse(
                        url: URL(string: "https://cdn.bambicloud.com/x.mp3")!,
                        mimeType: nil,
                        expectedContentLength: 5_000_000,
                        textEncodingName: nil
                    ))
                }
            ) { _ in
                Issue.record("A likely duplicate was downloaded without asking")
                throw PlaylistTrackDownloadError.networkUnavailable
            },
            isAutoAnalyseEnabled: { false }
        )
        model.adoptPlanForTesting(
            BambiCloudPlaylistImporter().makePlan(
                for: playlist,
                availableAudioFiles: [owned]
            )
        )

        let row = try #require(model.plan?.rows.first)
        await model.requestDownload(of: row)

        #expect(model.plan?.rows.first?.status == .possibleDuplicate(existing: owned.id))
        #expect(model.plan?.rows.first?.selectedAudioFileID == nil)
    }

    @Test func useExistingResolvesAPossibleDuplicate() throws {
        let owned = AudioFile(filename: "Original Name.mp3", duration: 600, fileSize: 5_000_000)
        let playlistID = try #require(UUID(uuidString: "69b12112-e603-428a-aeb5-9f204481da13"))
        let data = Data(
            """
            {"playlists":[{"uuid":"\(playlistID.uuidString.lowercased())","name":"P","files":[
             {"uuid":"\(UUID().uuidString)","name":"Renamed Beyond Recognition","duration":600000,
              "audioURL":"https://cdn.bambicloud.com/x.mp3","trackNum":1}]}]}
            """.utf8
        )
        let playlist = try BambiCloudPlaylist.decode(from: data, expectedID: playlistID)

        var plan = BambiCloudPlaylistImporter().makePlan(
            for: playlist,
            availableAudioFiles: [owned]
        )
        let rowID = try #require(plan.rows.first?.id)

        plan.markPossibleDuplicate(existing: owned.id, forRow: rowID)
        #expect(plan.rows[0].status == .possibleDuplicate(existing: owned.id))

        plan.select(audioFileID: owned.id, forRow: rowID)
        #expect(plan.rows[0].selectedAudioFileID == owned.id)
        #expect(plan.downloadableRows.isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/BambiCloudPlaylistImportTests
```

Expected: build failure, `type 'Status' has no member 'possibleDuplicate'`.

- [ ] **Step 3a: Add the case**

In `Ilumionate/PlaylistImport/BambiCloudPlaylistImportPlan.swift`, change the `Status` declaration. The `String` raw type must go, because a raw-value enum cannot carry an associated value. This is safe: `Status.rawValue` has no readers in the app or the tests — the only uses are equality comparisons.

```swift
        /// Raw type deliberately absent: `.possibleDuplicate` carries the
        /// library file it may duplicate, and `rawValue` had no readers.
        enum Status: Equatable {
            case exact
            case probable
            case needsReview
            case missing
            case manual
            case downloaded
            /// Strong but circumstantial evidence the user already has this.
            case possibleDuplicate(existing: AudioFile.ID)
        }
```

Add the mutator after `markResolvedAsExisting(rowID:)`:

```swift
    /// Flags a row as probably already in the library, without acting on it.
    /// The user chooses between the existing file and a fresh download.
    mutating func markPossibleDuplicate(existing: AudioFile.ID, forRow rowID: Row.ID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].status = .possibleDuplicate(existing: existing)
    }
```

- [ ] **Step 3b: Check for likely duplicates before requesting**

In `Ilumionate/PlaylistImport/BambiCloudPlaylistImportViewModel.swift`, replace `requestDownload(of:)` (currently lines 100–115) with:

```swift
    /// Entry point for the per-track Download button.
    ///
    /// Three outcomes before a single byte is fetched: the library already has
    /// this (bind and stop), the library probably has this (ask), or the file
    /// is large enough to be worth confirming.
    func requestDownload(of row: BambiCloudPlaylistImportPlan.Row) async {
        guard !downloadingRowIDs.contains(row.id) else { return }

        downloadErrors[row.id] = nil

        let size = try? await downloader.expectedSize(of: row.track)
        let verdict = DuplicateAudioIndex(availableAudioFiles).verdict(
            for: DuplicateAudioCandidate(
                remoteSource: row.track.audioURL.map { url in
                    RemoteAudioSource(
                        service: RemoteAudioSource.bambiCloudService,
                        trackID: row.track.id.uuidString,
                        url: url
                    )
                },
                fileSize: size,
                duration: row.track.duration,
                title: row.track.name
            )
        )

        switch verdict {
        case .identical(let existingID):
            plan?.select(audioFileID: existingID, forRow: row.id)
            plan?.markResolvedAsExisting(rowID: row.id)
            return
        case .likely(let existingID, _):
            plan?.markPossibleDuplicate(existing: existingID, forRow: row.id)
            return
        case .distinct:
            break
        }

        if let size, size > PlaylistTrackDownloader.confirmationThresholdBytes {
            pendingDownload = PendingLargeDownload(
                scope: .row(id: row.id, name: row.track.name),
                byteCount: size
            )
            return
        }

        await downloadRow(row)
    }

    /// The user chose to fetch a fresh copy despite the likely match.
    func downloadAnyway(_ row: BambiCloudPlaylistImportPlan.Row) async {
        await downloadRow(row, allowingLargeFile: true)
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/BambiCloudPlaylistImportTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/PlaylistImport/BambiCloudPlaylistImportPlan.swift Ilumionate/PlaylistImport/BambiCloudPlaylistImportViewModel.swift IlumionateTests/BambiCloudPlaylistImportTests.swift
git commit -m "feat(dedupe): offer a likely duplicate instead of downloading it"
```

---

### Task 10: Show the possible duplicate in the row

**Files:**
- Modify: `Ilumionate/PlaylistImport/BambiCloudPlaylistMatchRow.swift`
- Modify: `Ilumionate/PlaylistImport/BambiCloudPlaylistReviewView.swift`

- [ ] **Step 1: Extend the row's presentation**

`BambiCloudPlaylistMatchRow` switches over `row.status` in three computed properties. Adding an associated-value case makes all three non-exhaustive, so the compiler will point at each.

In `Ilumionate/PlaylistImport/BambiCloudPlaylistMatchRow.swift`, add two stored properties after `onDownload`:

```swift
    /// The library file this row may duplicate, when there is one.
    let possibleDuplicate: AudioFile?
    let onUseExisting: () -> Void
    let onDownloadAnyway: () -> Void
```

Add the new cases to each switch:

```swift
    private var statusText: String {
        switch row.status {
        case .exact: "Exact match"
        case .probable: "Probable match"
        case .needsReview: "Choose between possible matches"
        case .missing: "Not matched"
        case .manual: "Selected manually"
        case .downloaded: "Downloaded from the publisher"
        case .possibleDuplicate: "You may already have this"
        }
    }

    private var statusIcon: String {
        switch row.status {
        case .exact: "checkmark.seal.fill"
        case .probable: "checkmark.circle.fill"
        case .needsReview: "questionmark.circle.fill"
        case .missing: "exclamationmark.circle.fill"
        case .manual: "hand.tap.fill"
        case .downloaded: "arrow.down.circle.fill"
        case .possibleDuplicate: "doc.on.doc.fill"
        }
    }

    private var statusColor: Color {
        switch row.status {
        case .exact, .manual, .downloaded: .green
        case .probable: .roseGold
        case .needsReview, .possibleDuplicate: .orange
        case .missing: .textLight
        }
    }
```

Add the choice UI. Insert immediately before the `if let downloadError` block in `body`:

```swift
            if case .possibleDuplicate = row.status, let possibleDuplicate {
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text("Already in your library as “\(possibleDuplicate.displayName)”")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textLight)

                    HStack(spacing: TranceSpacing.inner) {
                        Button("Use Existing", systemImage: "checkmark.circle", action: onUseExisting)
                            .buttonStyle(.borderedProminent)
                            .tint(.roseGold)

                        Button("Keep Both", systemImage: "arrow.down.circle", action: onDownloadAnyway)
                            .buttonStyle(.bordered)
                            .tint(.textLight)
                    }
                    .font(TranceTypography.body)
                    .frame(minHeight: 44)
                }
            }
```

Also stop the plain Download button appearing alongside the choice:

```swift
    private var canDownload: Bool {
        if case .possibleDuplicate = row.status { return false }
        return selectedAudioFile == nil && row.track.audioURL != nil
    }
```

- [ ] **Step 2: Pass the new arguments from the review view**

In `Ilumionate/PlaylistImport/BambiCloudPlaylistReviewView.swift`, find where `BambiCloudPlaylistMatchRow` is constructed and add the three arguments. The duplicate is looked up from the view model's snapshot:

```swift
                    possibleDuplicate: {
                        guard case .possibleDuplicate(let id) = row.status else { return nil }
                        return viewModel.availableAudioFiles.first { $0.id == id }
                    }(),
                    onUseExisting: {
                        guard case .possibleDuplicate(let id) = row.status else { return }
                        viewModel.select(audioFileID: id, forRow: row.id)
                    },
                    onDownloadAnyway: {
                        Task { await viewModel.downloadAnyway(row) }
                    }
```

If the surrounding code names the model something other than `viewModel`, match the existing name.

- [ ] **Step 3: Build both platforms**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: both succeed.

- [ ] **Step 4: Run the suite**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/PlaylistImport/BambiCloudPlaylistMatchRow.swift Ilumionate/PlaylistImport/BambiCloudPlaylistReviewView.swift
git commit -m "feat(dedupe): show Use Existing / Keep Both on a likely duplicate"
```

---

## Phase 5 — Cleanup for the existing library

### Task 11: `DuplicateAudioGroup` and the merge policy

**Files:**
- Create: `Ilumionate/LibraryDedupe/DuplicateAudioGroup.swift`
- Create: `IlumionateTests/DuplicateAudioMergeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/DuplicateAudioMergeTests.swift`:

```swift
//
//  DuplicateAudioMergeTests.swift
//  IlumionateTests
//
//  Merging must never lose the listener's history. A duplicate group commonly
//  holds one copy with the analysis and another with the play count, because
//  the second copy is what the playlist has been playing.
//

import Foundation
import Testing
@testable import Ilumionate

struct DuplicateAudioMergeTests {

    private func makeFile(
        filename: String,
        fingerprint: String? = "shared",
        createdDaysAgo: Int = 0
    ) -> AudioFile {
        AudioFile(
            filename: filename,
            duration: 600,
            fileSize: 5_000_000,
            createdDate: Date(timeIntervalSince1970: 1_000_000 - Double(createdDaysAgo) * 86_400),
            contentFingerprint: fingerprint
        )
    }

    @Test("Files sharing a fingerprint form one group")
    func groupsByFingerprint() {
        let a = makeFile(filename: "Track.mp3")
        let b = makeFile(filename: "Track (1).mp3")
        let unrelated = makeFile(filename: "Other.mp3", fingerprint: "different")

        let groups = DuplicateAudioGroup.groups(in: [a, b, unrelated])

        #expect(groups.count == 1)
        #expect(groups[0].redundant.count == 1)
        #expect(Set([groups[0].keeper.id] + groups[0].redundant.map(\.id)) == Set([a.id, b.id]))
    }

    @Test("A file with no fingerprint is never grouped")
    func ungroupedWithoutFingerprint() {
        let a = makeFile(filename: "Track.mp3", fingerprint: nil)
        let b = makeFile(filename: "Track (1).mp3", fingerprint: nil)

        #expect(DuplicateAudioGroup.groups(in: [a, b]).isEmpty)
    }

    @Test("The analyzed copy is kept")
    func keepsTheAnalyzedCopy() {
        var analyzed = makeFile(filename: "Track (1).mp3")
        analyzed.transcription = "seeded"
        analyzed.analysisResult = nil
        var plain = makeFile(filename: "Track.mp3", createdDaysAgo: 5)
        plain.transcription = nil

        let groups = DuplicateAudioGroup.groups(in: [plain, analyzed])

        #expect(groups[0].keeper.id == analyzed.id)
    }

    @Test("The keeper absorbs what the redundant copies hold")
    func mergeUnionsUserHistory() {
        var keeper = makeFile(filename: "Track.mp3")
        keeper.transcription = "seeded"
        keeper.playCount = 3
        keeper.lastPlayedDate = Date(timeIntervalSince1970: 100)
        keeper.isFavorite = false

        var other = makeFile(filename: "Track (1).mp3")
        other.playCount = 4
        other.lastPlayedDate = Date(timeIntervalSince1970: 900)
        other.isFavorite = true
        other.rating = 5
        other.tags = ["sleep"]
        other.userTitle = "Bedtime"
        other.sessionNotes = "Works well after midnight"

        let merged = DuplicateAudioGroup(keeper: keeper, redundant: [other]).merged()

        #expect(merged.id == keeper.id)
        #expect(merged.playCount == 7)
        #expect(merged.lastPlayedDate == Date(timeIntervalSince1970: 900))
        #expect(merged.isFavorite == true)
        #expect(merged.rating == 5)
        #expect(merged.tags == ["sleep"])
        #expect(merged.userTitle == "Bedtime")
        #expect(merged.sessionNotes == "Works well after midnight")
        // The keeper's own values are never overwritten.
        #expect(merged.transcription == "seeded")
    }

    @Test("Playlist items repoint to the keeper")
    func playlistItemsRepoint() {
        let keeper = makeFile(filename: "Track.mp3")
        let other = makeFile(filename: "Track (1).mp3")
        let group = DuplicateAudioGroup(keeper: keeper, redundant: [other])

        let items = [
            PlaylistItem(audioFileId: other.id, filename: "Track (1).mp3", duration: 600),
            PlaylistItem(audioFileId: keeper.id, filename: "Track.mp3", duration: 600)
        ]

        let rebound = PlaylistTrackBinding.rebinding(
            items,
            to: [keeper],
            remapping: DuplicateAudioGroup.remap(for: [group])
        )

        #expect(rebound.allSatisfy { $0.audioFileId == keeper.id })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/DuplicateAudioMergeTests
```

Expected: build failure, `cannot find 'DuplicateAudioGroup' in scope`.

- [ ] **Step 3a: Create the group**

Create `Ilumionate/LibraryDedupe/DuplicateAudioGroup.swift`:

```swift
//
//  DuplicateAudioGroup.swift
//  Ilumionate
//
//  Library entries holding the same audio, and the policy for collapsing them.
//
//  Grouping is fingerprint-only on purpose. The circumstantial signals the
//  index uses at import time are appropriate when a human is about to confirm
//  them; a bulk cleanup that merges on "same size and duration" would fold two
//  genuinely different recordings together and lose one of them.
//

import Foundation

nonisolated struct DuplicateAudioGroup: Identifiable, Sendable {
    let id: UUID
    /// The entry that survives, carrying the merged history.
    let keeper: AudioFile
    /// Entries whose files are removed once their history is folded in.
    let redundant: [AudioFile]

    init(id: UUID = UUID(), keeper: AudioFile, redundant: [AudioFile]) {
        self.id = id
        self.keeper = keeper
        self.redundant = redundant
    }

    /// Groups of two or more entries sharing a content fingerprint.
    static func groups(in files: [AudioFile]) -> [DuplicateAudioGroup] {
        let byFingerprint = Dictionary(grouping: files) { file in
            file.contentFingerprint?.lowercased()
        }

        return byFingerprint
            .compactMap { fingerprint, matches -> DuplicateAudioGroup? in
                // A file whose bytes could not be read has no identity to
                // group by, and must not be pooled with every other such file.
                guard fingerprint != nil, matches.count > 1 else { return nil }

                let ranked = matches.sorted(by: isRicher)
                guard let keeper = ranked.first else { return nil }
                return DuplicateAudioGroup(
                    keeper: keeper,
                    redundant: Array(ranked.dropFirst())
                )
            }
            .sorted { $0.keeper.displayName.localizedStandardCompare($1.keeper.displayName) == .orderedAscending }
    }

    /// Redundant identifier → keeper identifier, across every group.
    static func remap(for groups: [DuplicateAudioGroup]) -> [AudioFile.ID: AudioFile.ID] {
        groups.reduce(into: [:]) { remap, group in
            for file in group.redundant {
                remap[file.id] = group.keeper.id
            }
        }
    }

    /// The keeper with every redundant copy's history folded in.
    ///
    /// The keeper's own values always win — it was chosen for being the richest
    /// entry, and a merge must not downgrade it. Only fields it lacks are
    /// filled, except for the counters, which accumulate.
    func merged() -> AudioFile {
        var result = keeper

        for other in redundant {
            result.analysisResult = result.analysisResult ?? other.analysisResult
            result.transcription = result.transcription ?? other.transcription
            result.deadTimeProfile = result.deadTimeProfile ?? other.deadTimeProfile
            result.trackMetadata = result.trackMetadata ?? other.trackMetadata
            result.userTitle = result.userTitle ?? other.userTitle
            result.creator = result.creator ?? other.creator
            result.rating = result.rating ?? other.rating
            result.detailedRating = result.detailedRating ?? other.detailedRating
            result.tags = result.tags ?? other.tags
            result.sessionNotes = result.sessionNotes ?? other.sessionNotes
            result.remoteSource = result.remoteSource ?? other.remoteSource
            result.contentFingerprint = result.contentFingerprint ?? other.contentFingerprint

            result.playCount = (result.playCount ?? 0) + (other.playCount ?? 0)
            result.isFavorite = (result.isFavorite ?? false) || (other.isFavorite ?? false)
            if let otherPlayed = other.lastPlayedDate {
                result.lastPlayedDate = max(result.lastPlayedDate ?? otherPlayed, otherPlayed)
            }
        }

        return result
    }

    /// Analysis first, then a transcript, then listening history, then age.
    private static func isRicher(_ lhs: AudioFile, _ rhs: AudioFile) -> Bool {
        if lhs.isAnalyzed != rhs.isAnalyzed { return lhs.isAnalyzed }
        if lhs.hasTranscription != rhs.hasTranscription { return lhs.hasTranscription }
        if (lhs.playCount ?? 0) != (rhs.playCount ?? 0) {
            return (lhs.playCount ?? 0) > (rhs.playCount ?? 0)
        }
        return lhs.createdDate < rhs.createdDate
    }
}
```

- [ ] **Step 3b: Add the remap to `PlaylistTrackBinding`**

In `Ilumionate/PlaylistTrackBinding.swift`, replace `rebinding(_:to:)` with:

```swift
    /// Items re-pointed at the entries they resolve to, so a healed link is
    /// persisted the next time the playlist is saved.
    ///
    /// The item keeps its own `id`, filename and duration — only the library
    /// reference moves, so ordering, artwork and the timeline are untouched.
    ///
    /// - Parameter remapping: retired identifier → surviving identifier, as
    ///   produced by a duplicate merge. Applied before resolution, because the
    ///   retired entry is already gone from `audioFiles` and would otherwise
    ///   fall through to the filename heuristic.
    static func rebinding(
        _ items: [PlaylistItem],
        to audioFiles: [AudioFile],
        remapping: [UUID: UUID] = [:]
    ) -> [PlaylistItem] {
        items.map { item in
            let remapped = remapping[item.audioFileId] ?? item.audioFileId
            let probe = remapped == item.audioFileId
                ? item
                : PlaylistItem(
                    id: item.id,
                    audioFileId: remapped,
                    filename: item.filename,
                    duration: item.duration
                )

            guard let file = resolve(probe, in: audioFiles),
                  file.id != item.audioFileId else {
                return probe
            }
            return PlaylistItem(
                id: item.id,
                audioFileId: file.id,
                filename: item.filename,
                duration: item.duration
            )
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/DuplicateAudioMergeTests
```

Expected: PASS, 5 tests. Then run the existing binding tests:

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/PlaylistTrackBindingTests
```

Expected: PASS — the new parameter is defaulted.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/LibraryDedupe/DuplicateAudioGroup.swift Ilumionate/PlaylistTrackBinding.swift IlumionateTests/DuplicateAudioMergeTests.swift
git commit -m "feat(dedupe): group duplicates and merge their listening history

Grouping is fingerprint-only: a bulk merge on circumstantial evidence
would fold two different recordings together."
```

---

### Task 12: The cleanup view model

**Files:**
- Create: `Ilumionate/LibraryDedupe/DuplicateAudioReviewViewModel.swift`
- Create: `IlumionateTests/DuplicateAudioReviewViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/DuplicateAudioReviewViewModelTests.swift`:

```swift
//
//  DuplicateAudioReviewViewModelTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct DuplicateAudioReviewViewModelTests {

    private func makeFile(_ filename: String, fingerprint: String = "shared") -> AudioFile {
        AudioFile(
            filename: filename,
            duration: 600,
            fileSize: 5_000_000,
            contentFingerprint: fingerprint
        )
    }

    @Test("Only selected groups are merged")
    func mergesOnlySelectedGroups() {
        let a = makeFile("Track.mp3")
        let b = makeFile("Track (1).mp3")
        let c = makeFile("Other.mp3", fingerprint: "other")
        let d = makeFile("Other (1).mp3", fingerprint: "other")

        let model = DuplicateAudioReviewViewModel(audioFiles: [a, b, c, d])
        #expect(model.groups.count == 2)

        let firstGroupID = model.groups[0].id
        model.setSelected(false, groupID: model.groups[1].id)

        let result = model.resolution()

        #expect(result.merged.count == 1)
        #expect(result.removed.count == 1)
        #expect(model.groups[0].id == firstGroupID)
    }

    @Test("A merge removes the redundant rows and keeps the merged keeper")
    func resolutionReplacesTheLibrary() {
        var a = makeFile("Track.mp3")
        a.playCount = 2
        var b = makeFile("Track (1).mp3")
        b.playCount = 3

        let model = DuplicateAudioReviewViewModel(audioFiles: [a, b])
        let result = model.resolution()

        #expect(result.audioFiles.count == 1)
        #expect(result.audioFiles[0].playCount == 5)
        #expect(result.removed.count == 1)
    }

    @Test("Nothing selected means nothing changes")
    func nothingSelectedChangesNothing() {
        let a = makeFile("Track.mp3")
        let b = makeFile("Track (1).mp3")

        let model = DuplicateAudioReviewViewModel(audioFiles: [a, b])
        model.setSelected(false, groupID: model.groups[0].id)

        let result = model.resolution()

        #expect(result.audioFiles.count == 2)
        #expect(result.removed.isEmpty)
        #expect(result.merged.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/DuplicateAudioReviewViewModelTests
```

Expected: build failure, `cannot find 'DuplicateAudioReviewViewModel' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Ilumionate/LibraryDedupe/DuplicateAudioReviewViewModel.swift`:

```swift
//
//  DuplicateAudioReviewViewModel.swift
//  Ilumionate
//

import Foundation
import Observation

@MainActor
@Observable
final class DuplicateAudioReviewViewModel {

    /// The library as it would be after merging, and what has to leave disk.
    struct Resolution: Sendable {
        /// The whole library, with each merged group collapsed to its keeper.
        let audioFiles: [AudioFile]
        /// Keepers that changed, for logging and for the confirmation message.
        let merged: [AudioFile]
        /// Entries whose files must be staged for deletion.
        let removed: [AudioFile]
        /// Retired identifier → surviving identifier, for playlist rebinding.
        let remap: [AudioFile.ID: AudioFile.ID]
    }

    private(set) var groups: [DuplicateAudioGroup]
    private var deselected: Set<DuplicateAudioGroup.ID> = []

    private let audioFiles: [AudioFile]

    init(audioFiles: [AudioFile]) {
        self.audioFiles = audioFiles
        groups = DuplicateAudioGroup.groups(in: audioFiles)
    }

    var hasDuplicates: Bool { !groups.isEmpty }

    /// How many library rows would go away if the current selection is applied.
    var removableCount: Int {
        selectedGroups.reduce(0) { $0 + $1.redundant.count }
    }

    func isSelected(_ groupID: DuplicateAudioGroup.ID) -> Bool {
        !deselected.contains(groupID)
    }

    func setSelected(_ isSelected: Bool, groupID: DuplicateAudioGroup.ID) {
        if isSelected {
            deselected.remove(groupID)
        } else {
            deselected.insert(groupID)
        }
    }

    private var selectedGroups: [DuplicateAudioGroup] {
        groups.filter { isSelected($0.id) }
    }

    func resolution() -> Resolution {
        let selected = selectedGroups
        guard !selected.isEmpty else {
            return Resolution(audioFiles: audioFiles, merged: [], removed: [], remap: [:])
        }

        let mergedByKeeperID = Dictionary(
            uniqueKeysWithValues: selected.map { ($0.keeper.id, $0.merged()) }
        )
        let removedIDs = Set(selected.flatMap { $0.redundant.map(\.id) })

        let updated = audioFiles.compactMap { file -> AudioFile? in
            if removedIDs.contains(file.id) { return nil }
            return mergedByKeeperID[file.id] ?? file
        }

        return Resolution(
            audioFiles: updated,
            merged: Array(mergedByKeeperID.values),
            removed: selected.flatMap(\.redundant),
            remap: DuplicateAudioGroup.remap(for: selected)
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests/DuplicateAudioReviewViewModelTests
```

Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/LibraryDedupe/DuplicateAudioReviewViewModel.swift IlumionateTests/DuplicateAudioReviewViewModelTests.swift
git commit -m "feat(dedupe): add the cleanup review view model"
```

---

### Task 13: The cleanup screen and its Library entry point

**Files:**
- Create: `Ilumionate/LibraryDedupe/DuplicateAudioReviewView.swift`
- Modify: `Ilumionate/AudioLibraryView.swift`
- Modify: `Ilumionate/AudioLibraryView+Actions.swift`
- Modify: `Playlist.swift` (repo root — `PlaylistStore.rebindAll`)

- [ ] **Step 1: Create the screen**

Create `Ilumionate/LibraryDedupe/DuplicateAudioReviewView.swift`:

```swift
//
//  DuplicateAudioReviewView.swift
//  Ilumionate
//

import SwiftUI

struct DuplicateAudioReviewView: View {
    @State private var viewModel: DuplicateAudioReviewViewModel
    private let onMerge: (DuplicateAudioReviewViewModel.Resolution) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        audioFiles: [AudioFile],
        onMerge: @escaping (DuplicateAudioReviewViewModel.Resolution) -> Void
    ) {
        _viewModel = State(initialValue: DuplicateAudioReviewViewModel(audioFiles: audioFiles))
        self.onMerge = onMerge
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasDuplicates {
                    groupList
                } else {
                    ContentUnavailableView(
                        "No Duplicates",
                        systemImage: "checkmark.seal",
                        description: Text("Every file in your library holds different audio.")
                    )
                }
            }
            .navigationTitle("Duplicates")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .tint(.roseGold)
                }

                ToolbarItem(placement: .primaryAction) {
                    if viewModel.hasDuplicates {
                        Button("Merge \(viewModel.removableCount)") {
                            onMerge(viewModel.resolution())
                            dismiss()
                        }
                        .tint(.roseGold)
                        .disabled(viewModel.removableCount == 0)
                    }
                }
            }
        }
    }

    private var groupList: some View {
        List(viewModel.groups) { group in
            DuplicateAudioGroupRow(
                group: group,
                isSelected: viewModel.isSelected(group.id),
                onToggle: { viewModel.setSelected(!viewModel.isSelected(group.id), groupID: group.id) }
            )
        }
        .scrollIndicators(.hidden)
    }
}

/// One duplicate group: the copy that survives, and the copies that go.
private struct DuplicateAudioGroupRow: View {
    let group: DuplicateAudioGroup
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: TranceSpacing.list) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.roseGold : Color.textLight)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(group.keeper.displayName)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textPrimary)

                    Text(keptDescription)
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textLight)

                    ForEach(group.redundant) { file in
                        Text("Removes “\(file.displayName)”")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.keeper.displayName), removes \(group.redundant.count) copy or copies")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var keptDescription: String {
        group.keeper.isAnalyzed
            ? "Keeps the analyzed copy"
            : "Keeps the earliest copy"
    }
}
```

- [ ] **Step 2: Add the toolbar entry point**

In `Ilumionate/AudioLibraryView.swift`, add the presentation state alongside the other `@State` flags such as `showingAddSheet`:

```swift
    @State private var showingDuplicateReview = false
```

In the `ToolbarItem(placement: .primaryAction)` `HStack` (currently around line 212), add a button before the existing "Add" button:

```swift
                        if audioFiles.count > 1 {
                            Button("Find Duplicates", systemImage: "doc.on.doc") {
                                TranceHaptics.shared.light()
                                showingDuplicateReview = true
                            }
                            .labelStyle(.iconOnly)
                            .tint(.roseGold)
                        }
```

Attach the sheet next to the view's other `.sheet` modifiers:

```swift
            .sheet(isPresented: $showingDuplicateReview) {
                DuplicateAudioReviewView(audioFiles: audioFiles) { resolution in
                    Task { await mergeDuplicates(resolution) }
                }
            }
```

- [ ] **Step 3: Apply the merge**

In `Ilumionate/AudioLibraryView+Actions.swift`, add:

```swift
    /// Collapses each selected duplicate group to one entry.
    ///
    /// The redundant files must actually leave `Documents`. Dropping only the
    /// row would leave the file in place for `discoverUnregisteredDocumentFiles`
    /// to re-register under a fresh identifier on the next load, recreating the
    /// duplicate this just removed.
    ///
    /// Everything is staged as one batch so a single Undo reverses the whole
    /// merge — `PendingAudioDeletion` holds exactly one batch, and staging in a
    /// loop would commit each group before the next.
    func mergeDuplicates(_ resolution: DuplicateAudioReviewViewModel.Resolution) async {
        guard !resolution.removed.isEmpty else { return }

        let entries = resolution.removed.map { file in
            StagedAudioFile(
                file: file,
                originalURL: file.url,
                originalIndex: audioFiles.firstIndex { $0.id == file.id } ?? 0
            )
        }
        let staged = pendingDeletion.stage(entries)
        let stagedIDs = Set(staged.map(\.file.id))
        guard !stagedIDs.isEmpty else { return }

        // A file that would not move stays in the library, so its merged
        // history must stay with it rather than being folded into the keeper.
        let applicable = stagedIDs == Set(resolution.removed.map(\.id))
            ? resolution.audioFiles
            : resolution.audioFiles.filter { !stagedIDs.contains($0.id) }

        audioFiles = applicable.filter { !stagedIDs.contains($0.id) }
        await saveAudioFiles()

        PlaylistStore.rebindAll(to: audioFiles, remapping: resolution.remap)

        TranceHaptics.shared.medium()
        Log.audio.info("🧹 Merged \(resolution.merged.count) duplicate group(s), removed \(stagedIDs.count) file(s)")
    }
```

Add `rebindAll` to `PlaylistStore` in `Playlist.swift`, after `save(_:)` (currently line 200). `PlaylistStore` is a `struct` with static members and a static `cache`, so this is a static method — there is no `shared` instance:

```swift
    /// Repoints every stored playlist at surviving library entries.
    ///
    /// Called after a duplicate merge retires an `AudioFile.ID`. Writing through
    /// `save` rather than the defaults key keeps the in-memory cache correct —
    /// `LibraryView` reads that cache during its rebuild and would otherwise
    /// show the retired identifiers until the next launch.
    static func rebindAll(
        to audioFiles: [AudioFile],
        remapping: [UUID: UUID]
    ) {
        guard !remapping.isEmpty else { return }

        let rebound = load().map { playlist in
            var updated = playlist
            updated.items = PlaylistTrackBinding.rebinding(
                playlist.items,
                to: audioFiles,
                remapping: remapping
            )
            return updated
        }
        save(rebound)
    }
```

- [ ] **Step 4: Build and test both platforms**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' test -only-testing:IlumionateTests
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:IlumionateTests
```

Expected: all four succeed.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/LibraryDedupe/DuplicateAudioReviewView.swift Ilumionate/AudioLibraryView.swift Ilumionate/AudioLibraryView+Actions.swift Playlist.swift
git commit -m "feat(dedupe): add Find Duplicates to the audio library

Merges each selected group to one entry, folding in the listening
history, repointing playlists, and staging the redundant files as a
single batch so one Undo reverses the whole merge."
```

---

## Phase 6 — Verification

### Task 14: Manual verification on device

Automated tests cover the logic. These check the parts they cannot.

- [ ] **Step 1: Build and run on the iOS Simulator**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

- [ ] **Step 2: Confirm the repeat-playlist case**

1. Import a BambiCloud playlist and download two or three missing tracks.
2. Import a **different** playlist that shares at least one of those tracks.
3. Confirm the shared rows show "Exact match" immediately, with no Download button and no spinner.
4. Open Files and confirm `Documents` gained no `Name (1).mp3`.

- [ ] **Step 3: Confirm the likely-duplicate path**

1. Rename a library file to something the matcher cannot resolve.
2. Import a playlist containing that track.
3. Confirm the row reads "You may already have this" and offers Use Existing / Keep Both.
4. Confirm **Use Existing** binds without a download, and **Keep Both** downloads.

- [ ] **Step 4: Confirm cleanup**

1. Open Audio → Find Duplicates.
2. Confirm each group names the surviving copy and the copies it removes.
3. Merge, then confirm the Undo banner restores every removed file in one action.
4. Confirm a playlist that pointed at a removed copy still plays and still shows its analysis.

- [ ] **Step 5: Update `plan.md`**

Add the completed item to `plan.md` following the existing format, then:

```bash
git add plan.md
git commit -m "docs: mark duplicate detection complete in plan.md"
```

---

## Coverage against the spec

| Spec section | Task |
|---|---|
| Root cause 1 — fingerprint never read | 3, 5, 7 |
| Root cause 2 — helpers manufacture duplicates | 5, 7 |
| Root cause 3 — downloader sets no fingerprint | 4 |
| Root cause 4 — no provenance | 2, 4, 6 |
| Root cause 5 — numbered series collapse | 1, 8 |
| `RemoteAudioSource` | 2 |
| `AudioTitleNormalizer` | 1 |
| `DuplicateAudioDetector` (index, candidate, verdict) | 3 |
| Enforcement: BambiCloud download | 5, 6 |
| Enforcement: Files picker | 7 |
| Enforcement: URL download | 7 |
| `.possibleDuplicate` review row | 9, 10 |
| Matcher corrections | 8 |
| Cleanup: grouping and merge | 11 |
| Cleanup: playlist repointing | 11 |
| Cleanup: staged removal, single batch | 13 |
| Cleanup: Library toolbar entry | 13 |
| Testing table | 1, 3, 4, 5, 6, 7, 8, 9, 11, 12 |
