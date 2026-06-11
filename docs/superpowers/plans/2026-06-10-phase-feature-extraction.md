# Phase Feature Extraction & Dataset Export — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable per-second `PhaseFeatureExtractor` (app target) that turns a transcription into a fixed-width numeric feature vector using the existing analyzer extractors, plus a test-driven `PhaseDatasetExporter` that writes a training-ready CSV from the labeled corpus.

**Architecture:** `PhaseFeatureExtractor` precomputes per-second signals once (keyword hit-map, transcript section analysis, technique-marker density) and yields a `PhaseFeatureVector` per second. `PhaseDatasetExporter` loops the labeled corpus and emits one CSV row per labeled second (gray zones skipped). The extractor is real runtime code (reused later at model inference); the exporter is an offline dev harness in the test target.

**Tech Stack:** Swift 6.2, Swift Testing, CorpusKit (SPM), the iOS app target. Tests run via `xcodebuild test` on the iOS simulator.

---

## Reference: exact APIs this plan uses (verified 2026-06-10)

- `HypnosisPhaseAnalyzer()` — `func approximateWordTimestamps(from segments: [AudioTranscriptionSegment]) -> [WordTimestamp]`; `func buildHitMap(wordTimestamps: [WordTimestamp], bucketCount: Int) -> [[HypnosisMetadata.Phase: Double]]`.
- `TrancePhase.orderedHypnosisPhases` — 11 phases (`HypnosisMetadata.Phase` is `typealias Phase = TrancePhase`).
- `TranscriptFeatureAnalyzer()` — `func analyze(transcription: AudioTranscriptionResult, phases: [PhaseSegment]? = nil) -> TranscriptAnalysis`. `TranscriptAnalysis` has `func section(at time: TimeInterval) -> TranscriptSectionMetrics?`. `TranscriptSectionMetrics` fields used: `normalizedWordsPerMinute`, `normalizedSpeechCoverage`, `normalizedLexicalDiversity`, `normalizedRepetitionDensity` (all `Double`).
- `TechniqueDetector()` — `func detect(wordTimestamps:segments:prosodic:duration:) -> TechniqueDetectionResult`. `TechniqueDetectionResult.markers: [LinguisticMarker]`; `LinguisticMarker.timestamp: TimeInterval`.
- `CorpusCase` (CorpusKit): `id: String`, `duration: TimeInterval`, `truth: [PhaseTruthSpan]`, `segments`, and the test-target extension `var transcriptionSegments: [AudioTranscriptionSegment]` (already in `IlumionateTests/Corpus/CorpusCaseAppBridge.swift`), `var transcriptText: String`. `PhaseTruthSpan { phase: TrancePhase, start, end }`.
- Build/test destination: `platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5`. NOTE: `-only-testing` must target a **struct/suite** id, not a method (a method filter matches zero Swift Testing tests).

## File Structure

| File | Target | Responsibility |
|---|---|---|
| `Ilumionate/Training/PhaseFeatureExtractor.swift` | app | `PhaseFeatureVector` + `PhaseFeatureExtractor` (precompute + per-second vector) |
| `IlumionateTests/Corpus/PhaseFeatureExtractorTests.swift` | test | unit tests for the extractor |
| `IlumionateTests/Corpus/PhaseDatasetExporter.swift` | test | `PhaseDatasetExporter` (corpus → CSV) |
| `IlumionateTests/Corpus/PhaseDatasetExportTests.swift` | test | export harness + CSV shape assertions |
| `.gitignore` | repo | ignore `Corpus/dataset/*.csv` |
| `Corpus/dataset/phase-features.csv` | output | generated (gitignored) |

---

### Task 1: `PhaseFeatureVector` + extractor with position & keyword features

**Files:**
- Create: `Ilumionate/Training/PhaseFeatureExtractor.swift`
- Test: `IlumionateTests/Corpus/PhaseFeatureExtractorTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/Corpus/PhaseFeatureExtractorTests.swift`:

```swift
import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct PhaseFeatureExtractorTests {

    private func transcription() -> AudioTranscriptionResult {
        AudioTranscriptionResult(
            fullText: "close your eyes and relax going deeper and deeper",
            segments: [
                AudioTranscriptionSegment(text: "close your eyes and relax", timestamp: 0, duration: 30, confidence: 1),
                AudioTranscriptionSegment(text: "going deeper and deeper", timestamp: 30, duration: 30, confidence: 1),
            ],
            duration: 60, detectedLanguage: "en"
        )
    }

    @Test("Header and vector width are equal and constant across seconds")
    func headerMatchesWidth() {
        let extractor = PhaseFeatureExtractor(transcription: transcription())
        let names = PhaseFeatureExtractor.columnNames
        #expect(names.first == "position")
        #expect(names.contains("kw_induction"))
        #expect(extractor.featureVector(at: 0).values.count == names.count)
        #expect(extractor.featureVector(at: 45).values.count == names.count)
    }

    @Test("Position is second/duration and increases over time")
    func positionMonotonic() {
        let extractor = PhaseFeatureExtractor(transcription: transcription())
        let p0 = extractor.featureVector(at: 0).value(for: "position")
        let p30 = extractor.featureVector(at: 30).value(for: "position")
        #expect(p0 == 0.0)
        #expect(abs(p30 - 0.5) < 1e-9)
    }

    @Test("Keyword features reflect the hit-map (induction keywords fire early)")
    func keywordFeaturesPresent() {
        let extractor = PhaseFeatureExtractor(transcription: transcription())
        let early = extractor.featureVector(at: 5)
        #expect(early.value(for: "kw_induction") > 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:IlumionateTests/PhaseFeatureExtractorTests 2>&1 | grep -E 'error:|TEST'
```
Expected: build error — `cannot find 'PhaseFeatureExtractor' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Ilumionate/Training/PhaseFeatureExtractor.swift`:

```swift
//  PhaseFeatureExtractor.swift
//  Ilumionate
//
//  Per-second feature vectors for the learned phase model. Reuses the SAME
//  extractors the analyzer uses (keyword hit-map, transcript features, technique
//  markers, position) so training and inference features match. Deterministic.
//
import Foundation

/// An ordered, named numeric feature vector for one second of a session.
struct PhaseFeatureVector: Sendable {
    let values: [Double]

    /// Value for a named column (linear lookup; vectors are small).
    func value(for column: String) -> Double {
        guard let index = PhaseFeatureExtractor.columnNames.firstIndex(of: column) else { return 0 }
        return values[index]
    }
}

@MainActor
struct PhaseFeatureExtractor {
    private let duration: TimeInterval
    private let bucketCount: Int
    private let hitMap: [[HypnosisMetadata.Phase: Double]]

    /// Stable feature column order (excludes trace columns and the label).
    static let columnNames: [String] =
        ["position"] + TrancePhase.orderedHypnosisPhases.map { "kw_\($0.rawValue)" }

    init(transcription: AudioTranscriptionResult) {
        self.duration = max(transcription.duration, 1)
        self.bucketCount = max(1, Int(ceil(transcription.duration)))
        let analyzer = HypnosisPhaseAnalyzer()
        let words = analyzer.approximateWordTimestamps(from: transcription.segments)
        self.hitMap = words.isEmpty
            ? Array(repeating: [:], count: bucketCount)
            : analyzer.buildHitMap(wordTimestamps: words, bucketCount: bucketCount)
    }

    func featureVector(at second: Int) -> PhaseFeatureVector {
        let bucket = min(max(second, 0), bucketCount - 1)
        var values: [Double] = [Double(second) / duration]
        for phase in TrancePhase.orderedHypnosisPhases {
            values.append(hitMap[bucket][phase] ?? 0)
        }
        return PhaseFeatureVector(values: values)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: all 3 tests pass (`** TEST SUCCEEDED **`).

> If the compiler reports actor-isolation errors on `HypnosisPhaseAnalyzer`/`buildHitMap`, the type already runs main-actor-isolated in this project; the `@MainActor` on `PhaseFeatureExtractor` and the `@MainActor` test struct cover it. No change needed.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/Training/PhaseFeatureExtractor.swift IlumionateTests/Corpus/PhaseFeatureExtractorTests.swift
git commit -m "feat(training): per-second feature extractor (position + keyword scores)"
```

---

### Task 2: Add transcript-feature columns (`tf_*`)

**Files:**
- Modify: `Ilumionate/Training/PhaseFeatureExtractor.swift`
- Test: `IlumionateTests/Corpus/PhaseFeatureExtractorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `PhaseFeatureExtractorTests`:

```swift
    @Test("Transcript-feature columns exist and are finite")
    func transcriptFeatureColumns() {
        let extractor = PhaseFeatureExtractor(transcription: transcription())
        let names = PhaseFeatureExtractor.columnNames
        for column in ["tf_wpm", "tf_coverage", "tf_lexical", "tf_repetition"] {
            #expect(names.contains(column), "missing \(column)")
        }
        let v = extractor.featureVector(at: 10)
        #expect(v.value(for: "tf_wpm").isFinite)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:IlumionateTests/PhaseFeatureExtractorTests 2>&1 | grep -E 'error:|TEST|missing'
```
Expected: the new test FAILS (`missing tf_wpm`) and `headerMatchesWidth` may also fail (width changed) — that is fine; it confirms RED.

- [ ] **Step 3: Write minimal implementation**

In `PhaseFeatureExtractor.swift`, add a stored `analysis` and extend `columnNames` + `featureVector`:

```swift
// add near the other stored properties:
    private let analysis: TranscriptAnalysis

// replace columnNames:
    static let columnNames: [String] =
        ["position"]
        + TrancePhase.orderedHypnosisPhases.map { "kw_\($0.rawValue)" }
        + ["tf_wpm", "tf_coverage", "tf_lexical", "tf_repetition"]

// in init(), after building hitMap:
        self.analysis = TranscriptFeatureAnalyzer().analyze(transcription: transcription, phases: nil)

// in featureVector(at:), before `return`, after the keyword loop:
        let section = analysis.section(at: Double(second) + 0.5)
        values.append(section?.normalizedWordsPerMinute ?? 0)
        values.append(section?.normalizedSpeechCoverage ?? 0)
        values.append(section?.normalizedLexicalDiversity ?? 0)
        values.append(section?.normalizedRepetitionDensity ?? 0)
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/Training/PhaseFeatureExtractor.swift IlumionateTests/Corpus/PhaseFeatureExtractorTests.swift
git commit -m "feat(training): add normalized transcript-feature columns"
```

---

### Task 3: Add technique-marker density column (`tech_marker_density`)

**Files:**
- Modify: `Ilumionate/Training/PhaseFeatureExtractor.swift`
- Test: `IlumionateTests/Corpus/PhaseFeatureExtractorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `PhaseFeatureExtractorTests`:

```swift
    @Test("Technique-marker density column exists and is non-negative")
    func techniqueDensityColumn() {
        let extractor = PhaseFeatureExtractor(transcription: transcription())
        #expect(PhaseFeatureExtractor.columnNames.last == "tech_marker_density")
        #expect(extractor.featureVector(at: 10).value(for: "tech_marker_density") >= 0)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:IlumionateTests/PhaseFeatureExtractorTests 2>&1 | grep -E 'error:|TEST'
```
Expected: FAIL (last column is not `tech_marker_density`).

- [ ] **Step 3: Write minimal implementation**

In `PhaseFeatureExtractor.swift`:

```swift
// add stored property:
    private let markerDensity: [Double]   // markers landing in each 1s bucket

// extend columnNames (append):
        + ["tech_marker_density"]

// in init(), after building analysis:
        let detector = TechniqueDetector()
        let detection = words.isEmpty
            ? TechniqueDetectionResult(techniques: [], markers: [])
            : detector.detect(
                wordTimestamps: words,
                segments: transcription.segments,
                prosodic: nil,
                duration: transcription.duration
              )
        var density = Array(repeating: 0.0, count: bucketCount)
        for marker in detection.markers {
            let bucket = min(max(Int(marker.timestamp), 0), bucketCount - 1)
            density[bucket] += 1
        }
        self.markerDensity = density

// in featureVector(at:), append at the very end before `return`:
        values.append(markerDensity[bucket])
```

> `TechniqueDetectionResult(techniques:markers:)` is its memberwise init (internal; reachable via `@testable`/app target). Confirm the empty-init path compiles; if the type lacks a public memberwise init, instead guard with `words.isEmpty ? [] : detector.detect(...).markers` and iterate that array.

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: all extractor tests pass.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/Training/PhaseFeatureExtractor.swift IlumionateTests/Corpus/PhaseFeatureExtractorTests.swift
git commit -m "feat(training): add technique-marker density column"
```

---

### Task 4: `PhaseDatasetExporter` (corpus → CSV)

**Files:**
- Create: `IlumionateTests/Corpus/PhaseDatasetExporter.swift`
- Test: `IlumionateTests/Corpus/PhaseDatasetExportTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/Corpus/PhaseDatasetExportTests.swift`:

```swift
import Testing
import Foundation
import CorpusKit
@testable import Ilumionate

@MainActor
struct PhaseDatasetExportTests {

    private func makeCase() -> CorpusCase {
        CorpusCase(
            id: "t1", source: .synthetic, boundaryMode: .exact, ambiguityLevel: .low,
            duration: 60,
            segments: [
                CorpusSegment(text: "close your eyes and relax", timestamp: 0, duration: 30, confidence: 1),
                CorpusSegment(text: "going deeper and deeper", timestamp: 30, duration: 30, confidence: 1),
            ],
            truth: [
                PhaseTruthSpan(phase: .induction, start: 0, end: 30),
                PhaseTruthSpan(phase: .deepening, start: 30, end: 60),
            ]
        )
    }

    @Test("Exports a header plus one row per labeled second")
    func exportsRowsForLabeledSeconds() throws {
        let url = URL.temporaryDirectory.appending(path: "ds-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        let count = try PhaseDatasetExporter().export(cases: [makeCase()], to: url)
        #expect(count == 60)   // all 60 seconds are labeled (no gray zones)

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 61)  // header + 60 rows
        #expect(lines.first?.hasPrefix("case_id,second,") == true)
        #expect(lines.first?.hasSuffix(",label") == true)

        // Every data row's label parses to a TrancePhase.
        for line in lines.dropFirst() {
            let label = line.split(separator: ",").last.map(String.init) ?? ""
            #expect(TrancePhase(rawValue: label) != nil, "bad label: \(label)")
        }
    }

    @Test("Gray-zone seconds are skipped")
    func skipsGrayZones() throws {
        // Anchor only 0-20; 20-60 is gray.
        let kase = CorpusCase(
            id: "g1", source: .real, boundaryMode: .anchored, ambiguityLevel: .unspecified,
            duration: 60, segments: makeCase().segments,
            truth: [PhaseTruthSpan(phase: .induction, start: 0, end: 20)]
        )
        let url = URL.temporaryDirectory.appending(path: "ds-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        let count = try PhaseDatasetExporter().export(cases: [kase], to: url)
        #expect(count == 20)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:IlumionateTests/PhaseDatasetExportTests 2>&1 | grep -E 'error:|TEST'
```
Expected: build error — `cannot find 'PhaseDatasetExporter' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `IlumionateTests/Corpus/PhaseDatasetExporter.swift`:

```swift
//  PhaseDatasetExporter.swift
//  IlumionateTests
//
//  Offline dev harness: loops labeled CorpusCases and writes one CSV row per
//  labeled second via PhaseFeatureExtractor. Gray-zone seconds are skipped.
//
import Foundation
import CorpusKit
@testable import Ilumionate

@MainActor
struct PhaseDatasetExporter {

    /// Truth phase covering `time` (half-open spans), or nil in a gray zone.
    private func phase(at time: TimeInterval, in spans: [PhaseTruthSpan]) -> TrancePhase? {
        for span in spans where time >= span.start && time < span.end { return span.phase }
        return nil
    }

    /// Writes the CSV to `url`, returning the number of data rows emitted.
    @discardableResult
    func export(cases: [CorpusCase], to url: URL) throws -> Int {
        let header = "case_id,second," + PhaseFeatureExtractor.columnNames.joined(separator: ",") + ",label"
        var lines: [String] = [header]
        var rows = 0

        for kase in cases.sorted(by: { $0.id < $1.id }) where !kase.truth.isEmpty {
            let transcription = AudioTranscriptionResult(
                fullText: kase.transcriptText,
                segments: kase.transcriptionSegments,
                duration: kase.duration,
                detectedLanguage: "en"
            )
            let extractor = PhaseFeatureExtractor(transcription: transcription)
            let bucketCount = max(1, Int(ceil(kase.duration)))
            for second in 0..<bucketCount {
                guard let truth = phase(at: Double(second) + 0.5, in: kase.truth) else { continue }
                let values = extractor.featureVector(at: second).values
                    .map { String(format: "%.6f", $0) }
                    .joined(separator: ",")
                lines.append("\(kase.id),\(second),\(values),\(truth.rawValue)")
                rows += 1
            }
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return rows
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: both export tests pass.

- [ ] **Step 5: Commit**

```bash
git add IlumionateTests/Corpus/PhaseDatasetExporter.swift IlumionateTests/Corpus/PhaseDatasetExportTests.swift
git commit -m "feat(training): dataset exporter writes per-second feature CSV"
```

---

### Task 5: Gitignore the generated dataset

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Add the ignore rule**

Append to `.gitignore` after the `Corpus/real/*.json` block:

```gitignore

# Generated training dataset (derived from labeled corpus; regenerate, don't commit)
Corpus/dataset/*.csv
```

- [ ] **Step 2: Verify it is ignored**

Run:
```bash
mkdir -p Corpus/dataset && touch Corpus/dataset/phase-features.csv
git check-ignore Corpus/dataset/phase-features.csv && echo "ignored"
```
Expected: prints the path and `ignored`.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore generated phase-feature dataset"
```

---

### Task 6: Generate the real dataset from the corpus & verify

**Files:**
- Test: `IlumionateTests/Corpus/PhaseDatasetExportTests.swift` (add one generation test)

- [ ] **Step 1: Write the generation test**

Append to `PhaseDatasetExportTests`:

```swift
    @Test("Generates phase-features.csv from the on-disk labeled corpus")
    func generatesFromCorpus() throws {
        let cases = try (CorpusLoader.load(subdirectory: "fixtures")
                       + CorpusLoader.load(subdirectory: "synthetic")
                       + CorpusLoader.load(subdirectory: "real"))
            .filter { !$0.truth.isEmpty }
        try #require(!cases.isEmpty, "no truth-bearing corpus cases")

        let out = CorpusLoader.corpusRoot.appending(path: "dataset").appending(path: "phase-features.csv")
        let rows = try PhaseDatasetExporter().export(cases: cases, to: out)
        #expect(rows > 0)

        // Re-parse: header width matches every data row's column count.
        let text = try String(contentsOf: out, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let expectedColumns = lines.first!.split(separator: ",", omittingEmptySubsequences: false).count
        for line in lines.dropFirst() {
            #expect(line.split(separator: ",", omittingEmptySubsequences: false).count == expectedColumns)
        }
    }
```

- [ ] **Step 2: Run it (this also writes the dataset)**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:IlumionateTests/PhaseDatasetExportTests 2>&1 | grep -E 'error:|TEST'
```
Expected: PASS. Then confirm the file exists and is gitignored:
```bash
ls -la Corpus/dataset/phase-features.csv
git status --short Corpus/dataset/   # expect no output (ignored)
head -1 Corpus/dataset/phase-features.csv
```

- [ ] **Step 3: Full regression check**

Run the broader suite to confirm no regressions:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -only-testing:IlumionateTests/PhaseFeatureExtractorTests \
  -only-testing:IlumionateTests/PhaseDatasetExportTests \
  -only-testing:IlumionateTests/KeywordPipelineEvaluationTests 2>&1 | grep -E 'TEST SUCCEEDED|TEST FAILED'
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add IlumionateTests/Corpus/PhaseDatasetExportTests.swift
git commit -m "test(training): generate + validate phase-features.csv from corpus"
```

---

## Done when

- `PhaseFeatureExtractor` yields a deterministic fixed-width per-second vector (`position` + `kw_*`×11 + 4 `tf_*` + `tech_marker_density`) reusing the real extractors.
- `PhaseDatasetExporter` writes `Corpus/dataset/phase-features.csv` from the labeled corpus, gray zones excluded.
- The CSV is gitignored; all new tests and `KeywordPipelineEvaluationTests` are green.

## Notes / future (out of scope)

- Audio/prosody features (`prosodic:` is passed `nil` — corpus has no audio).
- Richer per-phase technique evidence (current `tech_marker_density` is a single scalar).
- The model, training pipeline, Core ML conversion, learned transition matrix, and runtime integration.
