# Analyzer Improvement Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a decoupled, config-driven analyzer with a labeling UI and an evolutionary improvement pipeline that iterates the analyzer toward ground-truth accuracy.

**Architecture:** Three independent pieces communicating through JSON files: (1) Labeling UI in-app produces `LabeledFile.json` per audio, (2) evolutionary pipeline in the Xcode test target reads labeled data + config, evaluates, mutates, and writes better configs, (3) the app runtime loads the best `AnalyzerConfig.json` at startup.

**Tech Stack:** Swift 6.2, SwiftUI (iOS 26), @Observable, Swift Testing, AVFoundation (audio playback for labeling), CryptoKit (SHA256 for file fingerprinting)

---

## File Map

### New Files — App Target

| File | Responsibility |
|------|---------------|
| `Ilumionate/AnalyzerConfig/AnalyzerConfig.swift` | Codable model with nested structs for all config sections |
| `Ilumionate/AnalyzerConfig/AnalyzerConfigLoader.swift` | Load config from Documents (trained) or Bundle (default) |
| `Ilumionate/AnalyzerConfig/AnalyzerConfig_default.json` | Baseline config extracted from current hardcoded values |
| `Ilumionate/Training/LabeledFile.swift` | Codable model for ground-truth labeled audio files |
| `Ilumionate/Training/TrainingCorpusManager.swift` | CRUD operations for labeled files on disk |
| `Ilumionate/Training/CorpusManagerView.swift` | List of labeled files with status, import button |
| `Ilumionate/Training/PhaseLabelingView.swift` | Quick-label + refine UI with audio playback |

### New Files — Test Target

| File | Responsibility |
|------|---------------|
| `IlumionateTests/Training/FitnessEvaluator.swift` | Extended scoring with phase boundary accuracy |
| `IlumionateTests/Training/MutationOperators.swift` | Per-parameter-type mutation strategies |
| `IlumionateTests/Training/EvolutionaryOptimizer.swift` | Population management, selection, crossover |
| `IlumionateTests/Training/PipelineRunner.swift` | Orchestrates generations, caching, report output |
| `IlumionateTests/Training/EvolutionaryPipelineTests.swift` | Entry point test to run the pipeline |

### Modified Files

| File | Change |
|------|--------|
| `Ilumionate/HypnosisPhaseAnalyzer.swift` | Accept `AnalyzerConfig.KeywordPipeline` at init, read weights/thresholds from it |
| `Ilumionate/ChunkedPhaseAnalyzer.swift` | Accept `AnalyzerConfig.ChunkedAnalyzer` at init, read chunk params + prompt from it |
| `Ilumionate/ChunkedPhaseAnalyzer+Smoothing.swift` | Accept config params for collapse threshold |
| `Ilumionate/ProsodyAnalyzer.swift` | Map `AnalyzerConfig.Prosody` to existing `Config` struct |
| `Ilumionate/TechniqueDetector.swift` | Accept `AnalyzerConfig.TechniqueDetection` for thresholds |
| `Ilumionate/SessionGenerator+Strategies.swift` | Accept `AnalyzerConfig.SessionGeneration` for frequency bands |
| `Ilumionate/SessionGenerator.swift` | Pass config through to strategies |
| `Ilumionate/AIAnalysisManager.swift` | Load and pass config to sub-analyzers |
| `Ilumionate/AIAnalysisManager+Prompts.swift` | Read prompt text from config |
| `IlumionateTests/AnalysisEvaluationMetrics.swift` | Add `phaseBoundaryScore` to `AnalysisQualityScore` |
| `IlumionateTests/EvaluationHarnessTests.swift` | Pass config to analyzers |

---

## Task 1: AnalyzerConfig Codable Model

**Files:**
- Create: `Ilumionate/AnalyzerConfig/AnalyzerConfig.swift`

This is the foundational type everything else depends on.

- [ ] **Step 1: Create the AnalyzerConfig model**

Create `Ilumionate/AnalyzerConfig/AnalyzerConfig.swift`:

```swift
//
//  AnalyzerConfig.swift
//  Ilumionate
//
//  Single JSON-driven configuration for all analyzer components.
//  The evolutionary pipeline mutates this to improve accuracy.
//

import Foundation

struct AnalyzerConfig: Codable, Sendable {

    var version: Int = 1
    var generation: Int = 0
    var fitness: Double = 0.0

    var keywordPipeline: KeywordPipeline
    var chunkedAnalyzer: ChunkedAnalyzer
    var prosody: Prosody
    var techniqueDetection: TechniqueDetection
    var sessionGeneration: SessionGeneration

    // MARK: - Keyword Pipeline

    struct KeywordPipeline: Codable, Sendable {
        /// Phase name (raw value) → keyword → weight
        var weights: [String: [String: Double]]
        var contextWindowSeconds: Int
        var smoothingWindowSize: Int
        var minimumPhaseDurationSeconds: Int
        var collapseThresholdFraction: Double

        func weightsForPhase(_ phase: HypnosisMetadata.Phase) -> [String: Double] {
            weights[phase.rawValue] ?? [:]
        }
    }

    // MARK: - Chunked Analyzer (Foundation Models)

    struct ChunkedAnalyzer: Codable, Sendable {
        var chunkDurationSeconds: Double
        var chunkOverlapSeconds: Double
        var minChunks: Int
        var maxChunks: Int
        var systemInstructions: String
        var fewShotExamples: [FewShotExample]

        struct FewShotExample: Codable, Sendable {
            var text: String
            var position: Double
            var correctPhase: String
        }
    }

    // MARK: - Prosody

    struct Prosody: Codable, Sendable {
        var speechRateWindowSeconds: Double
        var pauseThresholdSeconds: Double
        var deliberatePauseMinSeconds: Double
        var musicOnlyPauseMinSeconds: Double
    }

    // MARK: - Technique Detection

    struct TechniqueDetection: Codable, Sendable {
        var sensitivityThreshold: Double
        var minConfidence: Double
    }

    // MARK: - Session Generation

    struct SessionGeneration: Codable, Sendable {
        var frequencyBands: [String: FrequencyBand]
        var transitionSmoothingSeconds: Double
        var intensityCurve: String

        struct FrequencyBand: Codable, Sendable {
            var lower: Double
            var upper: Double

            var closedRange: ClosedRange<Double> { lower...upper }
        }

        func band(for contentType: AnalysisResult.ContentType) -> FrequencyBand {
            frequencyBands[contentType.rawValue] ?? FrequencyBand(lower: 8.0, upper: 12.0)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/AnalyzerConfig/AnalyzerConfig.swift
git commit -m "feat: add AnalyzerConfig Codable model"
```

---

## Task 2: Default Config JSON + Loader

**Files:**
- Create: `Ilumionate/AnalyzerConfig/AnalyzerConfig_default.json`
- Create: `Ilumionate/AnalyzerConfig/AnalyzerConfigLoader.swift`

Extract every hardcoded constant from the current codebase into the default JSON. The loader reads config with Documents-first fallback.

- [ ] **Step 1: Create the default config JSON**

Create `Ilumionate/AnalyzerConfig/AnalyzerConfig_default.json`. This must be added to the Xcode project with target membership for the app bundle.

The JSON must contain ALL current hardcoded values extracted from the explore agent's findings. The keyword weights come from `HypnosisPhaseAnalyzer.swift`'s `buildHitMap` method — read that method to extract the exact keyword dictionaries per phase.

Read `HypnosisPhaseAnalyzer.swift` lines 114-155 to find the exact keyword→weight mappings, then build the JSON with those exact values.

The system instructions come from `ChunkedPhaseAnalyzer.swift` lines 33-59 — copy the full text verbatim.

- [ ] **Step 2: Create the config loader**

Create `Ilumionate/AnalyzerConfig/AnalyzerConfigLoader.swift`:

```swift
//
//  AnalyzerConfigLoader.swift
//  Ilumionate
//
//  Loads AnalyzerConfig from Documents (trained) or Bundle (default).
//

import Foundation

enum AnalyzerConfigLoader {

    private static let documentsConfigURL: URL =
        URL.documentsDirectory.appending(path: "AnalyzerConfig.json")

    /// Loads the best available config: trained version from Documents,
    /// falling back to the bundled default.
    static func load() -> AnalyzerConfig {
        // 1. Try trained config in Documents
        if let data = try? Data(contentsOf: documentsConfigURL),
           let config = try? JSONDecoder().decode(AnalyzerConfig.self, from: data) {
            print("📐 Loaded trained AnalyzerConfig (gen \(config.generation), fitness \(config.fitness))")
            return config
        }

        // 2. Fall back to bundled default
        if let url = Bundle.main.url(forResource: "AnalyzerConfig_default", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(AnalyzerConfig.self, from: data) {
            print("📐 Loaded default AnalyzerConfig from bundle")
            return config
        }

        // 3. Last resort: hardcoded minimal config
        fatalError("No AnalyzerConfig found in Documents or Bundle — app cannot start")
    }

    /// Saves a trained config to Documents for the app to pick up.
    static func save(_ config: AnalyzerConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: documentsConfigURL, options: .atomic)
        print("💾 Saved AnalyzerConfig (gen \(config.generation)) to Documents")
    }
}
```

- [ ] **Step 3: Add JSON to Xcode target membership**

The `AnalyzerConfig_default.json` file must have target membership for the Ilumionate app target so it's included in the bundle. Verify by checking it appears in the project's "Copy Bundle Resources" build phase.

- [ ] **Step 4: Build to verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/AnalyzerConfig/
git commit -m "feat: add AnalyzerConfig default JSON and loader"
```

---

## Task 3: Refactor HypnosisPhaseAnalyzer to Use Config

**Files:**
- Modify: `Ilumionate/HypnosisPhaseAnalyzer.swift`

The keyword pipeline must read weights, context window, smoothing, and collapse threshold from config instead of hardcoded values.

- [ ] **Step 1: Add config property and update init**

Change `HypnosisPhaseAnalyzer` from a bare struct to one that stores config:

```swift
struct HypnosisPhaseAnalyzer {
    let config: AnalyzerConfig.KeywordPipeline

    init(config: AnalyzerConfig.KeywordPipeline? = nil) {
        self.config = config ?? AnalyzerConfigLoader.load().keywordPipeline
    }
```

The `?= nil` default means all existing callers still work without changes.

- [ ] **Step 2: Update analyze() to use config thresholds**

In the `analyze(segments:duration:)` method, replace hardcoded values:

```swift
func analyze(segments: [AudioTranscriptionSegment], duration: Double) -> [PhaseSegment] {
    let wordTimestamps = approximateWordTimestamps(from: segments)
    guard !wordTimestamps.isEmpty else { return [] }

    let bucketCount = max(1, Int(ceil(duration)))
    let hitMap      = buildHitMap(wordTimestamps: wordTimestamps, bucketCount: bucketCount)
    var timeline    = resolveTimeline(hitMap: hitMap, bucketCount: bucketCount)

    timeline = enforcePhaseOrdering(timeline: timeline)
    timeline = majorityVoteSmooth(timeline: timeline, windowSize: config.smoothingWindowSize)
    timeline = collapseShortRuns(timeline, minRun: max(config.minimumPhaseDurationSeconds, Int(duration * config.collapseThresholdFraction)))

    return consolidatePhaseSegments(timeline: timeline, duration: duration)
}
```

- [ ] **Step 3: Update buildHitMap to use config weights**

In `buildHitMap(wordTimestamps:bucketCount:)`, replace the hardcoded keyword dictionaries with `config.weightsForPhase(phase)`. The method currently has a dictionary literal per phase — replace each with a config lookup.

- [ ] **Step 4: Update resolveTimeline to use config context window**

In `resolveTimeline(hitMap:bucketCount:)`, replace `contextRadius = 5` with `config.contextWindowSeconds`.

- [ ] **Step 5: Build and verify all callers still work**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` — the default parameter on init means no callers need updating yet.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/HypnosisPhaseAnalyzer.swift
git commit -m "refactor: HypnosisPhaseAnalyzer reads from AnalyzerConfig"
```

---

## Task 4: Refactor ChunkedPhaseAnalyzer to Use Config

**Files:**
- Modify: `Ilumionate/ChunkedPhaseAnalyzer.swift`
- Modify: `Ilumionate/ChunkedPhaseAnalyzer+Smoothing.swift`

- [ ] **Step 1: Add config to ChunkedPhaseAnalyzer**

The current struct uses all static constants. Add a stored config property and update the public entry point:

```swift
struct ChunkedPhaseAnalyzer {
    let config: AnalyzerConfig.ChunkedAnalyzer

    init(config: AnalyzerConfig.ChunkedAnalyzer? = nil) {
        self.config = config ?? AnalyzerConfigLoader.load().chunkedAnalyzer
    }
```

- [ ] **Step 2: Replace hardcoded chunk parameters**

Replace `Self.chunkDuration` with `config.chunkDurationSeconds`, `Self.chunkOverlap` with `config.chunkOverlapSeconds`, `Self.minChunks` with `config.minChunks`, `Self.maxChunks` with `config.maxChunks`.

Update `chunkCount(for:)` to use the config values.

- [ ] **Step 3: Replace systemInstructions with config**

Replace the static `systemInstructions` string with `config.systemInstructions`.

- [ ] **Step 4: Add few-shot examples to the prompt**

In `classifySingleChunk(request:previousPhase:model:)`, after the system instructions, append few-shot examples from config:

```swift
var prompt = "..."
if !config.fewShotExamples.isEmpty {
    prompt += "\n\nExamples:\n"
    for example in config.fewShotExamples {
        prompt += "Position: \(Int(example.position * 100))% | Text: \"\(example.text)\" → \(example.correctPhase)\n"
    }
}
```

- [ ] **Step 5: Update smoothing extension**

In `ChunkedPhaseAnalyzer+Smoothing.swift`, update any methods that take hardcoded values to accept them as parameters passed from the config.

- [ ] **Step 6: Update callers in AIAnalysisManager.swift**

In `AIAnalysisManager.swift`, the `runPhaseAnalysis` method creates a `ChunkedPhaseAnalyzer`. Update it to pass config:

```swift
let chunkedConfig = AnalyzerConfigLoader.load().chunkedAnalyzer
let chunked = ChunkedPhaseAnalyzer(config: chunkedConfig)
```

- [ ] **Step 7: Build and verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 8: Commit**

```bash
git add Ilumionate/ChunkedPhaseAnalyzer.swift Ilumionate/ChunkedPhaseAnalyzer+Smoothing.swift Ilumionate/AIAnalysisManager.swift
git commit -m "refactor: ChunkedPhaseAnalyzer reads from AnalyzerConfig"
```

---

## Task 5: Refactor Remaining Analyzers to Use Config

**Files:**
- Modify: `Ilumionate/ProsodyAnalyzer.swift`
- Modify: `Ilumionate/TechniqueDetector.swift`
- Modify: `Ilumionate/SessionGenerator.swift`
- Modify: `Ilumionate/SessionGenerator+Strategies.swift`
- Modify: `Ilumionate/AIAnalysisManager+Prompts.swift`

- [ ] **Step 1: ProsodyAnalyzer — map config to existing Config struct**

ProsodyAnalyzer already has a `Config` struct (line 30). Add an initializer that creates it from `AnalyzerConfig.Prosody`:

```swift
extension ProsodyAnalyzer.Config {
    init(from analyzerConfig: AnalyzerConfig.Prosody) {
        self.init(
            windowDuration: analyzerConfig.speechRateWindowSeconds,
            silenceThreshold: 0.008, // hardware constant, not tunable
            minPauseDuration: analyzerConfig.pauseThresholdSeconds,
            deliberatePauseMin: analyzerConfig.deliberatePauseMinSeconds,
            extendedPauseMin: analyzerConfig.musicOnlyPauseMinSeconds,
            minPitchHz: 70.0, // hardware constant
            maxPitchHz: 400.0  // hardware constant
        )
    }
}
```

Update callers to use this initializer.

- [ ] **Step 2: TechniqueDetector — add config property**

Add `config: AnalyzerConfig.TechniqueDetection` as a stored property with a default-init pattern:

```swift
struct TechniqueDetector {
    let config: AnalyzerConfig.TechniqueDetection

    init(config: AnalyzerConfig.TechniqueDetection? = nil) {
        self.config = config ?? AnalyzerConfigLoader.load().techniqueDetection
    }
```

Replace the hardcoded `strength >= 0.6` thresholds with `config.sensitivityThreshold`, and `minConfidence` usage for technique recording decisions.

- [ ] **Step 3: SessionGenerator — pass config to strategies**

Add `config: AnalyzerConfig.SessionGeneration` to `SessionGenerator`:

```swift
struct SessionGenerator {
    let config: AnalyzerConfig.SessionGeneration

    init(config: AnalyzerConfig.SessionGeneration? = nil) {
        self.config = config ?? AnalyzerConfigLoader.load().sessionGeneration
    }
```

In `generateSession(from:analysis:config:)`, use `self.config.band(for: analysis.contentType)` for frequency band selection instead of the hardcoded per-type constants.

- [ ] **Step 4: SessionGenerator+Strategies — use config frequency bands**

Update `frequencyRangeForPhase(_:)`, the strategy-specific frequency constants, and `transitionSmoothingSeconds` to read from `config`.

- [ ] **Step 5: AIAnalysisManager+Prompts — read prompt text from config**

Update `buildTranscriptionPrompt` to read classification guidance and frequency band text from config instead of hardcoded strings. The prompt structure stays the same, but the values come from config.

- [ ] **Step 6: Build and verify the full pipeline still works**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 7: Commit**

```bash
git add Ilumionate/ProsodyAnalyzer.swift Ilumionate/TechniqueDetector.swift Ilumionate/SessionGenerator.swift Ilumionate/SessionGenerator+Strategies.swift Ilumionate/AIAnalysisManager+Prompts.swift
git commit -m "refactor: all analyzers read from AnalyzerConfig"
```

---

## Task 6: LabeledFile Model + TrainingCorpusManager

**Files:**
- Create: `Ilumionate/Training/LabeledFile.swift`
- Create: `Ilumionate/Training/TrainingCorpusManager.swift`

- [ ] **Step 1: Create LabeledFile model**

Create `Ilumionate/Training/LabeledFile.swift`:

```swift
//
//  LabeledFile.swift
//  Ilumionate
//
//  Ground-truth labeled audio file for analyzer training.
//

import Foundation
import CryptoKit

struct LabeledFile: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var version: Int = 1
    var audioFilename: String
    var audioDuration: TimeInterval
    var audioSHA256: String
    var expectedContentType: AnalysisResult.ContentType
    var expectedFrequencyBand: FrequencyBand
    var phases: [LabeledPhase]
    var techniques: [LabeledTechnique]
    var labeledAt: Date
    var labelerNotes: String

    /// Label completeness status
    var status: LabelStatus {
        if phases.isEmpty { return .unlabeled }
        let allHaveNotes = phases.allSatisfy { !($0.notes ?? "").isEmpty }
        return allHaveNotes ? .refined : .rough
    }

    enum LabelStatus: String, Codable, Sendable {
        case unlabeled, rough, refined
    }

    struct FrequencyBand: Codable, Sendable {
        var lower: Double
        var upper: Double
        var closedRange: ClosedRange<Double> { lower...upper }
    }

    struct LabeledPhase: Codable, Identifiable, Sendable {
        var id: UUID = UUID()
        var phase: HypnosisMetadata.Phase
        var startTime: TimeInterval
        var endTime: TimeInterval
        var notes: String?
    }

    struct LabeledTechnique: Codable, Identifiable, Sendable {
        var id: UUID = UUID()
        var name: String
        var startTime: TimeInterval
        var endTime: TimeInterval
    }

    /// Computes SHA256 of the first 64KB of the audio file.
    static func computeSHA256(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        guard !chunk.isEmpty else { return nil }
        return SHA256.hash(data: chunk).map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 2: Create TrainingCorpusManager**

Create `Ilumionate/Training/TrainingCorpusManager.swift`:

```swift
//
//  TrainingCorpusManager.swift
//  Ilumionate
//
//  CRUD for ground-truth labeled audio files stored in Documents/TrainingCorpus/.
//

import Foundation
import Observation

@MainActor @Observable
final class TrainingCorpusManager {

    static let shared = TrainingCorpusManager()

    var labeledFiles: [LabeledFile] = []

    private let corpusDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus")
    private let audioDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus/Audio")

    private init() {
        ensureDirectories()
        loadAll()
    }

    // MARK: - Directory Setup

    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [corpusDirectory, audioDirectory] {
            if !fm.fileExists(atPath: dir.path()) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Load

    func loadAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: corpusDirectory, includingPropertiesForKeys: nil) else { return }
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        labeledFiles = jsonFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(LabeledFile.self, from: data)
        }.sorted { $0.labeledAt > $1.labeledAt }

        print("📂 Loaded \(labeledFiles.count) labeled file(s)")
    }

    // MARK: - Save

    func save(_ file: LabeledFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        let url = corpusDirectory.appending(path: "\(file.id.uuidString).json")
        try data.write(to: url, options: .atomic)

        if let index = labeledFiles.firstIndex(where: { $0.id == file.id }) {
            labeledFiles[index] = file
        } else {
            labeledFiles.insert(file, at: 0)
        }
        print("💾 Saved labeled file: \(file.audioFilename)")
    }

    // MARK: - Import Audio

    func importAudio(from sourceURL: URL) throws -> LabeledFile {
        let filename = sourceURL.lastPathComponent
        let destURL = audioDirectory.appending(path: filename)

        if !FileManager.default.fileExists(atPath: destURL.path()) {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        }

        let asset = AVURLAsset(url: destURL)
        // Duration will be set asynchronously by the caller after import
        let sha256 = LabeledFile.computeSHA256(url: destURL) ?? ""

        let file = LabeledFile(
            audioFilename: filename,
            audioDuration: 0, // Caller must set after loading duration
            audioSHA256: sha256,
            expectedContentType: .hypnosis,
            expectedFrequencyBand: LabeledFile.FrequencyBand(lower: 0.5, upper: 10.0),
            phases: [],
            techniques: [],
            labeledAt: Date(),
            labelerNotes: ""
        )

        try save(file)
        return file
    }

    // MARK: - Delete

    func delete(_ file: LabeledFile) {
        let jsonURL = corpusDirectory.appending(path: "\(file.id.uuidString).json")
        try? FileManager.default.removeItem(at: jsonURL)

        let audioURL = audioDirectory.appending(path: file.audioFilename)
        try? FileManager.default.removeItem(at: audioURL)

        labeledFiles.removeAll { $0.id == file.id }
        print("🗑 Deleted labeled file: \(file.audioFilename)")
    }

    // MARK: - Audio URL

    func audioURL(for file: LabeledFile) -> URL {
        audioDirectory.appending(path: file.audioFilename)
    }
}
```

Note: The `import AVFoundation` will be needed at the top of the file for AVURLAsset. However, duration loading should be done asynchronously by the caller — the import method creates a placeholder with duration 0.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/Training/LabeledFile.swift Ilumionate/Training/TrainingCorpusManager.swift
git commit -m "feat: add LabeledFile model and TrainingCorpusManager"
```

---

## Task 7: Corpus Manager View (Labeling UI — Screen 1)

**Files:**
- Create: `Ilumionate/Training/CorpusManagerView.swift`

- [ ] **Step 1: Create CorpusManagerView**

Create `Ilumionate/Training/CorpusManagerView.swift`:

```swift
//
//  CorpusManagerView.swift
//  Ilumionate
//
//  List of ground-truth labeled audio files with status badges.
//  Accessed from Settings → Analyzer Training.
//

import SwiftUI
import UniformTypeIdentifiers

struct CorpusManagerView: View {

    @State private var corpusManager = TrainingCorpusManager.shared
    @State private var showingImporter = false
    @State private var selectedFile: LabeledFile?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if corpusManager.labeledFiles.isEmpty {
                    emptyState
                } else {
                    fileList
                }
            }
            .navigationTitle("Training Corpus")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import", systemImage: "plus.circle.fill") {
                        showingImporter = true
                    }
                    .foregroundStyle(Color.roseGold)
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .navigationDestination(for: LabeledFile.self) { file in
                PhaseLabelingView(file: file)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TranceSpacing.content) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(Color.roseGold)

            Text("No Training Files")
                .font(TranceTypography.greeting)
                .foregroundStyle(Color.textPrimary)

            Text("Import audio files to label with ground-truth phase data")
                .font(TranceTypography.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Button("Import Audio", systemImage: "plus.circle.fill") {
                showingImporter = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.roseGold)
        }
        .padding(TranceSpacing.screen)
    }

    // MARK: - File List

    private var fileList: some View {
        List {
            ForEach(corpusManager.labeledFiles) { file in
                NavigationLink(value: file) {
                    HStack(spacing: TranceSpacing.list) {
                        statusBadge(file.status)

                        VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                            Text(file.audioFilename)
                                .font(TranceTypography.body)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            HStack(spacing: TranceSpacing.inner) {
                                Text(Duration.seconds(file.audioDuration).formatted(.time(pattern: .minuteSecond)))
                                Text("·")
                                Text(file.phases.count.formatted() + " phases")
                                Text("·")
                                Text(file.expectedContentType.rawValue.capitalized)
                            }
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    corpusManager.delete(corpusManager.labeledFiles[index])
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Helpers

    private func statusBadge(_ status: LabeledFile.LabelStatus) -> some View {
        let (icon, color): (String, Color) = switch status {
        case .unlabeled: ("circle.dashed", .textLight)
        case .rough:     ("circle.lefthalf.filled", .warmAccent)
        case .refined:   ("checkmark.circle.fill", .roseGold)
        }
        return Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(color)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                var file = try corpusManager.importAudio(from: url)
                // Load duration asynchronously
                Task {
                    let asset = AVURLAsset(url: corpusManager.audioURL(for: file))
                    if let duration = try? await asset.load(.duration) {
                        file.audioDuration = CMTimeGetSeconds(duration)
                        try? corpusManager.save(file)
                    }
                }
            } catch {
                print("❌ Failed to import \(url.lastPathComponent): \(error)")
            }
        }
    }
}
```

Note: `LabeledFile` must conform to `Hashable` for `NavigationLink(value:)`. Add to `LabeledFile.swift`:

```swift
extension LabeledFile: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LabeledFile, rhs: LabeledFile) -> Bool { lhs.id == rhs.id }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/Training/CorpusManagerView.swift Ilumionate/Training/LabeledFile.swift
git commit -m "feat: add CorpusManagerView for training corpus management"
```

---

## Task 8: Phase Labeling View (Labeling UI — Screen 2)

**Files:**
- Create: `Ilumionate/Training/PhaseLabelingView.swift`

This is the most complex UI: audio playback + quick-label mode + refine mode with draggable boundaries.

- [ ] **Step 1: Create PhaseLabelingView**

Create `Ilumionate/Training/PhaseLabelingView.swift`. This view has two modes:

**Quick-label mode:**
- AVAudioPlayer for audio playback (play/pause, scrubber)
- Current time display
- Row of 7 phase buttons — tap to mark a phase transition at current playback time
- Content type picker
- Frequency band presets

**Refine mode:**
- Timeline view with colored phase blocks
- Drag handles on phase boundaries
- Tap phase block to edit type/notes
- Technique annotation add/remove

The view should use `@State` for the `LabeledFile` being edited, `AVAudioPlayer` for playback, and a `Timer`-based (async Task) position tracker.

```swift
//
//  PhaseLabelingView.swift
//  Ilumionate
//
//  Quick-label and refine UI for ground-truth phase annotation.
//

import SwiftUI
import AVFoundation

struct PhaseLabelingView: View {

    @State var file: LabeledFile
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var isRefineMode = false
    @State private var positionTask: Task<Void, Never>?
    @State private var editingPhase: LabeledFile.LabeledPhase?
    @State private var phaseNotes = ""

    @Environment(\.dismiss) private var dismiss

    private let allPhases: [HypnosisMetadata.Phase] = [
        .preTalk, .induction, .deepening, .therapy,
        .suggestions, .conditioning, .emergence
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.content) {
                playerControls
                if isRefineMode {
                    refineTimeline
                    techniqueSection
                } else {
                    quickLabelButtons
                }
                metadataSection
                phaseList
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, TranceSpacing.tabBarClearance)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Label Phases")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button(isRefineMode ? "Quick Label" : "Refine") {
                        isRefineMode.toggle()
                    }
                    .foregroundStyle(Color.roseGold)

                    Button("Save") { saveFile() }
                        .bold()
                        .foregroundStyle(Color.roseGold)
                }
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { cleanup() }
        .alert("Phase Notes", isPresented: Binding(
            get: { editingPhase != nil },
            set: { if !$0 { editingPhase = nil } }
        )) {
            TextField("Notes", text: $phaseNotes)
            Button("Save") {
                if let editing = editingPhase,
                   let idx = file.phases.firstIndex(where: { $0.id == editing.id }) {
                    file.phases[idx].notes = phaseNotes
                }
                editingPhase = nil
            }
            Button("Cancel", role: .cancel) { editingPhase = nil }
        }
    }

    // MARK: - Player Controls

    private var playerControls: some View {
        GlassCard {
            VStack(spacing: TranceSpacing.list) {
                // Time display
                HStack {
                    Text(formatTime(currentTime))
                        .monospacedDigit()
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(formatTime(file.audioDuration))
                        .monospacedDigit()
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                // Scrubber
                Slider(value: $currentTime, in: 0...max(file.audioDuration, 1)) { editing in
                    if !editing {
                        player?.currentTime = currentTime
                    }
                }
                .tint(.roseGold)

                // Play/Pause
                HStack(spacing: TranceSpacing.card) {
                    Button("Rewind 10s", systemImage: "gobackward.10") {
                        seekRelative(-10)
                    }
                    .foregroundStyle(Color.textSecondary)

                    Button(isPlaying ? "Pause" : "Play",
                           systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill") {
                        togglePlayback()
                    }
                    .font(.system(size: 44))
                    .foregroundStyle(Color.roseGold)

                    Button("Forward 10s", systemImage: "goforward.10") {
                        seekRelative(10)
                    }
                    .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // MARK: - Quick Label Buttons

    private var quickLabelButtons: some View {
        GlassCard(label: "Tap to Mark Phase Start") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: TranceSpacing.inner) {
                ForEach(allPhases, id: \.self) { phase in
                    Button {
                        markPhaseStart(phase)
                        TranceHaptics.shared.medium()
                    } label: {
                        Text(phase.displayName)
                            .font(TranceTypography.caption)
                            .bold()
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, TranceSpacing.list)
                            .background(phaseColor(phase))
                            .clipShape(.rect(cornerRadius: TranceRadius.button))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Refine Timeline

    private var refineTimeline: some View {
        GlassCard(label: "Drag Boundaries to Refine") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                // Phase blocks as colored rectangles
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        ForEach(file.phases) { phase in
                            let startFraction = phase.startTime / max(file.audioDuration, 1)
                            let widthFraction = (phase.endTime - phase.startTime) / max(file.audioDuration, 1)

                            Rectangle()
                                .fill(phaseColor(phase.phase).opacity(0.7))
                                .frame(width: geo.size.width * widthFraction)
                                .offset(x: geo.size.width * startFraction)
                                .overlay(alignment: .center) {
                                    Text(phase.phase.displayName)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                        }

                        // Playhead
                        let playheadX = (currentTime / max(file.audioDuration, 1)) * geo.size.width
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 2)
                            .offset(x: playheadX)
                    }
                }
                .frame(height: 40)
                .clipShape(.rect(cornerRadius: TranceRadius.tabItem))

                Text("Tap a phase in the list below to edit its boundaries and notes")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textLight)
            }
        }
    }

    // MARK: - Technique Section

    private var techniqueSection: some View {
        GlassCard(label: "Techniques") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                ForEach(file.techniques) { technique in
                    HStack {
                        Text(technique.name)
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(formatTime(technique.startTime))–\(formatTime(technique.endTime))")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .monospacedDigit()
                    }
                }

                Button("Add Technique", systemImage: "plus") {
                    let technique = LabeledFile.LabeledTechnique(
                        name: "New Technique",
                        startTime: currentTime,
                        endTime: min(currentTime + 60, file.audioDuration)
                    )
                    file.techniques.append(technique)
                }
                .foregroundStyle(Color.roseGold)
            }
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        GlassCard(label: "Metadata") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                // Content Type
                Picker("Content Type", selection: $file.expectedContentType) {
                    ForEach(AnalysisResult.ContentType.allCases, id: \.self) { type in
                        Text(type.rawValue.capitalized).tag(type)
                    }
                }

                // Frequency band presets
                HStack {
                    Text("Frequency Band")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Menu {
                        Button("Theta (0.5–10 Hz)") {
                            file.expectedFrequencyBand = .init(lower: 0.5, upper: 10.0)
                        }
                        Button("Alpha (8–12 Hz)") {
                            file.expectedFrequencyBand = .init(lower: 8.0, upper: 12.0)
                        }
                        Button("Low Alpha (6–8 Hz)") {
                            file.expectedFrequencyBand = .init(lower: 6.0, upper: 8.0)
                        }
                        Button("Upper Alpha (9–11 Hz)") {
                            file.expectedFrequencyBand = .init(lower: 9.0, upper: 11.0)
                        }
                    } label: {
                        Text("\(file.expectedFrequencyBand.lower, format: .number.precision(.fractionLength(1)))–\(file.expectedFrequencyBand.upper, format: .number.precision(.fractionLength(1))) Hz")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.roseGold)
                    }
                }

                // Notes
                TextField("Labeler notes...", text: $file.labelerNotes, axis: .vertical)
                    .font(TranceTypography.body)
                    .lineLimit(3...6)
            }
        }
    }

    // MARK: - Phase List

    private var phaseList: some View {
        GlassCard(label: "Phases (\(file.phases.count))") {
            if file.phases.isEmpty {
                Text("No phases marked yet. Play the audio and tap phase buttons above.")
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textLight)
            } else {
                ForEach(file.phases) { phase in
                    HStack(spacing: TranceSpacing.inner) {
                        Circle()
                            .fill(phaseColor(phase.phase))
                            .frame(width: 10, height: 10)

                        Text(phase.phase.displayName)
                            .font(TranceTypography.body)
                            .bold()
                            .foregroundStyle(Color.textPrimary)

                        Spacer()

                        Text("\(formatTime(phase.startTime))–\(formatTime(phase.endTime))")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .monospacedDigit()

                        Button("Edit", systemImage: "pencil") {
                            editingPhase = phase
                            phaseNotes = phase.notes ?? ""
                        }
                        .foregroundStyle(Color.roseGold)
                        .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func setupPlayer() {
        let url = TrainingCorpusManager.shared.audioURL(for: file)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
    }

    private func cleanup() {
        positionTask?.cancel()
        player?.stop()
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            positionTask?.cancel()
        } else {
            player.play()
            positionTask = Task { @MainActor in
                while !Task.isCancelled {
                    currentTime = player.currentTime
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        isPlaying.toggle()
    }

    private func seekRelative(_ seconds: TimeInterval) {
        guard let player else { return }
        let newTime = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = newTime
        currentTime = newTime
    }

    private func markPhaseStart(_ phase: HypnosisMetadata.Phase) {
        // End previous phase at current time
        if var last = file.phases.last {
            let idx = file.phases.count - 1
            file.phases[idx].endTime = currentTime
        }

        // Start new phase
        let newPhase = LabeledFile.LabeledPhase(
            phase: phase,
            startTime: currentTime,
            endTime: file.audioDuration // Default to end of file
        )
        file.phases.append(newPhase)
    }

    private func saveFile() {
        file.labeledAt = Date()
        try? TrainingCorpusManager.shared.save(file)
        TranceHaptics.shared.medium()
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m):\(s < 10 ? "0" : "")\(s)"
    }

    private func phaseColor(_ phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .preTalk:      return .bwAlpha
        case .induction:    return .phaseInduction
        case .deepening:    return .phaseDeepener
        case .therapy:      return .phaseSuggestion
        case .suggestions:  return .bwTheta
        case .conditioning: return .bwGamma
        case .emergence:    return .bwBeta
        case .transitional: return .textLight
        }
    }
}
```

- [ ] **Step 2: Add ContentType.allCases**

`AnalysisResult.ContentType` needs `CaseIterable` conformance for the Picker. In `AudioFile.swift`, add:

```swift
enum ContentType: String, Codable, Sendable, CaseIterable {
```

- [ ] **Step 3: Wire into Settings**

Add a navigation link in the app's Settings or developer section to access `CorpusManagerView`. This should be behind a developer toggle. Find the appropriate settings view and add:

```swift
NavigationLink("Analyzer Training", destination: CorpusManagerView())
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/Training/PhaseLabelingView.swift Ilumionate/AudioFile.swift
git commit -m "feat: add PhaseLabelingView with quick-label and refine modes"
```

---

## Task 9: FitnessEvaluator (Extended Scoring)

**Files:**
- Create: `IlumionateTests/Training/FitnessEvaluator.swift`
- Modify: `IlumionateTests/AnalysisEvaluationMetrics.swift`

- [ ] **Step 1: Add phaseBoundaryScore to AnalysisQualityScore**

In `IlumionateTests/AnalysisEvaluationMetrics.swift`, add the new field:

```swift
struct AnalysisQualityScore: Sendable {
    let contentTypeCorrect: Bool
    let phasePresenceScore: Double
    let phaseOrderScore: Double
    let frequencyRangeScore: Double
    let sessionValidityScore: Double
    let phaseBoundaryScore: Double  // NEW

    var overallScore: Double {
        (phasePresenceScore + phaseOrderScore + frequencyRangeScore + sessionValidityScore + phaseBoundaryScore) / 5.0
    }
}
```

Update the `AnalysisEvaluator.score()` method to compute and pass `phaseBoundaryScore`. Since `EvaluationCase` doesn't have boundary times, default to 1.0 for existing tests.

- [ ] **Step 2: Create FitnessEvaluator**

Create `IlumionateTests/Training/FitnessEvaluator.swift`:

```swift
//
//  FitnessEvaluator.swift
//  IlumionateTests
//
//  Extended scoring with phase boundary accuracy for the evolutionary pipeline.
//

import Foundation
@testable import Ilumionate

struct FitnessEvaluator {

    /// Tolerance in seconds for phase boundary matching.
    var boundaryToleranceSeconds: Double = 30.0

    /// Weighted fitness function per the spec.
    func fitness(
        labeledFile: LabeledFile,
        result: AnalysisResult,
        session: LightSession
    ) -> Double {
        let contentTypeScore: Double = result.contentType == labeledFile.expectedContentType ? 1.0 : 0.0
        let boundaryScore = scorePhaseBoundaries(labeledFile: labeledFile, result: result)
        let presenceScore = scorePhasePresence(labeledFile: labeledFile, result: result)
        let orderScore = scorePhaseOrder(result: result)
        let frequencyScore = scoreFrequencyRange(labeledFile: labeledFile, result: result)
        let sessionScore = scoreSessionValidity(session: session)

        return (0.25 * contentTypeScore)
             + (0.25 * boundaryScore)
             + (0.20 * presenceScore)
             + (0.10 * orderScore)
             + (0.10 * frequencyScore)
             + (0.10 * sessionScore)
    }

    // MARK: - Phase Boundary Score

    /// For each truth boundary, find the nearest detected boundary.
    /// Score = 1.0 - (avgErrorSeconds / toleranceSeconds), clamped to 0.
    func scorePhaseBoundaries(labeledFile: LabeledFile, result: AnalysisResult) -> Double {
        guard let meta = result.hypnosisMetadata, !meta.phases.isEmpty else {
            return labeledFile.phases.isEmpty ? 1.0 : 0.0
        }

        let truthBoundaries = labeledFile.phases.map(\.startTime) + [labeledFile.phases.last?.endTime ?? labeledFile.audioDuration]
        let detectedBoundaries = meta.phases.map(\.startTime) + [meta.phases.last?.endTime ?? 0]

        guard !truthBoundaries.isEmpty else { return 1.0 }

        var totalError: Double = 0
        for truth in truthBoundaries {
            let nearest = detectedBoundaries.min(by: { abs($0 - truth) < abs($1 - truth) }) ?? 0
            totalError += abs(nearest - truth)
        }

        let avgError = totalError / Double(truthBoundaries.count)
        return max(0, 1.0 - (avgError / boundaryToleranceSeconds))
    }

    // MARK: - Phase Presence

    func scorePhasePresence(labeledFile: LabeledFile, result: AnalysisResult) -> Double {
        guard !labeledFile.phases.isEmpty else { return 1.0 }
        guard let meta = result.hypnosisMetadata else { return 0.0 }
        let detected = Set(meta.phases.map(\.phase))
        let expected = Set(labeledFile.phases.map(\.phase))
        let hits = expected.intersection(detected).count
        return Double(hits) / Double(expected.count)
    }

    // MARK: - Phase Order

    private static let canonicalOrder: [HypnosisMetadata.Phase] = [
        .preTalk, .induction, .deepening, .therapy,
        .suggestions, .conditioning, .emergence
    ]

    func scorePhaseOrder(result: AnalysisResult) -> Double {
        guard let meta = result.hypnosisMetadata, !meta.phases.isEmpty else { return 1.0 }
        let detected = meta.phases.map(\.phase)
        var lastIndex = -1
        for phase in detected {
            if let idx = Self.canonicalOrder.firstIndex(of: phase) {
                if idx < lastIndex { return 0.0 }
                lastIndex = idx
            }
        }
        return 1.0
    }

    // MARK: - Frequency Range

    func scoreFrequencyRange(labeledFile: LabeledFile, result: AnalysisResult) -> Double {
        let detected = result.suggestedFrequencyRange
        let expected = labeledFile.expectedFrequencyBand.closedRange
        let overlaps = detected.lowerBound <= expected.upperBound && expected.lowerBound <= detected.upperBound
        return overlaps ? 1.0 : 0.0
    }

    // MARK: - Session Validity

    func scoreSessionValidity(session: LightSession) -> Double {
        guard !session.light_score.isEmpty else { return 0.0 }
        let validFreq = session.light_score.allSatisfy { $0.frequency >= 0.5 && $0.frequency <= 40.0 }
        let validAmp = session.light_score.allSatisfy { $0.intensity >= 0.0 && $0.intensity <= 1.0 }
        let sorted = session.light_score.map(\.time) == session.light_score.map(\.time).sorted()
        return (validFreq && validAmp && sorted) ? 1.0 : 0.0
    }
}
```

- [ ] **Step 3: Build test target**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build-for-testing -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 4: Commit**

```bash
git add IlumionateTests/Training/FitnessEvaluator.swift IlumionateTests/AnalysisEvaluationMetrics.swift
git commit -m "feat: add FitnessEvaluator with phase boundary scoring"
```

---

## Task 10: Mutation Operators

**Files:**
- Create: `IlumionateTests/Training/MutationOperators.swift`

- [ ] **Step 1: Create MutationOperators**

Create `IlumionateTests/Training/MutationOperators.swift`:

```swift
//
//  MutationOperators.swift
//  IlumionateTests
//
//  Per-parameter-type mutation strategies for the evolutionary optimizer.
//

import Foundation
@testable import Ilumionate

struct MutationOperators {

    /// Gaussian perturbation: multiply value by (1 + N(0, sigma)).
    static func perturbDouble(_ value: Double, sigma: Double) -> Double {
        let noise = gaussianRandom() * sigma
        return value * (1.0 + noise)
    }

    /// Integer perturbation: add random from [-delta, delta].
    static func perturbInt(_ value: Int, delta: Int) -> Int {
        value + Int.random(in: -delta...delta)
    }

    /// Shift a frequency band boundary by up to ±maxShift Hz.
    static func perturbFrequencyBand(
        _ band: AnalyzerConfig.SessionGeneration.FrequencyBand,
        maxShift: Double = 1.0
    ) -> AnalyzerConfig.SessionGeneration.FrequencyBand {
        let newLower = max(0.5, band.lower + Double.random(in: -maxShift...maxShift))
        let newUpper = max(newLower + 0.5, band.upper + Double.random(in: -maxShift...maxShift))
        return .init(lower: newLower, upper: newUpper)
    }

    // MARK: - Keyword Weight Mutation

    /// Perturb all keyword weights by ±20%.
    static func mutateKeywordWeights(
        _ weights: [String: [String: Double]]
    ) -> [String: [String: Double]] {
        var result = weights
        for (phase, keywords) in weights {
            var mutated = keywords
            for (keyword, weight) in keywords {
                mutated[keyword] = max(0.1, perturbDouble(weight, sigma: 0.20))
            }
            result[phase] = mutated
        }
        return result
    }

    // MARK: - Section Mutators

    static func mutateKeywordPipeline(
        _ pipeline: AnalyzerConfig.KeywordPipeline
    ) -> AnalyzerConfig.KeywordPipeline {
        var p = pipeline
        p.weights = mutateKeywordWeights(p.weights)
        p.contextWindowSeconds = max(1, perturbInt(p.contextWindowSeconds, delta: 2))
        p.smoothingWindowSize = max(1, perturbInt(p.smoothingWindowSize, delta: 2))
        p.minimumPhaseDurationSeconds = max(10, perturbInt(p.minimumPhaseDurationSeconds, delta: 10))
        p.collapseThresholdFraction = max(0.01, perturbDouble(p.collapseThresholdFraction, sigma: 0.30))
        return p
    }

    static func mutateChunkedAnalyzer(
        _ chunked: AnalyzerConfig.ChunkedAnalyzer,
        labeledCorpus: [LabeledFile]
    ) -> AnalyzerConfig.ChunkedAnalyzer {
        var c = chunked
        c.chunkDurationSeconds = max(5.0, perturbDouble(c.chunkDurationSeconds, sigma: 0.30))
        c.chunkOverlapSeconds = max(1.0, perturbDouble(c.chunkOverlapSeconds, sigma: 0.30))
        c.minChunks = max(2, perturbInt(c.minChunks, delta: 2))
        c.maxChunks = max(c.minChunks + 1, perturbInt(c.maxChunks, delta: 5))

        // Few-shot mutation: add/remove/replace from labeled corpus
        if !labeledCorpus.isEmpty && Bool.random() {
            c.fewShotExamples = generateFewShotExamples(from: labeledCorpus, count: Int.random(in: 1...3))
        }

        return c
    }

    static func mutateProsody(
        _ prosody: AnalyzerConfig.Prosody
    ) -> AnalyzerConfig.Prosody {
        var p = prosody
        p.speechRateWindowSeconds = max(1.0, perturbDouble(p.speechRateWindowSeconds, sigma: 0.30))
        p.pauseThresholdSeconds = max(0.3, perturbDouble(p.pauseThresholdSeconds, sigma: 0.30))
        p.deliberatePauseMinSeconds = max(1.0, perturbDouble(p.deliberatePauseMinSeconds, sigma: 0.30))
        p.musicOnlyPauseMinSeconds = max(2.0, perturbDouble(p.musicOnlyPauseMinSeconds, sigma: 0.30))
        return p
    }

    static func mutateTechniqueDetection(
        _ td: AnalyzerConfig.TechniqueDetection
    ) -> AnalyzerConfig.TechniqueDetection {
        var t = td
        t.sensitivityThreshold = max(0.1, min(1.0, perturbDouble(t.sensitivityThreshold, sigma: 0.15)))
        t.minConfidence = max(0.1, min(1.0, perturbDouble(t.minConfidence, sigma: 0.15)))
        return t
    }

    static func mutateSessionGeneration(
        _ sg: AnalyzerConfig.SessionGeneration
    ) -> AnalyzerConfig.SessionGeneration {
        var s = sg
        for (key, band) in s.frequencyBands {
            s.frequencyBands[key] = perturbFrequencyBand(band)
        }
        s.transitionSmoothingSeconds = max(1.0, perturbDouble(s.transitionSmoothingSeconds, sigma: 0.30))
        return s
    }

    // MARK: - Full Config Mutation

    static func mutate(
        _ config: AnalyzerConfig,
        labeledCorpus: [LabeledFile]
    ) -> AnalyzerConfig {
        var c = config
        c.keywordPipeline = mutateKeywordPipeline(c.keywordPipeline)
        c.chunkedAnalyzer = mutateChunkedAnalyzer(c.chunkedAnalyzer, labeledCorpus: labeledCorpus)
        c.prosody = mutateProsody(c.prosody)
        c.techniqueDetection = mutateTechniqueDetection(c.techniqueDetection)
        c.sessionGeneration = mutateSessionGeneration(c.sessionGeneration)
        return c
    }

    // MARK: - Crossover

    /// Section-level crossover: each section randomly picked from one parent.
    static func crossover(_ a: AnalyzerConfig, _ b: AnalyzerConfig) -> AnalyzerConfig {
        var child = a
        child.keywordPipeline = Bool.random() ? a.keywordPipeline : b.keywordPipeline
        child.chunkedAnalyzer = Bool.random() ? a.chunkedAnalyzer : b.chunkedAnalyzer
        child.prosody = Bool.random() ? a.prosody : b.prosody
        child.techniqueDetection = Bool.random() ? a.techniqueDetection : b.techniqueDetection
        child.sessionGeneration = Bool.random() ? a.sessionGeneration : b.sessionGeneration
        return child
    }

    // MARK: - Few-Shot Generation

    static func generateFewShotExamples(
        from corpus: [LabeledFile],
        count: Int
    ) -> [AnalyzerConfig.ChunkedAnalyzer.FewShotExample] {
        var examples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample] = []
        for _ in 0..<count {
            guard let file = corpus.randomElement(),
                  let phase = file.phases.randomElement() else { continue }
            let position = phase.startTime / max(file.audioDuration, 1)
            examples.append(.init(
                text: "[\(phase.phase.displayName) segment at \(Int(position * 100))%]",
                position: position,
                correctPhase: phase.phase.rawValue
            ))
        }
        return examples
    }

    // MARK: - Gaussian Random

    /// Box-Muller transform for normal distribution.
    private static func gaussianRandom() -> Double {
        let u1 = Double.random(in: Double.ulpOfOne...1.0)
        let u2 = Double.random(in: 0.0...1.0)
        return (-2.0 * log(u1)).squareRoot() * cos(2.0 * .pi * u2)
    }
}
```

- [ ] **Step 2: Build test target**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build-for-testing -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add IlumionateTests/Training/MutationOperators.swift
git commit -m "feat: add MutationOperators for evolutionary config optimization"
```

---

## Task 11: Evolutionary Optimizer

**Files:**
- Create: `IlumionateTests/Training/EvolutionaryOptimizer.swift`

- [ ] **Step 1: Create EvolutionaryOptimizer**

Create `IlumionateTests/Training/EvolutionaryOptimizer.swift`:

```swift
//
//  EvolutionaryOptimizer.swift
//  IlumionateTests
//
//  Population management, selection, and generational evolution.
//

import Foundation
@testable import Ilumionate

struct EvolutionaryOptimizer {

    struct Parameters {
        var populationSize: Int = 10
        var maxGenerations: Int = 20
        var elitismCount: Int = 3
        var mutationRate: Double = 0.8
        var earlyStopPatience: Int = 5
    }

    struct GenerationResult {
        let generation: Int
        let bestFitness: Double
        let averageFitness: Double
        let bestConfig: AnalyzerConfig
    }

    let params: Parameters
    let labeledCorpus: [LabeledFile]

    /// Evaluates a single config against the entire labeled corpus.
    /// Uses keyword pipeline only (fast) — Foundation Models evaluation
    /// is handled separately in PipelineRunner when the flag is set.
    func evaluateConfig(
        _ config: AnalyzerConfig
    ) -> Double {
        let keywordAnalyzer = HypnosisPhaseAnalyzer(config: config.keywordPipeline)
        let sessionGenerator = SessionGenerator(config: config.sessionGeneration)
        let fitnessEvaluator = FitnessEvaluator()

        var totalFitness: Double = 0

        for labeledFile in labeledCorpus {
            // Build a synthetic transcription from the labeled file
            // (In production, cached WhisperKit transcriptions would be used)
            let audioFile = AudioFile(
                filename: labeledFile.audioFilename,
                duration: labeledFile.audioDuration,
                fileSize: 0
            )

            // Run keyword analyzer
            let phases = keywordAnalyzer.analyze(
                segments: [], // Empty segments for keyword-only eval
                duration: labeledFile.audioDuration
            )

            // Build analysis result
            let metadata = HypnosisMetadata(
                phases: phases,
                inductionStyle: .permissive,
                estimatedTranceDeph: .medium,
                suggestionDensity: nil,
                languagePatterns: [],
                detectedTechniques: []
            )

            let result = AnalysisResult(
                mood: .meditative,
                energyLevel: 0.3,
                suggestedFrequencyRange: config.sessionGeneration.band(for: labeledFile.expectedContentType).closedRange,
                suggestedIntensity: 0.5,
                keyMoments: [],
                aiSummary: "",
                recommendedPreset: "",
                contentType: labeledFile.expectedContentType,
                hypnosisMetadata: metadata
            )

            let session = sessionGenerator.generateSession(from: audioFile, analysis: result)
            totalFitness += fitnessEvaluator.fitness(labeledFile: labeledFile, result: result, session: session)
        }

        return labeledCorpus.isEmpty ? 0 : totalFitness / Double(labeledCorpus.count)
    }

    /// Runs the full evolutionary loop and returns generation history.
    func run(
        seed: AnalyzerConfig,
        onGeneration: ((GenerationResult) -> Void)? = nil
    ) -> (bestConfig: AnalyzerConfig, history: [GenerationResult]) {
        // Seed population
        var population: [(config: AnalyzerConfig, fitness: Double)] = []
        population.append((seed, evaluateConfig(seed)))

        for _ in 1..<params.populationSize {
            let mutated = MutationOperators.mutate(seed, labeledCorpus: labeledCorpus)
            population.append((mutated, evaluateConfig(mutated)))
        }

        var history: [GenerationResult] = []
        var bestEverFitness: Double = 0
        var bestEverConfig = seed
        var stagnantGenerations = 0

        for gen in 0..<params.maxGenerations {
            // Sort by fitness descending
            population.sort { $0.fitness > $1.fitness }

            let bestFitness = population[0].fitness
            let avgFitness = population.map(\.fitness).reduce(0, +) / Double(population.count)

            var bestConfig = population[0].config
            bestConfig.generation = gen
            bestConfig.fitness = bestFitness

            let result = GenerationResult(
                generation: gen,
                bestFitness: bestFitness,
                averageFitness: avgFitness,
                bestConfig: bestConfig
            )
            history.append(result)
            onGeneration?(result)

            print("📊 Gen \(gen): best=\(bestFitness.formatted(.number.precision(.fractionLength(4)))), avg=\(avgFitness.formatted(.number.precision(.fractionLength(4))))")

            // Track best ever
            if bestFitness > bestEverFitness {
                bestEverFitness = bestFitness
                bestEverConfig = bestConfig
                stagnantGenerations = 0
            } else {
                stagnantGenerations += 1
            }

            // Early stopping
            if stagnantGenerations >= params.earlyStopPatience {
                print("🛑 Early stop: no improvement for \(params.earlyStopPatience) generations")
                break
            }

            // Selection: keep top elitismCount
            let elites = Array(population.prefix(params.elitismCount))

            // Generate children
            var nextGen = elites
            while nextGen.count < params.populationSize {
                let parent: AnalyzerConfig
                if nextGen.count < params.elitismCount + 2 && population.count >= 2 {
                    // Crossover from top 2
                    parent = MutationOperators.crossover(population[0].config, population[1].config)
                } else {
                    // Select random elite as parent
                    parent = elites.randomElement()!.config
                }

                let child: AnalyzerConfig
                if Double.random(in: 0...1) < params.mutationRate {
                    child = MutationOperators.mutate(parent, labeledCorpus: labeledCorpus)
                } else {
                    child = parent
                }

                nextGen.append((child, evaluateConfig(child)))
            }

            population = nextGen
        }

        return (bestEverConfig, history)
    }
}
```

- [ ] **Step 2: Build test target**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build-for-testing -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add IlumionateTests/Training/EvolutionaryOptimizer.swift
git commit -m "feat: add EvolutionaryOptimizer with selection, mutation, crossover"
```

---

## Task 12: Pipeline Runner + Evaluation Report

**Files:**
- Create: `IlumionateTests/Training/PipelineRunner.swift`

- [ ] **Step 1: Create EvaluationReport model and PipelineRunner**

Create `IlumionateTests/Training/PipelineRunner.swift`:

```swift
//
//  PipelineRunner.swift
//  IlumionateTests
//
//  Orchestrates generations, caching, and report output.
//

import Foundation
@testable import Ilumionate

// MARK: - Evaluation Report

struct EvaluationReport: Codable {
    let generatedAt: Date
    let totalGenerations: Int
    let bestFitness: Double
    let fitnessHistory: [GenerationSnapshot]
    let perFileScores: [FileScore]

    struct GenerationSnapshot: Codable {
        let generation: Int
        let bestFitness: Double
        let averageFitness: Double
    }

    struct FileScore: Codable {
        let filename: String
        let fitness: Double
        let contentTypeCorrect: Bool
        let phaseBoundaryScore: Double
        let phasePresenceScore: Double
    }
}

// MARK: - Pipeline Runner

struct PipelineRunner {

    let corpusDirectory: URL
    let outputDirectory: URL

    init(
        corpusDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus"),
        outputDirectory: URL = URL.documentsDirectory.appending(path: "TrainingOutput")
    ) {
        self.corpusDirectory = corpusDirectory
        self.outputDirectory = outputDirectory
    }

    /// Loads the labeled corpus from disk.
    func loadCorpus() -> [LabeledFile] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: corpusDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(LabeledFile.self, from: data)
            }
    }

    /// Runs the full improvement pipeline.
    func run(
        params: EvolutionaryOptimizer.Parameters = .init()
    ) -> (config: AnalyzerConfig, report: EvaluationReport) {
        let corpus = loadCorpus()
        print("📂 Loaded \(corpus.count) labeled file(s)")

        let seedConfig = AnalyzerConfigLoader.load()
        let optimizer = EvolutionaryOptimizer(params: params, labeledCorpus: corpus)

        let (bestConfig, history) = optimizer.run(seed: seedConfig) { gen in
            print("  Gen \(gen.generation): fitness \(gen.bestFitness)")
        }

        // Build per-file score breakdown
        let fitnessEvaluator = FitnessEvaluator()
        let keywordAnalyzer = HypnosisPhaseAnalyzer(config: bestConfig.keywordPipeline)
        let sessionGenerator = SessionGenerator(config: bestConfig.sessionGeneration)

        var perFileScores: [EvaluationReport.FileScore] = []
        for labeledFile in corpus {
            let audioFile = AudioFile(
                filename: labeledFile.audioFilename,
                duration: labeledFile.audioDuration,
                fileSize: 0
            )
            let phases = keywordAnalyzer.analyze(segments: [], duration: labeledFile.audioDuration)
            let metadata = HypnosisMetadata(
                phases: phases,
                inductionStyle: .permissive,
                estimatedTranceDeph: .medium,
                suggestionDensity: nil,
                languagePatterns: [],
                detectedTechniques: []
            )
            let result = AnalysisResult(
                mood: .meditative,
                energyLevel: 0.3,
                suggestedFrequencyRange: bestConfig.sessionGeneration.band(for: labeledFile.expectedContentType).closedRange,
                suggestedIntensity: 0.5,
                keyMoments: [],
                aiSummary: "",
                recommendedPreset: "",
                contentType: labeledFile.expectedContentType,
                hypnosisMetadata: metadata
            )
            let session = sessionGenerator.generateSession(from: audioFile, analysis: result)
            let fitness = fitnessEvaluator.fitness(labeledFile: labeledFile, result: result, session: session)

            perFileScores.append(.init(
                filename: labeledFile.audioFilename,
                fitness: fitness,
                contentTypeCorrect: result.contentType == labeledFile.expectedContentType,
                phaseBoundaryScore: fitnessEvaluator.scorePhaseBoundaries(labeledFile: labeledFile, result: result),
                phasePresenceScore: fitnessEvaluator.scorePhasePresence(labeledFile: labeledFile, result: result)
            ))
        }

        let report = EvaluationReport(
            generatedAt: Date(),
            totalGenerations: history.count,
            bestFitness: bestConfig.fitness,
            fitnessHistory: history.map { .init(generation: $0.generation, bestFitness: $0.bestFitness, averageFitness: $0.averageFitness) },
            perFileScores: perFileScores
        )

        // Write outputs
        writeOutputs(config: bestConfig, report: report)

        return (bestConfig, report)
    }

    private func writeOutputs(config: AnalyzerConfig, report: EvaluationReport) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: outputDirectory.path()) {
            try? fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        // Config
        if let data = try? encoder.encode(config) {
            let url = outputDirectory.appending(path: "AnalyzerConfig_gen\(config.generation).json")
            try? data.write(to: url, options: .atomic)
            print("💾 Wrote config: \(url.lastPathComponent)")
        }

        // Report
        if let data = try? encoder.encode(report) {
            let url = outputDirectory.appending(path: "EvaluationReport_gen\(config.generation).json")
            try? data.write(to: url, options: .atomic)
            print("📊 Wrote report: \(url.lastPathComponent)")
        }

        // Also write as the active config
        try? AnalyzerConfigLoader.save(config)
        print("✅ Pipeline complete. Best fitness: \(config.fitness)")
    }
}
```

- [ ] **Step 2: Build test target**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build-for-testing -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E "error:|BUILD"
```

- [ ] **Step 3: Commit**

```bash
git add IlumionateTests/Training/PipelineRunner.swift
git commit -m "feat: add PipelineRunner with evaluation report output"
```

---

## Task 13: Pipeline Entry Point Test

**Files:**
- Create: `IlumionateTests/Training/EvolutionaryPipelineTests.swift`

- [ ] **Step 1: Create the test entry point**

Create `IlumionateTests/Training/EvolutionaryPipelineTests.swift`:

```swift
//
//  EvolutionaryPipelineTests.swift
//  IlumionateTests
//
//  Entry point to run the evolutionary improvement pipeline.
//  Run with: xcodebuild test -only-testing:IlumionateTests/EvolutionaryPipelineTests
//

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct EvolutionaryPipelineTests {

    /// Smoke test: runs 2 generations with population 4 to verify the pipeline works.
    @Test func pipelineSmokeTest() {
        let runner = PipelineRunner()
        let (config, report) = runner.run(
            params: .init(populationSize: 4, maxGenerations: 2, elitismCount: 1, earlyStopPatience: 2)
        )

        #expect(config.generation >= 0, "Config should have a generation number")
        #expect(report.totalGenerations > 0, "Report should contain at least one generation")
        #expect(report.fitnessHistory.count > 0, "Fitness history should not be empty")
        print("✅ Smoke test passed. Best fitness: \(config.fitness)")
    }

    /// Full pipeline run — use this to actually improve the analyzer.
    /// Tagged so it doesn't run in CI (takes minutes).
    @Test(.disabled("Run manually for actual training"))
    func fullPipelineRun() {
        let runner = PipelineRunner()
        let (config, report) = runner.run(
            params: .init(populationSize: 10, maxGenerations: 20, elitismCount: 3, earlyStopPatience: 5)
        )

        print("🏆 Full run complete:")
        print("   Best fitness: \(config.fitness)")
        print("   Generations: \(report.totalGenerations)")
        for fileScore in report.perFileScores {
            print("   \(fileScore.filename): \(fileScore.fitness)")
        }
    }

    /// Verify mutation produces different configs.
    @Test func mutationProducesDiversity() {
        let seed = AnalyzerConfigLoader.load()
        let mutated = MutationOperators.mutate(seed, labeledCorpus: [])

        // At least one keyword weight should differ
        let seedWeights = seed.keywordPipeline.weights
        let mutatedWeights = mutated.keywordPipeline.weights
        var hasDifference = false
        for (phase, keywords) in seedWeights {
            for (keyword, weight) in keywords {
                if mutatedWeights[phase]?[keyword] != weight {
                    hasDifference = true
                    break
                }
            }
            if hasDifference { break }
        }
        #expect(hasDifference, "Mutation should produce at least one different value")
    }

    /// Verify crossover mixes sections from two parents.
    @Test func crossoverMixesSections() {
        let parentA = AnalyzerConfigLoader.load()
        var parentB = parentA
        parentB.keywordPipeline.contextWindowSeconds = 99
        parentB.prosody.speechRateWindowSeconds = 99.0

        // Run crossover multiple times — at least once should mix
        var sawMix = false
        for _ in 0..<20 {
            let child = MutationOperators.crossover(parentA, parentB)
            let hasAKeyword = child.keywordPipeline.contextWindowSeconds != 99
            let hasBProsody = child.prosody.speechRateWindowSeconds == 99.0
            if hasAKeyword && hasBProsody {
                sawMix = true
                break
            }
        }
        #expect(sawMix, "Crossover should eventually mix sections from different parents")
    }
}
```

- [ ] **Step 2: Run the smoke test**

```bash
xcodebuild test -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/EvolutionaryPipelineTests/pipelineSmokeTest 2>&1 | tail -20
```

- [ ] **Step 3: Commit**

```bash
git add IlumionateTests/Training/EvolutionaryPipelineTests.swift
git commit -m "feat: add EvolutionaryPipelineTests as pipeline entry point"
```

---

## Task 14: Update Existing Tests for Config Compatibility

**Files:**
- Modify: `IlumionateTests/EvaluationHarnessTests.swift`

- [ ] **Step 1: Update test code to pass config where needed**

The refactored analyzers now accept config at init. Existing tests that create `HypnosisPhaseAnalyzer()` or `SessionGenerator()` still work because of the `nil` defaults, but verify they compile and pass:

```bash
xcodebuild test -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/KeywordPipelineEvaluationTests 2>&1 | tail -20
```

If any tests fail due to the `phaseBoundaryScore` change in `AnalysisQualityScore`, update the `buildAnalysisResult` helper to pass the new field.

- [ ] **Step 2: Commit if changes were needed**

```bash
git add IlumionateTests/
git commit -m "fix: update existing tests for AnalyzerConfig compatibility"
```

---

## Task 15: Final Integration Build + Verification

- [ ] **Step 1: Full clean build**

```bash
xcodebuild -project Ilumionate.xcodeproj clean && xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 2: Run all tests**

```bash
xcodebuild test -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30
```

Expected: All tests pass.

- [ ] **Step 3: Commit any final fixes**

```bash
git add -A && git commit -m "feat: analyzer improvement pipeline — complete implementation"
```
