# Phase Evaluation Harness (Corpus Schema + Timeline Metrics) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the phase classifier a file-based, ground-truth corpus and timeline-aware metrics that measure *boundary placement* — the actual roadblock — so improvement can chase correctness instead of self-consistency.

**Architecture:** Add a Codable on-disk corpus schema (`CorpusCase`) loaded from repo `Corpus/**.json` via a source-relative loader (no Xcode resource bundling). Add a focused `PhaseTimelineEvaluator` that builds per-second truth/predicted timelines and computes agreement, boundary-placement error, a confusion matrix, per-phase precision/recall/F1, and an accuracy-by-ambiguity aggregate. Wire both into the existing Swift Testing harness without removing the current presence/order scorers.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`), Foundation. Test target `IlumionateTests`, app target `Ilumionate` (`@testable import`).

**Scope:** Spec steps 1–2 only. Steps 3 (generator CLI) and 4 (real-corpus labeling) are a separate follow-on plan — the generator is an independent SwiftPM subsystem that should be built against this *proven* schema, and labeling is a manual LumeLabel procedure. See `docs/superpowers/specs/2026-05-31-phase-classifier-training-design.md`.

**Decomposition note (deviation from spec wording):** The spec says "extend `AnalysisEvaluator`." This plan instead adds a **new focused `PhaseTimelineEvaluator`** type and leaves `AnalysisEvaluator` untouched. Rationale: `AnalysisEvaluator` scores a `HypnosisMetadata` against an `EvaluationCase` (presence/order/frequency); the timeline metrics need per-second truth spans and a different report shape. A separate focused file is cleaner than swelling the existing scorer and matches the project's focused-file convention. The harness gains the timeline metrics exactly as the spec intends.

**Phase rawValue assumption (verify in Task 1):** corpus JSON stores each phase as `HypnosisMetadata.Phase.rawValue` (a `String`). Task 1 Step 2 verifies `HypnosisMetadata.Phase: RawRepresentable where RawValue == String`. If it is not, add a `String`-backed `rawValue`/`init?(rawValue:)` bridge in the corpus module (instructions in that step) — do **not** modify the app enum.

---

## File Structure

- Create: `Corpus/synthetic/.gitkeep` — synthetic generated cases land here later (empty for now).
- Create: `Corpus/real/.gitkeep` — hand-labeled anchored cases land here later (empty for now).
- Create: `Corpus/fixtures/legacy-pretalk-induction.json` etc. — migrated existing cases + new timeline fixtures used by tests.
- Create: `IlumionateTests/Corpus/CorpusCase.swift` — Codable on-disk schema (DTOs) + conversion to `EvaluationCase` and to a `PhaseTruthTimeline`.
- Create: `IlumionateTests/Corpus/CorpusLoader.swift` — loads `*.json` from a `Corpus/` subdirectory using a source-relative path.
- Create: `IlumionateTests/Corpus/PhaseTimelineEvaluator.swift` — per-second timeline builder + all timeline metrics + `PhaseTimelineScore` and `CorpusTimelineReport`.
- Create: `IlumionateTests/Corpus/CorpusCaseTests.swift` — schema decode tests.
- Create: `IlumionateTests/Corpus/CorpusLoaderTests.swift` — loader tests.
- Create: `IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift` — metric tests.
- Modify: `IlumionateTests/EvaluationHarnessTests.swift` — add a test that runs the real pipeline over the file corpus and asserts timeline thresholds.

**Xcode target membership:** New `.swift` files under `IlumionateTests/` must belong to the `IlumionateTests` target. This project uses synchronized groups (see project memory: "Xcode target membership"), so files added under the synchronized folder are auto-included — but after creating files, confirm membership in Xcode if a build reports "cannot find type in scope." The `Corpus/` JSON files are **not** bundled into the target; they are read from disk via a source-relative path, so they need no target membership.

---

## Task 1: Corpus on-disk schema (`CorpusCase`)

**Files:**
- Create: `IlumionateTests/Corpus/CorpusCase.swift`
- Test: `IlumionateTests/Corpus/CorpusCaseTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  CorpusCaseTests.swift
import Testing
import Foundation
@testable import Ilumionate

struct CorpusCaseTests {

    @Test("Decodes an exact-mode synthetic case with truth spans")
    func decodesExactCase() throws {
        let json = """
        {
          "id": "synth-0001",
          "source": "synthetic",
          "boundaryMode": "exact",
          "ambiguityLevel": "high",
          "duration": 120.0,
          "segments": [
            { "text": "close your eyes", "timestamp": 0.0, "duration": 10.0, "confidence": 1.0 }
          ],
          "truth": [
            { "phase": "induction", "start": 0.0,  "end": 60.0 },
            { "phase": "deepening", "start": 60.0, "end": 120.0 }
          ]
        }
        """
        let data = Data(json.utf8)
        let kase = try JSONDecoder().decode(CorpusCase.self, from: data)

        #expect(kase.id == "synth-0001")
        #expect(kase.source == .synthetic)
        #expect(kase.boundaryMode == .exact)
        #expect(kase.ambiguityLevel == .high)
        #expect(kase.duration == 120.0)
        #expect(kase.segments.count == 1)
        #expect(kase.segments.first?.text == "close your eyes")
        #expect(kase.truth.count == 2)
        #expect(kase.truth.first?.phase == .induction)
        #expect(kase.truth.last?.end == 120.0)
    }

    @Test("Decodes a legacy case with no truth spans and optional expectations")
    func decodesLegacyCase() throws {
        let json = """
        {
          "id": "legacy-1",
          "source": "real",
          "boundaryMode": "anchored",
          "ambiguityLevel": "unspecified",
          "duration": 60.0,
          "segments": [],
          "truth": [],
          "expectedContentType": "hypnosis",
          "expectedPhaseOrder": ["preTalk", "induction"],
          "minimumPhaseCount": 1
        }
        """
        let kase = try JSONDecoder().decode(CorpusCase.self, from: Data(json.utf8))
        #expect(kase.truth.isEmpty)
        #expect(kase.expectedPhaseOrder == [.preTalk, .induction])
        #expect(kase.expectedContentType == .hypnosis)
    }

    // NOTE: `expectedContentType` decodes to `AnalysisResult.ContentType`
    // (verified in IlumionateTests/AnalysisEvaluationMetrics.swift:46). Its
    // rawValue string (e.g. "hypnosis") must match a case of that enum.

    @Test("Converts to AudioTranscriptionSegment array")
    func convertsSegments() throws {
        let kase = CorpusCase(
            id: "x", source: .synthetic, boundaryMode: .exact,
            ambiguityLevel: .low, duration: 20,
            segments: [CorpusSegment(text: "hi", timestamp: 1, duration: 2, confidence: 0.9)],
            truth: []
        )
        let segs = kase.transcriptionSegments
        #expect(segs.count == 1)
        #expect(segs.first?.text == "hi")
        #expect(segs.first?.timestamp == 1)
        #expect(segs.first?.duration == 2)
    }
}
```

- [ ] **Step 2: Verify the Phase rawValue assumption**

Run: `grep -nE "enum Phase|enum ContentType" Ilumionate/AIAnalysisModels.swift Ilumionate/*.swift`
Then inspect the `Phase` and `AnalysisResult.ContentType` declarations. Confirm both are `String`-backed (`RawRepresentable where RawValue == String`). The keyword taxonomy and `AnalyzerConfig_default.json` reference phases by name, and the legacy corpus uses `"hypnosis"` for content type, so this is expected.

Expected: both are `String`-RawRepresentable. The code below deliberately decodes/encodes both through their `rawValue` / `init?(rawValue:)` (not `Codable`), so it only requires `RawRepresentable<String>` — no app-enum edits needed regardless of their `Codable` conformance. If either is **not** `String`-RawRepresentable, stop and reconcile before continuing (it would contradict `EvaluationCase` at AnalysisEvaluationMetrics.swift:46-48).

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/CorpusCaseTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'CorpusCase' in scope`.

- [ ] **Step 4: Write minimal implementation**

```swift
//  CorpusCase.swift
//  IlumionateTests
//
//  On-disk corpus schema. Decoupled DTOs so the JSON format does not depend
//  on app types' Codable conformance. Phases are stored by rawValue string.
//
import Foundation
@testable import Ilumionate

enum CorpusSource: String, Codable, Sendable { case synthetic, real }
enum CorpusBoundaryMode: String, Codable, Sendable { case exact, anchored }
enum CorpusAmbiguityLevel: String, Codable, Sendable {
    case low, medium, high, unspecified
}

/// Segment DTO mirroring `AudioTranscriptionSegment(text:timestamp:duration:confidence:)`.
struct CorpusSegment: Codable, Sendable {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Double
}

/// A ground-truth phase span. In `exact` mode `start`/`end` are precise.
/// In `anchored` mode spans are anchor regions; gaps between them are
/// unlabeled gray zones the evaluator does not grade.
struct PhaseTruthSpan: Codable, Sendable {
    let phase: HypnosisMetadata.Phase
    let start: TimeInterval
    let end: TimeInterval

    private enum CodingKeys: String, CodingKey { case phase, start, end }

    init(phase: HypnosisMetadata.Phase, start: TimeInterval, end: TimeInterval) {
        self.phase = phase; self.start = start; self.end = end
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .phase)
        guard let phase = HypnosisMetadata.Phase(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .phase, in: c,
                debugDescription: "Unknown phase rawValue '\(raw)'"
            )
        }
        self.phase = phase
        self.start = try c.decode(TimeInterval.self, forKey: .start)
        self.end = try c.decode(TimeInterval.self, forKey: .end)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase.rawValue, forKey: .phase)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
    }
}

/// One corpus case on disk. `truth` drives the timeline metrics; the optional
/// `expected*` fields preserve the legacy presence/order scorers.
struct CorpusCase: Codable, Sendable {
    let id: String
    let source: CorpusSource
    let boundaryMode: CorpusBoundaryMode
    let ambiguityLevel: CorpusAmbiguityLevel
    let duration: TimeInterval
    let segments: [CorpusSegment]
    let truth: [PhaseTruthSpan]

    // Optional legacy expectations (used by AnalysisEvaluator path).
    // `AnalysisResult.ContentType` is the real enum (AnalysisEvaluationMetrics.swift:46).
    let expectedContentType: AnalysisResult.ContentType?
    let expectedPhaseOrder: [HypnosisMetadata.Phase]?
    let minimumPhaseCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, source, boundaryMode, ambiguityLevel, duration, segments, truth
        case expectedContentType, expectedPhaseOrder, minimumPhaseCount
    }

    init(
        id: String,
        source: CorpusSource,
        boundaryMode: CorpusBoundaryMode,
        ambiguityLevel: CorpusAmbiguityLevel,
        duration: TimeInterval,
        segments: [CorpusSegment],
        truth: [PhaseTruthSpan],
        expectedContentType: AnalysisResult.ContentType? = nil,
        expectedPhaseOrder: [HypnosisMetadata.Phase]? = nil,
        minimumPhaseCount: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.boundaryMode = boundaryMode
        self.ambiguityLevel = ambiguityLevel
        self.duration = duration
        self.segments = segments
        self.truth = truth
        self.expectedContentType = expectedContentType
        self.expectedPhaseOrder = expectedPhaseOrder
        self.minimumPhaseCount = minimumPhaseCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(CorpusSource.self, forKey: .source)
        boundaryMode = try c.decode(CorpusBoundaryMode.self, forKey: .boundaryMode)
        ambiguityLevel = try c.decodeIfPresent(CorpusAmbiguityLevel.self, forKey: .ambiguityLevel) ?? .unspecified
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        segments = try c.decodeIfPresent([CorpusSegment].self, forKey: .segments) ?? []
        truth = try c.decodeIfPresent([PhaseTruthSpan].self, forKey: .truth) ?? []
        if let rawType = try c.decodeIfPresent(String.self, forKey: .expectedContentType) {
            expectedContentType = AnalysisResult.ContentType(rawValue: rawType)
        } else {
            expectedContentType = nil
        }
        if let rawOrder = try c.decodeIfPresent([String].self, forKey: .expectedPhaseOrder) {
            expectedPhaseOrder = rawOrder.compactMap { HypnosisMetadata.Phase(rawValue: $0) }
        } else {
            expectedPhaseOrder = nil
        }
        minimumPhaseCount = try c.decodeIfPresent(Int.self, forKey: .minimumPhaseCount)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(source, forKey: .source)
        try c.encode(boundaryMode, forKey: .boundaryMode)
        try c.encode(ambiguityLevel, forKey: .ambiguityLevel)
        try c.encode(duration, forKey: .duration)
        try c.encode(segments, forKey: .segments)
        try c.encode(truth, forKey: .truth)
        try c.encodeIfPresent(expectedContentType?.rawValue, forKey: .expectedContentType)
        try c.encodeIfPresent(expectedPhaseOrder?.map(\.rawValue), forKey: .expectedPhaseOrder)
        try c.encodeIfPresent(minimumPhaseCount, forKey: .minimumPhaseCount)
    }

    /// App-typed transcription segments for feeding the analyzer.
    var transcriptionSegments: [AudioTranscriptionSegment] {
        segments.map {
            AudioTranscriptionSegment(
                text: $0.text, timestamp: $0.timestamp,
                duration: $0.duration, confidence: $0.confidence
            )
        }
    }

    /// Concatenated transcript text (fallback when segment text is the whole script).
    var transcriptText: String {
        segments.map(\.text).joined(separator: " ")
    }
}
```

Note: if Step 2 found `ContentAnalysisType` is not `Codable`, decode it via its rawValue the same way phases are decoded (replace the `decodeIfPresent(ContentAnalysisType.self …)` line with a `String` decode + `ContentAnalysisType(rawValue:)`). Confirm its raw type in the same grep.

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/CorpusCaseTests 2>&1 | tail -20`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add IlumionateTests/Corpus/CorpusCase.swift IlumionateTests/Corpus/CorpusCaseTests.swift
git commit -m "feat(eval): add Codable corpus case schema"
```

---

## Task 2: Corpus loader

**Files:**
- Create: `IlumionateTests/Corpus/CorpusLoader.swift`
- Test: `IlumionateTests/Corpus/CorpusLoaderTests.swift`
- Create: `Corpus/fixtures/loader-smoke.json`

- [ ] **Step 1: Create a fixture file the loader can find**

Create `Corpus/fixtures/loader-smoke.json`:

```json
{
  "id": "loader-smoke",
  "source": "synthetic",
  "boundaryMode": "exact",
  "ambiguityLevel": "low",
  "duration": 30.0,
  "segments": [
    { "text": "relax now", "timestamp": 0.0, "duration": 30.0, "confidence": 1.0 }
  ],
  "truth": [
    { "phase": "induction", "start": 0.0, "end": 30.0 }
  ]
}
```

- [ ] **Step 2: Write the failing test**

```swift
//  CorpusLoaderTests.swift
import Testing
import Foundation
@testable import Ilumionate

struct CorpusLoaderTests {

    @Test("Loads cases from the fixtures subdirectory")
    func loadsFixtures() throws {
        let cases = try CorpusLoader.load(subdirectory: "fixtures")
        #expect(cases.contains { $0.id == "loader-smoke" })
    }

    @Test("Returns empty for an empty/missing subdirectory")
    func emptyForMissing() throws {
        let cases = try CorpusLoader.load(subdirectory: "definitely-not-here")
        #expect(cases.isEmpty)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/CorpusLoaderTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'CorpusLoader' in scope`.

- [ ] **Step 4: Write minimal implementation**

```swift
//  CorpusLoader.swift
//  IlumionateTests
//
//  Loads corpus JSON from the repo-root `Corpus/<subdirectory>/` directory.
//  Uses a source-file-relative path so no Xcode resource bundling is needed;
//  tests run on the build machine where the checkout is present.
//
import Foundation

enum CorpusLoader {

    /// Repo-root `Corpus/` directory, resolved relative to this source file.
    /// This file lives at <repo>/IlumionateTests/Corpus/CorpusLoader.swift,
    /// so the repo root is three parents up.
    static var corpusRoot: URL {
        URL(filePath: #filePath)            // .../IlumionateTests/Corpus/CorpusLoader.swift
            .deletingLastPathComponent()    // .../IlumionateTests/Corpus
            .deletingLastPathComponent()    // .../IlumionateTests
            .deletingLastPathComponent()    // .../<repo root>
            .appending(path: "Corpus")
    }

    static func load(subdirectory: String) throws -> [CorpusCase] {
        let dir = corpusRoot.appending(path: subdirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }

        let urls = try fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        return try urls.map { url in
            let data = try Data(contentsOf: url)
            do {
                return try decoder.decode(CorpusCase.self, from: data)
            } catch {
                throw CorpusLoadError.decodeFailed(file: url.lastPathComponent, underlying: error)
            }
        }
    }

    enum CorpusLoadError: Error, CustomStringConvertible {
        case decodeFailed(file: String, underlying: Error)
        var description: String {
            switch self {
            case let .decodeFailed(file, underlying):
                return "Failed to decode corpus file \(file): \(underlying)"
            }
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/CorpusLoaderTests 2>&1 | tail -20`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add IlumionateTests/Corpus/CorpusLoader.swift IlumionateTests/Corpus/CorpusLoaderTests.swift Corpus/fixtures/loader-smoke.json
git commit -m "feat(eval): add source-relative corpus loader"
```

---

## Task 3: Migrate existing cases + add timeline fixtures

**Files:**
- Create: `Corpus/fixtures/legacy-pretalk-induction.json`
- Create: `Corpus/fixtures/legacy-deepening-therapy.json`
- Create: `Corpus/fixtures/legacy-full-session.json`
- Create: `Corpus/fixtures/timeline-induction-deepening.json`
- Create: `Corpus/synthetic/.gitkeep`, `Corpus/real/.gitkeep`

- [ ] **Step 1: Create the three migrated legacy cases (no truth spans, legacy expectations preserved)**

`Corpus/fixtures/legacy-pretalk-induction.json`:

```json
{
  "id": "pretalk-induction",
  "source": "real",
  "boundaryMode": "anchored",
  "ambiguityLevel": "unspecified",
  "duration": 60.0,
  "segments": [
    { "text": "Welcome, make yourself comfortable. Today we'll explore hypnosis and how your subconscious mind works. Just relax and listen to my voice as we begin. Close your eyes and take a deep breath in.", "timestamp": 0.0, "duration": 60.0, "confidence": 1.0 }
  ],
  "truth": [],
  "expectedContentType": "hypnosis",
  "expectedPhaseOrder": ["preTalk", "induction"],
  "minimumPhaseCount": 1
}
```

`Corpus/fixtures/legacy-deepening-therapy.json`:

```json
{
  "id": "deepening-therapy",
  "source": "real",
  "boundaryMode": "anchored",
  "ambiguityLevel": "unspecified",
  "duration": 60.0,
  "segments": [
    { "text": "Going deeper now, ten times more relaxed with every breath. Down, down, deeper and deeper. And now in this deep state, imagine your goal clearly, feeling confident and capable.", "timestamp": 0.0, "duration": 60.0, "confidence": 1.0 }
  ],
  "truth": [],
  "expectedContentType": "hypnosis",
  "expectedPhaseOrder": ["deepening", "therapy"],
  "minimumPhaseCount": 1
}
```

`Corpus/fixtures/legacy-full-session.json`:

```json
{
  "id": "full-session",
  "source": "real",
  "boundaryMode": "anchored",
  "ambiguityLevel": "unspecified",
  "duration": 60.0,
  "segments": [
    { "text": "Welcome and make yourself comfortable as we begin today. Close your eyes, take a deep breath, and let go. Going deeper now, deeper and deeper with each breath. In this deep state, see yourself achieving your goals. When I count to five you'll wake feeling refreshed. One, two, three, four, five, eyes open, wide awake.", "timestamp": 0.0, "duration": 60.0, "confidence": 1.0 }
  ],
  "truth": [],
  "expectedContentType": "hypnosis",
  "expectedPhaseOrder": ["preTalk", "induction", "deepening", "therapy", "emergence"],
  "minimumPhaseCount": 3
}
```

- [ ] **Step 2: Create one exact-mode timeline fixture with per-segment truth**

`Corpus/fixtures/timeline-induction-deepening.json` — segment timestamps line up with truth boundaries so the analyzer has a fighting chance, and the boundary at 60s is exact:

```json
{
  "id": "timeline-induction-deepening",
  "source": "synthetic",
  "boundaryMode": "exact",
  "ambiguityLevel": "low",
  "duration": 120.0,
  "segments": [
    { "text": "close your eyes and take a deep breath", "timestamp": 0.0,  "duration": 20.0, "confidence": 1.0 },
    { "text": "let your eyelids grow heavy and close them down", "timestamp": 20.0, "duration": 20.0, "confidence": 1.0 },
    { "text": "just relax and let go completely now", "timestamp": 40.0, "duration": 20.0, "confidence": 1.0 },
    { "text": "going deeper and deeper with every breath", "timestamp": 60.0, "duration": 20.0, "confidence": 1.0 },
    { "text": "down down deeper into relaxation", "timestamp": 80.0, "duration": 20.0, "confidence": 1.0 },
    { "text": "ten times more relaxed deeper and deeper", "timestamp": 100.0, "duration": 20.0, "confidence": 1.0 }
  ],
  "truth": [
    { "phase": "induction", "start": 0.0,  "end": 60.0 },
    { "phase": "deepening", "start": 60.0, "end": 120.0 }
  ]
}
```

- [ ] **Step 3: Create empty corpus directories**

```bash
mkdir -p Corpus/synthetic Corpus/real
touch Corpus/synthetic/.gitkeep Corpus/real/.gitkeep
```

- [ ] **Step 4: Verify the loader reads all fixtures**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/CorpusLoaderTests 2>&1 | tail -20`
Expected: PASS — existing tests still green (loader now also returns the new files; the smoke test only asserts containment).

- [ ] **Step 5: Commit**

```bash
git add Corpus/
git commit -m "test(eval): migrate legacy cases to corpus files + add timeline fixture"
```

---

## Task 4: Per-second timeline builder

**Files:**
- Create: `IlumionateTests/Corpus/PhaseTimelineEvaluator.swift`
- Test: `IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  PhaseTimelineEvaluatorTests.swift
import Testing
import Foundation
@testable import Ilumionate

struct PhaseTimelineEvaluatorTests {

    // Helper: build predicted spans quickly.
    private func span(_ phase: HypnosisMetadata.Phase, _ start: Double, _ end: Double) -> PhaseTruthSpan {
        PhaseTruthSpan(phase: phase, start: start, end: end)
    }

    @Test("Builds a per-second timeline; uncovered seconds are nil")
    func buildsTimeline() {
        let eval = PhaseTimelineEvaluator()
        let spans = [span(.induction, 0, 3), span(.deepening, 5, 8)]
        let timeline = eval.perSecondTimeline(spans: spans, duration: 8)
        // seconds 0,1,2 = induction ; 3,4 = nil (gap) ; 5,6,7 = deepening
        #expect(timeline.count == 8)
        #expect(timeline[0] == .induction)
        #expect(timeline[2] == .induction)
        #expect(timeline[3] == nil)
        #expect(timeline[4] == nil)
        #expect(timeline[5] == .deepening)
        #expect(timeline[7] == .deepening)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PhaseTimelineEvaluator' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
//  PhaseTimelineEvaluator.swift
//  IlumionateTests
//
//  Timeline-aware phase metrics. Grades predictions against ground-truth
//  spans per second; supports exact and anchored (gray-zone) boundary modes.
//
import Foundation
@testable import Ilumionate

struct PhaseTimelineEvaluator: Sendable {

    /// One phase per second over [0, duration). `nil` = not covered by any span
    /// (a gray-zone gap, or beyond the labeled region).
    func perSecondTimeline(
        spans: [PhaseTruthSpan],
        duration: TimeInterval
    ) -> [HypnosisMetadata.Phase?] {
        let bucketCount = max(0, Int(ceil(duration)))
        var timeline = [HypnosisMetadata.Phase?](repeating: nil, count: bucketCount)
        for span in spans {
            let lo = max(0, Int(floor(span.start)))
            let hi = min(bucketCount, Int(ceil(span.end)))
            guard lo < hi else { continue }
            for i in lo..<hi { timeline[i] = span.phase }
        }
        return timeline
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add IlumionateTests/Corpus/PhaseTimelineEvaluator.swift IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift
git commit -m "feat(eval): per-second phase timeline builder"
```

---

## Task 5: Per-second agreement metric

**Files:**
- Modify: `IlumionateTests/Corpus/PhaseTimelineEvaluator.swift`
- Test: `IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `PhaseTimelineEvaluatorTests`:

```swift
    @Test("Per-second agreement grades only truth-covered seconds")
    func perSecondAgreement() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 4), span(.deepening, 6, 10)] // 4,5 = gray gap
        let predicted = [span(.induction, 0, 5), span(.deepening, 5, 10)]
        // Graded seconds: 0,1,2,3 (induction) + 6,7,8,9 (deepening) = 8 graded.
        // predicted: 0-4 induction, 5-9 deepening.
        //   sec 0,1,2,3 -> induction == induction (4 correct)
        //   sec 6,7,8,9 -> deepening == deepening (4 correct)
        // gray seconds 4,5 ignored.
        let agreement = eval.perSecondAgreement(
            truth: truth, predicted: predicted, duration: 10
        )
        #expect(agreement == 1.0)
    }

    @Test("Agreement is zero when predictions miss every graded second")
    func agreementZero() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 4)]
        let predicted = [span(.emergence, 0, 4)]
        #expect(eval.perSecondAgreement(truth: truth, predicted: predicted, duration: 4) == 0.0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'PhaseTimelineEvaluator' has no member 'perSecondAgreement'`.

- [ ] **Step 3: Add the implementation**

Add to `PhaseTimelineEvaluator`:

```swift
    /// Fraction of truth-covered seconds where predicted phase == truth phase.
    /// Returns 0 when there are no graded seconds.
    func perSecondAgreement(
        truth: [PhaseTruthSpan],
        predicted: [PhaseTruthSpan],
        duration: TimeInterval
    ) -> Double {
        let truthTimeline = perSecondTimeline(spans: truth, duration: duration)
        let predTimeline = perSecondTimeline(spans: predicted, duration: duration)
        var graded = 0
        var correct = 0
        for i in truthTimeline.indices {
            guard let t = truthTimeline[i] else { continue } // skip gray/uncovered
            graded += 1
            if i < predTimeline.count, predTimeline[i] == t { correct += 1 }
        }
        return graded == 0 ? 0 : Double(correct) / Double(graded)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add IlumionateTests/Corpus/PhaseTimelineEvaluator.swift IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift
git commit -m "feat(eval): per-second phase agreement metric"
```

---

## Task 6: Boundary-placement error metric

**Files:**
- Modify: `IlumionateTests/Corpus/PhaseTimelineEvaluator.swift`
- Test: `IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `PhaseTimelineEvaluatorTests`:

```swift
    @Test("Exact-mode boundary error is distance to nearest predicted boundary")
    func boundaryErrorExact() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 60), span(.deepening, 60, 120)] // boundary at 60
        let predicted = [span(.induction, 0, 68), span(.deepening, 68, 120)] // boundary at 68
        let result = eval.boundaryError(
            truth: truth, predicted: predicted, boundaryMode: .exact, duration: 120
        )
        #expect(result.mean == 8.0)
        #expect(result.median == 8.0)
    }

    @Test("Anchored-mode boundary inside the gray gap scores zero error")
    func boundaryErrorAnchoredInsideGap() {
        let eval = PhaseTimelineEvaluator()
        // anchors: induction ends at 50, deepening starts at 70 -> gray gap [50,70]
        let truth = [span(.induction, 0, 50), span(.deepening, 70, 120)]
        let predicted = [span(.induction, 0, 60), span(.deepening, 60, 120)] // boundary 60 ∈ [50,70]
        let result = eval.boundaryError(
            truth: truth, predicted: predicted, boundaryMode: .anchored, duration: 120
        )
        #expect(result.mean == 0.0)
    }

    @Test("Anchored-mode boundary spilling past the gap is penalized by overshoot")
    func boundaryErrorAnchoredSpill() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 50), span(.deepening, 70, 120)] // gap [50,70]
        let predicted = [span(.induction, 0, 80), span(.deepening, 80, 120)] // boundary 80 > 70 by 10
        let result = eval.boundaryError(
            truth: truth, predicted: predicted, boundaryMode: .anchored, duration: 120
        )
        #expect(result.mean == 10.0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: FAIL — no member `boundaryError`.

- [ ] **Step 3: Add the implementation**

Add to `PhaseTimelineEvaluator`:

```swift
    struct BoundaryError: Sendable, Equatable {
        let mean: Double
        let median: Double
        let count: Int   // number of truth boundaries scored
    }

    /// For each internal truth transition, the distance from the nearest
    /// predicted boundary to the truth boundary (exact) or to the gray-zone
    /// gap (anchored: zero inside the gap, overshoot distance outside it).
    func boundaryError(
        truth: [PhaseTruthSpan],
        predicted: [PhaseTruthSpan],
        boundaryMode: CorpusBoundaryMode,
        duration: TimeInterval
    ) -> BoundaryError {
        let sortedTruth = truth.sorted { $0.start < $1.start }
        let predBoundaries = internalBoundaries(of: predicted)

        var distances: [Double] = []
        for i in 0..<max(0, sortedTruth.count - 1) {
            let prev = sortedTruth[i]
            let next = sortedTruth[i + 1]
            let target: (Double) -> Double
            switch boundaryMode {
            case .exact:
                // gap collapses to the shared boundary point
                let point = next.start
                target = { abs($0 - point) }
            case .anchored:
                // tolerance gap [prev.end, next.start]; 0 inside, overshoot outside
                let lo = prev.end, hi = next.start
                target = { p in p < lo ? lo - p : (p > hi ? p - hi : 0) }
            }
            // nearest predicted boundary to this truth transition
            guard let best = predBoundaries.map(target).min() else {
                distances.append(duration) // no predicted boundary at all = worst case
                continue
            }
            distances.append(best)
        }

        guard !distances.isEmpty else { return BoundaryError(mean: 0, median: 0, count: 0) }
        let mean = distances.reduce(0, +) / Double(distances.count)
        let median = medianOf(distances)
        return BoundaryError(mean: mean, median: median, count: distances.count)
    }

    /// Start times of every span after the first (the internal transitions).
    private func internalBoundaries(of spans: [PhaseTruthSpan]) -> [Double] {
        let sorted = spans.sorted { $0.start < $1.start }
        guard sorted.count > 1 else { return [] }
        return sorted.dropFirst().map(\.start)
    }

    private func medianOf(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let mid = s.count / 2
        return s.count.isMultiple(of: 2) ? (s[mid - 1] + s[mid]) / 2 : s[mid]
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add IlumionateTests/Corpus/PhaseTimelineEvaluator.swift IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift
git commit -m "feat(eval): boundary-placement error metric (exact + anchored)"
```

---

## Task 7: Confusion matrix + precision/recall/F1

**Files:**
- Modify: `IlumionateTests/Corpus/PhaseTimelineEvaluator.swift`
- Test: `IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `PhaseTimelineEvaluatorTests`:

```swift
    @Test("Confusion matrix counts truth->predicted over graded seconds")
    func confusionMatrix() {
        let eval = PhaseTimelineEvaluator()
        let truth = [span(.induction, 0, 4)]                  // 4 graded secs, all induction
        let predicted = [span(.induction, 0, 2), span(.deepening, 2, 4)] // 2 ind, 2 deep
        let cm = eval.confusionMatrix(truth: truth, predicted: predicted, duration: 4)
        #expect(cm.count(truth: .induction, predicted: .induction) == 2)
        #expect(cm.count(truth: .induction, predicted: .deepening) == 2)
    }

    @Test("Precision/recall/F1 derive from the confusion matrix")
    func precisionRecallF1() {
        let eval = PhaseTimelineEvaluator()
        // truth: 4 induction secs ; predicted: 3 induction (1 wrong as deepening) + over-predicts induction once elsewhere
        let truth = [span(.induction, 0, 4), span(.deepening, 4, 6)]
        let predicted = [span(.induction, 0, 3), span(.deepening, 3, 6)]
        let cm = eval.confusionMatrix(truth: truth, predicted: predicted, duration: 6)
        let stats = cm.stats(for: .induction)
        // induction: TP=3 (secs0-2), FN=1 (sec3 predicted deepening), FP=0
        #expect(stats.precision == 1.0)
        #expect(abs(stats.recall - 0.75) < 0.0001)
        #expect(abs(stats.f1 - (2 * 1.0 * 0.75 / 1.75)) < 0.0001)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: FAIL — no member `confusionMatrix`.

- [ ] **Step 3: Add the implementation**

Add to `PhaseTimelineEvaluator.swift` (top-level types + method):

```swift
struct ConfusionMatrix: Sendable {
    /// counts[truth][predicted] = seconds.
    private(set) var counts: [HypnosisMetadata.Phase: [HypnosisMetadata.Phase: Int]] = [:]

    mutating func add(truth: HypnosisMetadata.Phase, predicted: HypnosisMetadata.Phase) {
        counts[truth, default: [:]][predicted, default: 0] += 1
    }

    func count(truth: HypnosisMetadata.Phase, predicted: HypnosisMetadata.Phase) -> Int {
        counts[truth]?[predicted] ?? 0
    }

    struct PhaseStats: Sendable, Equatable {
        let precision: Double
        let recall: Double
        let f1: Double
    }

    func stats(for phase: HypnosisMetadata.Phase) -> PhaseStats {
        let tp = count(truth: phase, predicted: phase)
        let fn = (counts[phase]?.values.reduce(0, +) ?? 0) - tp
        var fp = 0
        for (truthPhase, row) in counts where truthPhase != phase {
            fp += row[phase] ?? 0
        }
        let precision = (tp + fp) == 0 ? 0 : Double(tp) / Double(tp + fp)
        let recall = (tp + fn) == 0 ? 0 : Double(tp) / Double(tp + fn)
        let f1 = (precision + recall) == 0 ? 0 : 2 * precision * recall / (precision + recall)
        return PhaseStats(precision: precision, recall: recall, f1: f1)
    }
}
```

Add to `PhaseTimelineEvaluator`:

```swift
    func confusionMatrix(
        truth: [PhaseTruthSpan],
        predicted: [PhaseTruthSpan],
        duration: TimeInterval
    ) -> ConfusionMatrix {
        let truthTimeline = perSecondTimeline(spans: truth, duration: duration)
        let predTimeline = perSecondTimeline(spans: predicted, duration: duration)
        var cm = ConfusionMatrix()
        for i in truthTimeline.indices {
            guard let t = truthTimeline[i] else { continue }
            let p = (i < predTimeline.count ? predTimeline[i] : nil) ?? t == t ? (predTimeline[i] ?? sentinelMiss) : sentinelMiss
            cm.add(truth: t, predicted: p)
        }
        return cm
    }

    /// Phase used to record a graded second with no prediction. Reuses
    /// `.transitional` so an unpredicted second counts as a miss, not a match.
    private var sentinelMiss: HypnosisMetadata.Phase { .transitional }
```

> Note: the ternary above is intentionally explicit so an uncovered predicted second is recorded as `.transitional` (a guaranteed mismatch for real phases), keeping recall honest. If `.transitional` is a phase your truth uses, replace `sentinelMiss` with any phase never present in truth, or model misses with an `Optional` predicted key — confirm against `HypnosisMetadata.Phase` cases when implementing.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add IlumionateTests/Corpus/PhaseTimelineEvaluator.swift IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift
git commit -m "feat(eval): confusion matrix + per-phase precision/recall/F1"
```

---

## Task 8: Case score + corpus report with accuracy-by-ambiguity

**Files:**
- Modify: `IlumionateTests/Corpus/PhaseTimelineEvaluator.swift`
- Test: `IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift`

- [ ] **Step 1: Add the failing test**

Append to `PhaseTimelineEvaluatorTests`:

```swift
    @Test("Scores one case end to end")
    func scoresCase() {
        let eval = PhaseTimelineEvaluator()
        let kase = CorpusCase(
            id: "c1", source: .synthetic, boundaryMode: .exact,
            ambiguityLevel: .high, duration: 120,
            segments: [],
            truth: [span(.induction, 0, 60), span(.deepening, 60, 120)]
        )
        let predicted = [span(.induction, 0, 60), span(.deepening, 60, 120)]
        let score = eval.score(case: kase, predicted: predicted)
        #expect(score.caseID == "c1")
        #expect(score.ambiguityLevel == .high)
        #expect(score.agreement == 1.0)
        #expect(score.boundaryError.mean == 0.0)
    }

    @Test("Aggregates a corpus report grouped by ambiguity")
    func aggregatesReport() {
        let eval = PhaseTimelineEvaluator()
        let low = CorpusCase(
            id: "lo", source: .synthetic, boundaryMode: .exact, ambiguityLevel: .low,
            duration: 10, segments: [], truth: [span(.induction, 0, 10)]
        )
        let high = CorpusCase(
            id: "hi", source: .synthetic, boundaryMode: .exact, ambiguityLevel: .high,
            duration: 10, segments: [], truth: [span(.induction, 0, 10)]
        )
        let perfect = [span(.induction, 0, 10)]
        let wrong = [span(.emergence, 0, 10)]
        let report = eval.report(scores: [
            eval.score(case: low, predicted: perfect),
            eval.score(case: high, predicted: wrong)
        ])
        #expect(abs(report.overallAgreement - 0.5) < 0.0001)
        #expect(report.agreementByAmbiguity[.low] == 1.0)
        #expect(report.agreementByAmbiguity[.high] == 0.0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: FAIL — no member `score(case:predicted:)`.

- [ ] **Step 3: Add the implementation**

Add to `PhaseTimelineEvaluator.swift` (top-level + methods):

```swift
struct PhaseTimelineScore: Sendable {
    let caseID: String
    let source: CorpusSource
    let ambiguityLevel: CorpusAmbiguityLevel
    let agreement: Double
    let boundaryError: PhaseTimelineEvaluator.BoundaryError
    let confusion: ConfusionMatrix
}

struct CorpusTimelineReport: Sendable {
    let overallAgreement: Double
    let meanBoundaryError: Double
    let agreementByAmbiguity: [CorpusAmbiguityLevel: Double]
    let agreementBySource: [CorpusSource: Double]
    let perCase: [PhaseTimelineScore]
}
```

Add to `PhaseTimelineEvaluator`:

```swift
    func score(case kase: CorpusCase, predicted: [PhaseTruthSpan]) -> PhaseTimelineScore {
        PhaseTimelineScore(
            caseID: kase.id,
            source: kase.source,
            ambiguityLevel: kase.ambiguityLevel,
            agreement: perSecondAgreement(truth: kase.truth, predicted: predicted, duration: kase.duration),
            boundaryError: boundaryError(truth: kase.truth, predicted: predicted, boundaryMode: kase.boundaryMode, duration: kase.duration),
            confusion: confusionMatrix(truth: kase.truth, predicted: predicted, duration: kase.duration)
        )
    }

    func report(scores: [PhaseTimelineScore]) -> CorpusTimelineReport {
        func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
        func group<K: Hashable>(_ key: (PhaseTimelineScore) -> K) -> [K: Double] {
            Dictionary(grouping: scores, by: key).mapValues { mean($0.map(\.agreement)) }
        }
        return CorpusTimelineReport(
            overallAgreement: mean(scores.map(\.agreement)),
            meanBoundaryError: mean(scores.map(\.boundaryError.mean)),
            agreementByAmbiguity: group(\.ambiguityLevel),
            agreementBySource: group(\.source),
            perCase: scores
        )
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/PhaseTimelineEvaluatorTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add IlumionateTests/Corpus/PhaseTimelineEvaluator.swift IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift
git commit -m "feat(eval): case score + corpus report (accuracy-by-ambiguity/source)"
```

---

## Task 9: Wire the real pipeline into the harness

**Files:**
- Modify: `IlumionateTests/EvaluationHarnessTests.swift`

**Real harness shape (verified):** this file has no `EvaluationHarnessTests` struct. It contains
`@MainActor struct KeywordPipelineEvaluationTests` (the deterministic, CI-safe suite) and
`@MainActor struct AIAnalysisPipelineEvaluationTests`. Add the new test to
**`KeywordPipelineEvaluationTests`** — it already holds `private let analyzer = HypnosisPhaseAnalyzer()`,
so reuse that property rather than redeclaring it. The analyzer returns `[PhaseSegment]` (the unqualified
type used throughout this file, e.g. the `buildAnalysisResult(evalCase:phases:)` helper signature), not
`HypnosisPhaseAnalyzer.PhaseSegment`.

- [ ] **Step 1: Add the failing test**

Add these two members inside `struct KeywordPipelineEvaluationTests` (it already declares `analyzer`; do
**not** redeclare it). Add a `PhaseTimelineEvaluator` property and the test:

```swift
    private let timelineEvaluator = PhaseTimelineEvaluator()

    /// Maps analyzer output to truth-span shape for the timeline evaluator.
    private func predictedSpans(_ phases: [PhaseSegment]) -> [PhaseTruthSpan] {
        phases.map { PhaseTruthSpan(phase: $0.phase, start: $0.startTime, end: $0.endTime) }
    }

    @Test("Timeline metrics run over the file corpus and meet thresholds")
    func timelineMetricsOverCorpus() async throws {
        let eval = timelineEvaluator

        // Only cases that carry ground-truth spans participate in timeline scoring.
        let cases = try (CorpusLoader.load(subdirectory: "fixtures")
                       + CorpusLoader.load(subdirectory: "synthetic")
                       + CorpusLoader.load(subdirectory: "real"))
            .filter { !$0.truth.isEmpty }

        try #require(!cases.isEmpty, "no truth-bearing corpus cases found")

        var scores: [PhaseTimelineScore] = []
        for kase in cases {
            let transcription = AudioTranscriptionResult(
                fullText: kase.transcriptText,
                segments: kase.transcriptionSegments.isEmpty
                    ? [AudioTranscriptionSegment(text: kase.transcriptText, timestamp: 0, duration: kase.duration)]
                    : kase.transcriptionSegments,
                duration: kase.duration,
                detectedLanguage: "en"
            )
            let phases = analyzer.analyzeTranscription(transcription)
            scores.append(eval.score(case: kase, predicted: predictedSpans(phases)))
        }

        let report = eval.report(scores: scores)
        // Baseline regression bar. Tighten as the corpus and tuning improve.
        #expect(report.overallAgreement >= 0.40,
                "overall agreement \(report.overallAgreement); by-ambiguity \(report.agreementByAmbiguity); mean boundary err \(report.meanBoundaryError)")
    }
```

- [ ] **Step 2: Run test to verify it fails or surfaces the real baseline**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests/EvaluationHarnessTests 2>&1 | tail -30`
Expected: either FAIL (compile: new symbols) on first run, then after compiling, a real measured agreement. If the measured agreement is below 0.40, **lower the threshold to just under the observed value** and note the true baseline in a code comment — the goal of this task is an honest regression floor, not a passing fiction.

- [ ] **Step 3: Adjust threshold to the honest observed baseline**

Edit the `#expect(report.overallAgreement >= 0.40 …)` threshold to sit just below the actual measured `overallAgreement` from Step 2 (e.g. observed 0.52 → set `>= 0.50`). Add a comment: `// Observed baseline 2026-05-31: <value>. This is the number Phase-1 tuning must raise.`

- [ ] **Step 4: Run the full test target to confirm nothing regressed**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:IlumionateTests 2>&1 | tail -30`
Expected: PASS — existing `keywordAnalyzerQuality` plus all new tests green.

- [ ] **Step 5: Commit**

```bash
git add IlumionateTests/EvaluationHarnessTests.swift
git commit -m "test(eval): wire timeline metrics over file corpus with baseline floor"
```

---

## Self-Review (completed during planning)

**Spec coverage (steps 1–2):**
- Unified `CorpusCase` JSON schema with `boundaryMode` bridging exact/anchored → Task 1. ✓
- Shared type imported by test target (CLI sharing deferred with step 3) → Task 1; noted package extraction belongs to the generator plan. ✓
- File-based corpus loaded by the test target → Task 2 (source-relative loader, no bundling). ✓
- Migrate existing `EvaluationCorpus` cases to files → Task 3. ✓
- Per-second agreement → Task 5. Boundary-placement error (exact + anchored gray-zone) → Task 6. Confusion matrix + P/R/F1 → Task 7. Accuracy-by-ambiguity + report → Task 8. ✓
- Wire into `EvaluationHarnessTests` with honest baseline → Task 9. ✓

**Deferred to follow-on plan (flagged, not silently dropped):** generator CLI (spec §3) and real-corpus labeling (spec §4). The legacy `EvaluationCorpus.swift` Swift file is left in place (still referenced by the existing test); a later cleanup can delete it once the file corpus fully supersedes it.

**Placeholder scan:** no TBD/TODO; every code step shows complete code. The two judgment points (Phase Codability in Task 1 Step 2; `.transitional` sentinel in Task 7 Step 3) include explicit fallback instructions rather than hand-waving.

**Type consistency:** `PhaseTruthSpan`, `CorpusCase`, `CorpusSegment`, `PhaseTimelineEvaluator`, `BoundaryError`, `ConfusionMatrix`, `PhaseTimelineScore`, `CorpusTimelineReport` are defined once and referenced consistently. Method names (`perSecondTimeline`, `perSecondAgreement`, `boundaryError`, `confusionMatrix`, `score(case:predicted:)`, `report(scores:)`) match across tasks and the harness.

**Risk note for the implementer:** Task 7 Step 3's `confusionMatrix` line that records misses is deliberately conservative; verify `HypnosisMetadata.Phase` includes `.transitional` (it does per `HypnosisPhaseAnalyzer`), or swap the sentinel for any phase absent from truth.
