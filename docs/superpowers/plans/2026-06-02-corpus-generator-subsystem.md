# Corpus Generator Subsystem (Tracer Bullet) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dev-time SwiftPM CLI (`corpus-gen`) that authors synthetic hypnosis-session transcripts one phase block at a time and emits schema-valid `CorpusCase` JSON the existing evaluation harness loads and scores — proving the whole pipe end to end.

**Architecture:** Extract the on-disk corpus schema and the `TrancePhase` enum into a new platform-agnostic SwiftPM library `CorpusKit` (single source of truth, no drift). A second library `CorpusGenKit` holds the generator logic (phase plans, block responder, session assembler, seed library, Claude request builder); a thin `corpus-gen` executable wires them. The iOS app, test target, and LumeLabel link `CorpusKit` via `@_exported import`. The Anthropic Messages API is reached through a `BlockResponder` protocol so offline `--dry-run` and unit tests use a deterministic stub with no network or API key.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`), Foundation (`URLSession`). New package at `Tools/CorpusGenerator/`. Existing Xcode project `Ilumionate.xcodeproj` (targets `Ilumionate`, `IlumionateTests`, `LumeLabel`).

**Spec:** `docs/superpowers/specs/2026-06-02-corpus-generator-subsystem-design.md`.

---

## File Structure

**New SwiftPM package — `Tools/CorpusGenerator/`:**

- `Package.swift` — declares products `CorpusKit` (lib), `corpus-gen` (exe) and targets `CorpusKit`, `CorpusGenKit`, `CorpusGenerator` (exe), `CorpusKitTests`, `CorpusGenKitTests`.
- `Sources/CorpusKit/TrancePhase.swift` — **moved** from `Ilumionate/TrancePhase.swift`; made `public`.
- `Sources/CorpusKit/CorpusModels.swift` — **moved/rewritten** pure DTOs (`CorpusSource`, `CorpusBoundaryMode`, `CorpusAmbiguityLevel`, `CorpusSegment`, `PhaseTruthSpan`, `CorpusCase`, `GenerationParams`); content-type stored as raw `String`.
- `Sources/CorpusKit/CorpusLoader.swift` — **moved** from `IlumionateTests/Corpus/CorpusLoader.swift`; made `public`; repo-root resolution updated for the new file location.
- `Sources/CorpusGenKit/PhasePlan.swift` — phase-plan model + `classic` archetype with duration variation.
- `Sources/CorpusGenKit/BlockResponder.swift` — `BlockRequest`, `BlockResponder` protocol, `StubResponder` (keyword-rich per-phase canned text).
- `Sources/CorpusGenKit/SessionAssembler.swift` — assembles a plan into one `CorpusCase` with exact truth spans.
- `Sources/CorpusGenKit/SeedLibrary.swift` — parses real LumeLabel label+transcript files into per-phase `PhaseSeed`s.
- `Sources/CorpusGenKit/ClaudeClient.swift` — `ClaudeRequestBuilder` (pure, testable) + `ClaudeResponder` (`URLSession`, conforms to `BlockResponder`).
- `Sources/CorpusGenerator/CLIOptions.swift` — argv parsing.
- `Sources/CorpusGenerator/main.swift` — wires options → responder → plan → assembler → JSON files.
- `Tests/CorpusKitTests/CorpusCaseDecodingTests.swift` — schema decode/round-trip (no app dependency).
- `Tests/CorpusGenKitTests/{PhasePlanTests,SessionAssemblerTests,SeedLibraryTests,ClaudeRequestBuilderTests,CLIOptionsTests}.swift`.
- `Tests/CorpusGenKitTests/Fixtures/` — a trimmed real label + transcript pair for the seed test.

**Modified in the Xcode project (Task 2):**

- Delete: `Ilumionate/TrancePhase.swift`, `IlumionateTests/Corpus/CorpusCase.swift`, `IlumionateTests/Corpus/CorpusLoader.swift`, `IlumionateTests/Corpus/CorpusLoaderTests.swift` (its tests move to `CorpusKitTests`), `IlumionateTests/Corpus/CorpusCaseTests.swift` (likewise).
- Create: `IlumionateTests/Corpus/CorpusCaseAppBridge.swift` — test-target extension giving back `expectedContentType: AnalysisResult.ContentType?` and `transcriptionSegments: [AudioTranscriptionSegment]`.
- Create: `Ilumionate/CorpusKitReexport.swift`, `LumeLabel/CorpusKitReexport.swift` — one-line `@_exported import CorpusKit` per target.
- Keep unchanged: `IlumionateTests/Corpus/PhaseTimelineEvaluator.swift`, `…/PhaseTimelineEvaluatorTests.swift`, `IlumionateTests/EvaluationHarnessTests.swift` (they keep working via the re-export + bridge).

**Xcode integration note:** This project uses synchronized groups, so files added *inside* the existing synchronized folders (`Ilumionate/`, `IlumionateTests/`, `LumeLabel/`) are auto-included in their targets. The `Tools/CorpusGenerator/` package is **outside** those folders and is added as a **local package dependency** whose `CorpusKit` product is linked to the three targets (Task 2). If a build reports "cannot find type 'CorpusCase'/'TrancePhase' in scope," the package link or a `@_exported import` is missing — see Task 2 fallback.

---

## Task 1: Scaffold `CorpusKit` package (standalone, command-line verifiable)

This task touches **only** the new package directory and is verified entirely with `swift` on the command line — no Xcode. It does **not** delete the originals yet (that is Task 2), so the Xcode build stays green throughout Task 1.

**Files:**
- Create: `Tools/CorpusGenerator/Package.swift`
- Create: `Tools/CorpusGenerator/Sources/CorpusKit/TrancePhase.swift`
- Create: `Tools/CorpusGenerator/Sources/CorpusKit/CorpusModels.swift`
- Create: `Tools/CorpusGenerator/Sources/CorpusKit/CorpusLoader.swift`
- Create: `Tools/CorpusGenerator/Sources/CorpusGenKit/Placeholder.swift` (temporary, keeps the target non-empty)
- Create: `Tools/CorpusGenerator/Sources/CorpusGenerator/main.swift` (temporary stub)
- Test: `Tools/CorpusGenerator/Tests/CorpusKitTests/CorpusCaseDecodingTests.swift`

- [ ] **Step 1: Create the package manifest**

Create `Tools/CorpusGenerator/Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CorpusGenerator",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CorpusKit", targets: ["CorpusKit"]),
        .executable(name: "corpus-gen", targets: ["CorpusGenerator"]),
    ],
    targets: [
        .target(name: "CorpusKit"),
        .target(name: "CorpusGenKit", dependencies: ["CorpusKit"]),
        .executableTarget(name: "CorpusGenerator", dependencies: ["CorpusGenKit", "CorpusKit"]),
        .testTarget(name: "CorpusKitTests", dependencies: ["CorpusKit"]),
        .testTarget(name: "CorpusGenKitTests", dependencies: ["CorpusGenKit", "CorpusKit"]),
    ]
)
```

- [ ] **Step 2: Move `TrancePhase` into `CorpusKit` and make it public**

Copy `Ilumionate/TrancePhase.swift` to `Tools/CorpusGenerator/Sources/CorpusKit/TrancePhase.swift` and make the type and every member used cross-module `public`. Full file:

```swift
//  TrancePhase.swift
//  CorpusKit
//
//  Standalone phase enum shared by the iOS analysis pipeline, the LumeLabel
//  macOS labeling utility, the evaluation harness, and the corpus generator.
//  Single source of truth — lives in CorpusKit, imported everywhere else.
//
import Foundation

public enum TrancePhase: String, Codable, Sendable, CaseIterable {
    case preTalk = "pre_talk"
    case induction = "induction"
    case fractionation = "fractionation"
    case deepening = "deepening"
    case confusion = "confusion"
    case suggestions = "suggestions"
    case therapy = "therapeutic_work"
    case eroticSuggestions = "erotic_suggestions"
    case brainwashing = "brainwashing"
    case conditioning = "post_hypnotic_conditioning"
    case emergence = "emergence"

    case transitional // Used when phases blend

    public static let orderedHypnosisPhases: [TrancePhase] = [
        .preTalk, .induction, .fractionation, .deepening, .confusion,
        .therapy, .suggestions, .eroticSuggestions, .brainwashing,
        .conditioning, .emergence,
    ]

    public var displayName: String {
        switch self {
        case .preTalk: return "Pre-Talk"
        case .induction: return "Induction"
        case .fractionation: return "Fractionation"
        case .deepening: return "Deepening"
        case .confusion: return "Confusion"
        case .therapy: return "Therapeutic Work"
        case .suggestions: return "Suggestions"
        case .eroticSuggestions: return "Erotic Suggestions"
        case .brainwashing: return "Brainwashing"
        case .conditioning: return "Post-Hypnotic Conditioning"
        case .emergence: return "Emergence"
        case .transitional: return "Transitional"
        }
    }

    public var tranceDepthEstimate: Double {
        switch self {
        case .preTalk: return 0.05
        case .induction: return 0.22
        case .fractionation: return 0.42
        case .deepening: return 0.62
        case .confusion: return 0.74
        case .therapy: return 0.84
        case .suggestions: return 0.72
        case .eroticSuggestions: return 0.78
        case .brainwashing: return 0.82
        case .conditioning: return 0.58
        case .emergence: return 0.24
        case .transitional: return 0.40
        }
    }
}
```

> The original `TrancePhase.swift` declared the enum `nonisolated`. A `public enum` with only value members has no actor isolation to begin with, so the `nonisolated` keyword is dropped. This is behavior-preserving.

- [ ] **Step 3: Create the pure corpus DTOs**

Create `Tools/CorpusGenerator/Sources/CorpusKit/CorpusModels.swift`. This is the landed `CorpusCase` with two changes: everything is `public`, and `expectedContentType` is stored as a raw `String` (`expectedContentTypeRaw`) so the module has **zero** app dependencies. A new optional `GenerationParams` records provenance (spec §3d).

```swift
//  CorpusModels.swift
//  CorpusKit
//
//  On-disk corpus schema. Pure DTOs with no app-type dependencies: phases use
//  TrancePhase (also in CorpusKit); content type is a raw string bridged on the
//  test-target side. JSON shape is unchanged from the landed schema, plus an
//  optional `generation` provenance block written by the generator.
//
import Foundation

public enum CorpusSource: String, Codable, Sendable { case synthetic, real }
public enum CorpusBoundaryMode: String, Codable, Sendable { case exact, anchored }
public enum CorpusAmbiguityLevel: String, Codable, Sendable {
    case low, medium, high, unspecified
}

/// Segment DTO mirroring `AudioTranscriptionSegment(text:timestamp:duration:confidence:)`.
public struct CorpusSegment: Codable, Sendable {
    public let text: String
    public let timestamp: TimeInterval
    public let duration: TimeInterval
    public let confidence: Double

    public init(text: String, timestamp: TimeInterval, duration: TimeInterval, confidence: Double) {
        self.text = text; self.timestamp = timestamp
        self.duration = duration; self.confidence = confidence
    }
}

/// A ground-truth phase span. `exact` mode: precise. `anchored` mode: anchor
/// regions; gaps between them are unlabeled gray zones the evaluator skips.
public struct PhaseTruthSpan: Codable, Sendable {
    public let phase: TrancePhase
    public let start: TimeInterval
    public let end: TimeInterval

    private enum CodingKeys: String, CodingKey { case phase, start, end }

    public init(phase: TrancePhase, start: TimeInterval, end: TimeInterval) {
        self.phase = phase; self.start = start; self.end = end
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .phase)
        guard let phase = TrancePhase(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .phase, in: c,
                debugDescription: "Unknown phase rawValue '\(raw)'"
            )
        }
        self.phase = phase
        self.start = try c.decode(TimeInterval.self, forKey: .start)
        self.end = try c.decode(TimeInterval.self, forKey: .end)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase.rawValue, forKey: .phase)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
    }
}

/// Provenance for a generated case (spec §3d). Optional; ignored by the harness.
public struct GenerationParams: Codable, Sendable {
    public let archetype: String
    public let ambiguity: String
    public let seedSetID: String?
    public let model: String?
    public let createdAt: Date

    public init(archetype: String, ambiguity: String, seedSetID: String?, model: String?, createdAt: Date) {
        self.archetype = archetype; self.ambiguity = ambiguity
        self.seedSetID = seedSetID; self.model = model; self.createdAt = createdAt
    }
}

/// One corpus case on disk. `truth` drives the timeline metrics; the optional
/// `expected*` fields preserve the legacy presence/order scorers.
public struct CorpusCase: Codable, Sendable {
    public let id: String
    public let source: CorpusSource
    public let boundaryMode: CorpusBoundaryMode
    public let ambiguityLevel: CorpusAmbiguityLevel
    public let duration: TimeInterval
    public let segments: [CorpusSegment]
    public let truth: [PhaseTruthSpan]

    /// Raw content-type string (e.g. "hypnosis"). Bridged to the app's
    /// `AnalysisResult.ContentType` on the test-target side.
    public let expectedContentTypeRaw: String?
    public let expectedPhaseOrder: [TrancePhase]?
    public let minimumPhaseCount: Int?
    public let generation: GenerationParams?

    private enum CodingKeys: String, CodingKey {
        case id, source, boundaryMode, ambiguityLevel, duration, segments, truth
        case expectedContentType, expectedPhaseOrder, minimumPhaseCount, generation
    }

    public init(
        id: String,
        source: CorpusSource,
        boundaryMode: CorpusBoundaryMode,
        ambiguityLevel: CorpusAmbiguityLevel,
        duration: TimeInterval,
        segments: [CorpusSegment],
        truth: [PhaseTruthSpan],
        expectedContentTypeRaw: String? = nil,
        expectedPhaseOrder: [TrancePhase]? = nil,
        minimumPhaseCount: Int? = nil,
        generation: GenerationParams? = nil
    ) {
        self.id = id; self.source = source; self.boundaryMode = boundaryMode
        self.ambiguityLevel = ambiguityLevel; self.duration = duration
        self.segments = segments; self.truth = truth
        self.expectedContentTypeRaw = expectedContentTypeRaw
        self.expectedPhaseOrder = expectedPhaseOrder
        self.minimumPhaseCount = minimumPhaseCount
        self.generation = generation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decode(CorpusSource.self, forKey: .source)
        boundaryMode = try c.decode(CorpusBoundaryMode.self, forKey: .boundaryMode)
        ambiguityLevel = try c.decodeIfPresent(CorpusAmbiguityLevel.self, forKey: .ambiguityLevel) ?? .unspecified
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        segments = try c.decodeIfPresent([CorpusSegment].self, forKey: .segments) ?? []
        truth = try c.decodeIfPresent([PhaseTruthSpan].self, forKey: .truth) ?? []
        expectedContentTypeRaw = try c.decodeIfPresent(String.self, forKey: .expectedContentType)
        if let rawOrder = try c.decodeIfPresent([String].self, forKey: .expectedPhaseOrder) {
            expectedPhaseOrder = rawOrder.compactMap { TrancePhase(rawValue: $0) }
        } else {
            expectedPhaseOrder = nil
        }
        minimumPhaseCount = try c.decodeIfPresent(Int.self, forKey: .minimumPhaseCount)
        generation = try c.decodeIfPresent(GenerationParams.self, forKey: .generation)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(source, forKey: .source)
        try c.encode(boundaryMode, forKey: .boundaryMode)
        try c.encode(ambiguityLevel, forKey: .ambiguityLevel)
        try c.encode(duration, forKey: .duration)
        try c.encode(segments, forKey: .segments)
        try c.encode(truth, forKey: .truth)
        try c.encodeIfPresent(expectedContentTypeRaw, forKey: .expectedContentType)
        try c.encodeIfPresent(expectedPhaseOrder?.map(\.rawValue), forKey: .expectedPhaseOrder)
        try c.encodeIfPresent(minimumPhaseCount, forKey: .minimumPhaseCount)
        try c.encodeIfPresent(generation, forKey: .generation)
    }

    /// Concatenated transcript text (pure; no app types).
    public var transcriptText: String {
        segments.map(\.text).joined(separator: " ")
    }
}
```

- [ ] **Step 4: Move the loader and fix its repo-root math**

Create `Tools/CorpusGenerator/Sources/CorpusKit/CorpusLoader.swift`. The file now lives at `<repo>/Tools/CorpusGenerator/Sources/CorpusKit/CorpusLoader.swift`, so the repo root is **five** parents up (was three). Make it `public`.

```swift
//  CorpusLoader.swift
//  CorpusKit
//
//  Loads corpus JSON from the repo-root `Corpus/<subdirectory>/` directory
//  using a source-file-relative path (no resource bundling). The harness and
//  the generator both resolve the same repo-root `Corpus/`.
//
import Foundation

public enum CorpusLoader {

    /// Repo-root `Corpus/` directory, resolved relative to this source file.
    /// This file lives at
    ///   <repo>/Tools/CorpusGenerator/Sources/CorpusKit/CorpusLoader.swift
    /// so the repo root is five parents up.
    public static var corpusRoot: URL {
        URL(filePath: #filePath)            // .../Sources/CorpusKit/CorpusLoader.swift
            .deletingLastPathComponent()    // .../Sources/CorpusKit
            .deletingLastPathComponent()    // .../Sources
            .deletingLastPathComponent()    // .../CorpusGenerator
            .deletingLastPathComponent()    // .../Tools
            .deletingLastPathComponent()    // .../<repo root>
            .appending(path: "Corpus")
    }

    public static func load(subdirectory: String) throws -> [CorpusCase] {
        let dir = corpusRoot.appending(path: subdirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }

        let urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
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

    public enum CorpusLoadError: Error, CustomStringConvertible {
        case decodeFailed(file: String, underlying: Error)
        public var description: String {
            switch self {
            case let .decodeFailed(file, underlying):
                return "Failed to decode corpus file \(file): \(underlying)"
            }
        }
    }
}
```

- [ ] **Step 5: Add temporary placeholders so the other targets compile**

Create `Tools/CorpusGenerator/Sources/CorpusGenKit/Placeholder.swift`:

```swift
//  Placeholder.swift — replaced in Task 3+. Keeps the target non-empty.
import Foundation
enum CorpusGenKitPlaceholder { static let ready = true }
```

Create `Tools/CorpusGenerator/Sources/CorpusGenerator/main.swift`:

```swift
//  main.swift — replaced in Task 9.
import CorpusKit
print("corpus-gen scaffold; CorpusKit loaded. Phases: \(TrancePhase.allCases.count)")
```

- [ ] **Step 6: Write the failing decode test**

Create `Tools/CorpusGenerator/Tests/CorpusKitTests/CorpusCaseDecodingTests.swift`:

```swift
import Testing
import Foundation
@testable import CorpusKit

struct CorpusCaseDecodingTests {

    @Test("Decodes an exact-mode synthetic case with truth spans")
    func decodesExactCase() throws {
        let json = """
        {
          "id": "synth-0001", "source": "synthetic", "boundaryMode": "exact",
          "ambiguityLevel": "high", "duration": 120.0,
          "segments": [{ "text": "close your eyes", "timestamp": 0.0, "duration": 10.0, "confidence": 1.0 }],
          "truth": [
            { "phase": "induction", "start": 0.0,  "end": 60.0 },
            { "phase": "deepening", "start": 60.0, "end": 120.0 }
          ]
        }
        """
        let kase = try JSONDecoder().decode(CorpusCase.self, from: Data(json.utf8))
        #expect(kase.id == "synth-0001")
        #expect(kase.source == .synthetic)
        #expect(kase.boundaryMode == .exact)
        #expect(kase.ambiguityLevel == .high)
        #expect(kase.truth.first?.phase == .induction)
        #expect(kase.truth.last?.end == 120.0)
    }

    @Test("Decodes a legacy case; content type stays raw, phase order parses")
    func decodesLegacyCase() throws {
        let json = """
        {
          "id": "legacy-1", "source": "real", "boundaryMode": "anchored",
          "ambiguityLevel": "unspecified", "duration": 60.0, "segments": [], "truth": [],
          "expectedContentType": "hypnosis",
          "expectedPhaseOrder": ["pre_talk", "induction"],
          "minimumPhaseCount": 1
        }
        """
        let kase = try JSONDecoder().decode(CorpusCase.self, from: Data(json.utf8))
        #expect(kase.truth.isEmpty)
        #expect(kase.expectedContentTypeRaw == "hypnosis")
        #expect(kase.expectedPhaseOrder == [.preTalk, .induction])
    }

    @Test("Round-trips through encode/decode")
    func roundTrips() throws {
        let original = CorpusCase(
            id: "rt", source: .synthetic, boundaryMode: .exact, ambiguityLevel: .low,
            duration: 30, segments: [CorpusSegment(text: "relax", timestamp: 0, duration: 30, confidence: 1)],
            truth: [PhaseTruthSpan(phase: .induction, start: 0, end: 30)]
        )
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(CorpusCase.self, from: data)
        #expect(back.id == "rt")
        #expect(back.truth.first?.phase == .induction)
        #expect(back.segments.first?.text == "relax")
    }
}
```

- [ ] **Step 7: Build and test the package standalone**

Run: `cd Tools/CorpusGenerator && swift build 2>&1 | tail -20`
Expected: build succeeds (CorpusKit, CorpusGenKit, executable all compile).

Run: `cd Tools/CorpusGenerator && swift test 2>&1 | tail -20`
Expected: PASS — 3 tests in `CorpusCaseDecodingTests`.

Run (proves the executable links CorpusKit): `cd Tools/CorpusGenerator && swift run corpus-gen 2>&1 | tail -3`
Expected: prints `corpus-gen scaffold; CorpusKit loaded. Phases: 12`.

- [ ] **Step 8: Commit**

```bash
git add Tools/CorpusGenerator
git commit -m "feat(corpus-gen): scaffold CorpusKit package (schema + TrancePhase) standalone"
```

---

## Task 2: Integrate `CorpusKit` into the Xcode project

Make the iOS app, test target, and LumeLabel use the **one** `CorpusKit` copy, then delete the originals. This is the one task with Xcode-side risk; it is gated by a green `xcodebuild` build and a green `IlumionateTests` run before any generator logic is written.

**Files:**
- Modify (Xcode project): add local package `Tools/CorpusGenerator`, link `CorpusKit` product to `Ilumionate`, `IlumionateTests`, `LumeLabel`.
- Create: `Ilumionate/CorpusKitReexport.swift`, `LumeLabel/CorpusKitReexport.swift`
- Create: `IlumionateTests/Corpus/CorpusCaseAppBridge.swift`
- Delete: `Ilumionate/TrancePhase.swift`
- Delete: `IlumionateTests/Corpus/CorpusCase.swift`, `IlumionateTests/Corpus/CorpusLoader.swift`, `IlumionateTests/Corpus/CorpusLoaderTests.swift`, `IlumionateTests/Corpus/CorpusCaseTests.swift`

- [ ] **Step 1: Add the local package to the Xcode project and link it to three targets**

In Xcode: **File ▸ Add Package Dependencies… ▸ Add Local…**, choose `Tools/CorpusGenerator`. Then for each of the targets `Ilumionate`, `IlumionateTests`, `LumeLabel`: open **target ▸ General ▸ Frameworks, Libraries, and Embedded Content** (for the app/LumeLabel) or **target ▸ Build Phases ▸ Link Binary With Libraries** (for the test target) and add the **`CorpusKit`** library product.

> No CLI equivalent adds a local-package product dependency reliably; this is a GUI step. If the executing agent cannot drive Xcode, hand this single step to the user. The `CorpusGenKit`/`corpus-gen` targets are **not** linked into any Xcode target — only the `CorpusKit` library product.

- [ ] **Step 2: Re-export `CorpusKit` into the app and LumeLabel modules**

This makes `TrancePhase` (and the corpus types) visible to every file in those modules without per-file imports.

Create `Ilumionate/CorpusKitReexport.swift`:

```swift
//  CorpusKitReexport.swift
//  Ilumionate
//
//  TrancePhase and the corpus schema now live in the CorpusKit package.
//  Re-export so existing files referencing `TrancePhase` keep compiling
//  without per-file imports. `HypnosisMetadata.Phase` (typealias in
//  AudioFile.swift) continues to resolve to CorpusKit.TrancePhase.
@_exported import CorpusKit
```

Create `LumeLabel/CorpusKitReexport.swift`:

```swift
//  CorpusKitReexport.swift
//  LumeLabel
@_exported import CorpusKit
```

- [ ] **Step 3: Add the test-target bridge for app-typed conveniences**

Create `IlumionateTests/Corpus/CorpusCaseAppBridge.swift`. This restores the two app-typed accessors that the pure DTO dropped, bridging the raw content-type string to `AnalysisResult.ContentType` and producing `AudioTranscriptionSegment`s.

```swift
//  CorpusCaseAppBridge.swift
//  IlumionateTests
//
//  Bridges the pure CorpusKit DTO to app types used by the harness:
//  the typed content type and AudioTranscriptionSegment conversion.
//
import Foundation
import CorpusKit
@testable import Ilumionate

extension CorpusCase {
    /// App-typed content type, bridged from the raw string.
    var expectedContentType: AnalysisResult.ContentType? {
        expectedContentTypeRaw.flatMap(AnalysisResult.ContentType.init(rawValue:))
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
}
```

- [ ] **Step 4: Delete the originals now superseded by CorpusKit**

```bash
git rm Ilumionate/TrancePhase.swift \
       IlumionateTests/Corpus/CorpusCase.swift \
       IlumionateTests/Corpus/CorpusLoader.swift \
       IlumionateTests/Corpus/CorpusLoaderTests.swift \
       IlumionateTests/Corpus/CorpusCaseTests.swift
```

> `CorpusLoaderTests.swift` and `CorpusCaseTests.swift` are removed because their coverage now lives in `CorpusKitTests` (decode) and Task 2 Step 6 (loader-from-Xcode). The loader's source-relative path test is environment-specific to the package; the harness's `timelineMetricsOverCorpus` already exercises the loader end-to-end from the Xcode side.

- [ ] **Step 5: Add `import CorpusKit` only where `@_exported` does not reach**

The test target uses `@testable import Ilumionate` (which re-exports CorpusKit via Step 2) plus direct CorpusKit types. To be explicit and avoid relying on transitive re-export inside tests, add `import CorpusKit` to the top of these files **if the build flags them**:
- `IlumionateTests/Corpus/PhaseTimelineEvaluator.swift`
- `IlumionateTests/Corpus/PhaseTimelineEvaluatorTests.swift`
- `IlumionateTests/EvaluationHarnessTests.swift`

Build first (next step); add the import only to files the compiler reports as missing `CorpusCase`/`PhaseTruthSpan`/`TrancePhase`. (App-target files `AudioFile.swift`, `PhaseTimelineNormalizer.swift`, and LumeLabel's `AnalyzerTrainingSupport.swift` are covered by the Step 2 re-exports and should need no change.)

- [ ] **Step 6: Build the app and run the test target — the gate**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build 2>&1 | tail -25`
Expected: **BUILD SUCCEEDED**. If errors mention `cannot find 'TrancePhase'/'CorpusCase' in scope`, the `CorpusKit` link (Step 1) or a `@_exported import` (Step 2) is missing for that target; fix and rebuild.

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests 2>&1 | tail -30`
Expected: PASS — including `timelineMetricsOverCorpus` and `GoldenDatasetTests`. (Use whatever simulator name `xcrun simctl list devices available` shows if `iPhone 16` is absent.)

> **Fallback if local-package linking proves intractable in this environment:** revert Steps 1–2, restore `Ilumionate/TrancePhase.swift` in the app, and instead add the three `CorpusKit` source files to the app/test/LumeLabel target membership directly (same physical files under `Tools/CorpusGenerator/Sources/CorpusKit/`, no module import). Single physical source still prevents drift. This is the spec's documented non-preferred fallback; only use it if Step 6 cannot go green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(eval): source TrancePhase + corpus schema from CorpusKit package"
```

---

## Task 3: CLI option parsing

**Files:**
- Create: `Tools/CorpusGenerator/Sources/CorpusGenerator/CLIOptions.swift`
- Test: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/CLIOptionsTests.swift`

> `CLIOptions` lives in the executable target but is tested from `CorpusGenKitTests`. To make it testable without `@testable`-importing an executable, define the parser in **`CorpusGenKit`** instead. Create the file at `Sources/CorpusGenKit/CLIOptions.swift` (not the executable target).

- [ ] **Step 1: Write the failing test**

Create `Tools/CorpusGenerator/Tests/CorpusGenKitTests/CLIOptionsTests.swift`:

```swift
import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct CLIOptionsTests {

    @Test("Defaults: dry-run off, ambiguity low, count 1, out Corpus/synthetic")
    func defaults() throws {
        let o = try CLIOptions(arguments: [])
        #expect(o.dryRun == false)
        #expect(o.ambiguity == .low)
        #expect(o.count == 1)
        #expect(o.outDirectory.lastPathComponent == "synthetic")
        #expect(o.model == CLIOptions.defaultModel)
    }

    @Test("Parses flags")
    func parsesFlags() throws {
        let o = try CLIOptions(arguments: [
            "--dry-run", "--ambiguity", "high", "--count", "3",
            "--out", "/tmp/out", "--seeds", "/tmp/seeds", "--model", "claude-x",
        ])
        #expect(o.dryRun)
        #expect(o.ambiguity == .high)
        #expect(o.count == 3)
        #expect(o.outDirectory.path == "/tmp/out")
        #expect(o.seedsDirectory?.path == "/tmp/seeds")
        #expect(o.model == "claude-x")
    }

    @Test("Unknown ambiguity throws")
    func badAmbiguity() {
        #expect(throws: CLIOptionsError.self) {
            _ = try CLIOptions(arguments: ["--ambiguity", "banana"])
        }
    }

    @Test("--help sets showHelp")
    func help() throws {
        let o = try CLIOptions(arguments: ["--help"])
        #expect(o.showHelp)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Tools/CorpusGenerator && swift test --filter CLIOptionsTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'CLIOptions' in scope`.

- [ ] **Step 3: Implement the parser**

Create `Tools/CorpusGenerator/Sources/CorpusGenKit/CLIOptions.swift`:

```swift
//  CLIOptions.swift
//  CorpusGenKit
//
//  Parses corpus-gen arguments. Pure value type so it is unit-testable.
//
import Foundation
import CorpusKit

public enum CLIOptionsError: Error, CustomStringConvertible {
    case missingValue(flag: String)
    case unknownAmbiguity(String)
    case badCount(String)
    public var description: String {
        switch self {
        case .missingValue(let f): return "Missing value for \(f)"
        case .unknownAmbiguity(let v): return "Unknown --ambiguity '\(v)' (use low|medium|high)"
        case .badCount(let v): return "Invalid --count '\(v)'"
        }
    }
}

public struct CLIOptions: Sendable {
    public static let defaultModel = "claude-sonnet-4-5"

    public var dryRun = false
    public var showHelp = false
    public var ambiguity: CorpusAmbiguityLevel = .low
    public var count = 1
    public var outDirectory: URL
    public var seedsDirectory: URL?
    public var model = CLIOptions.defaultModel

    public init(arguments: [String]) throws {
        // Default out = <repo>/Corpus/synthetic
        outDirectory = CorpusLoader.corpusRoot.appending(path: "synthetic")

        var i = 0
        func value(_ flag: String) throws -> String {
            guard i + 1 < arguments.count else { throw CLIOptionsError.missingValue(flag: flag) }
            i += 1
            return arguments[i]
        }
        while i < arguments.count {
            let arg = arguments[i]
            switch arg {
            case "--dry-run": dryRun = true
            case "--help", "-h": showHelp = true
            case "--ambiguity":
                let v = try value(arg)
                guard let a = CorpusAmbiguityLevel(rawValue: v), a != .unspecified else {
                    throw CLIOptionsError.unknownAmbiguity(v)
                }
                ambiguity = a
            case "--count":
                let v = try value(arg)
                guard let n = Int(v), n > 0 else { throw CLIOptionsError.badCount(v) }
                count = n
            case "--out": outDirectory = URL(filePath: try value(arg))
            case "--seeds": seedsDirectory = URL(filePath: try value(arg))
            case "--model": model = try value(arg)
            default: break
            }
            i += 1
        }
    }

    public static let helpText = """
    corpus-gen — synthetic hypnosis corpus generator (dev tool)

      --dry-run           Use the offline stub responder (no network/API key)
      --ambiguity LEVEL   low | medium | high   (default low)
      --count N           Number of cases to generate (default 1)
      --out DIR           Output directory (default <repo>/Corpus/synthetic)
      --seeds DIR         LumeLabel TrainingCorpus dir for few-shot seeds (optional)
      --model NAME        Anthropic model id (default \(defaultModel))
      --help              Show this help

    Real generation reads ANTHROPIC_API_KEY from the environment.
    """
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Tools/CorpusGenerator && swift test --filter CLIOptionsTests 2>&1 | tail -15`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Tools/CorpusGenerator/Sources/CorpusGenKit/CLIOptions.swift Tools/CorpusGenerator/Tests/CorpusGenKitTests/CLIOptionsTests.swift
git commit -m "feat(corpus-gen): CLI option parsing"
```

---

## Task 4: Phase plan (classic archetype + duration variation)

**Files:**
- Create: `Tools/CorpusGenerator/Sources/CorpusGenKit/PhasePlan.swift`
- Test: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/PhasePlanTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tools/CorpusGenerator/Tests/CorpusGenKitTests/PhasePlanTests.swift`:

```swift
import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct PhasePlanTests {

    @Test("Classic archetype has the canonical 5-phase order")
    func classicOrder() {
        var rng = SeededRNG(seed: 42)
        let plan = PhasePlan.classic(using: &rng)
        #expect(plan.blocks.map(\.phase) == [.preTalk, .induction, .deepening, .therapy, .emergence])
    }

    @Test("Block durations are positive and within configured ranges")
    func durationsInRange() {
        var rng = SeededRNG(seed: 7)
        let plan = PhasePlan.classic(using: &rng)
        for block in plan.blocks {
            #expect(block.duration > 0)
            let range = PhasePlan.durationRange(for: block.phase)
            #expect(block.duration >= range.lowerBound)
            #expect(block.duration <= range.upperBound)
        }
    }

    @Test("totalDuration equals the sum of block durations")
    func totalDuration() {
        var rng = SeededRNG(seed: 1)
        let plan = PhasePlan.classic(using: &rng)
        #expect(abs(plan.totalDuration - plan.blocks.reduce(0) { $0 + $1.duration }) < 0.0001)
    }

    @Test("Same seed reproduces the same plan")
    func deterministic() {
        var a = SeededRNG(seed: 99); var b = SeededRNG(seed: 99)
        let p1 = PhasePlan.classic(using: &a)
        let p2 = PhasePlan.classic(using: &b)
        #expect(p1.blocks.map(\.duration) == p2.blocks.map(\.duration))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Tools/CorpusGenerator && swift test --filter PhasePlanTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'PhasePlan'/'SeededRNG' in scope`.

- [ ] **Step 3: Implement the plan + a seeded RNG**

Create `Tools/CorpusGenerator/Sources/CorpusGenKit/PhasePlan.swift`:

```swift
//  PhasePlan.swift
//  CorpusGenKit
//
//  A phase plan is an ordered list of (phase, duration) blocks. The assembler
//  places blocks back-to-back, so boundary truth is exact by construction.
//
import Foundation
import CorpusKit

/// Deterministic RNG so a seed reproduces a plan (spec §3d reproducibility).
public struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    public init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    public mutating func next() -> UInt64 {
        // splitmix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct PhasePlanBlock: Sendable, Equatable {
    public let phase: TrancePhase
    public let duration: TimeInterval
    public init(phase: TrancePhase, duration: TimeInterval) {
        self.phase = phase; self.duration = duration
    }
}

public struct PhasePlan: Sendable {
    public let archetype: String
    public let blocks: [PhasePlanBlock]

    public init(archetype: String, blocks: [PhasePlanBlock]) {
        self.archetype = archetype; self.blocks = blocks
    }

    public var totalDuration: TimeInterval { blocks.reduce(0) { $0 + $1.duration } }

    /// Per-phase duration range (seconds) used to vary block lengths.
    public static func durationRange(for phase: TrancePhase) -> ClosedRange<TimeInterval> {
        switch phase {
        case .preTalk:   return 30...90
        case .induction: return 90...240
        case .deepening: return 120...300
        case .therapy:   return 120...360
        case .emergence: return 30...90
        default:         return 60...180
        }
    }

    /// Classic induction→deepening→therapy→emergence archetype with varied lengths.
    public static func classic<R: RandomNumberGenerator>(using rng: inout R) -> PhasePlan {
        let order: [TrancePhase] = [.preTalk, .induction, .deepening, .therapy, .emergence]
        let blocks = order.map { phase -> PhasePlanBlock in
            let r = durationRange(for: phase)
            let d = TimeInterval.random(in: r, using: &rng).rounded()
            return PhasePlanBlock(phase: phase, duration: d)
        }
        return PhasePlan(archetype: "classic", blocks: blocks)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Tools/CorpusGenerator && swift test --filter PhasePlanTests 2>&1 | tail -15`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Tools/CorpusGenerator/Sources/CorpusGenKit/PhasePlan.swift Tools/CorpusGenerator/Tests/CorpusGenKitTests/PhasePlanTests.swift
git commit -m "feat(corpus-gen): classic phase plan with seeded duration variation"
```

---

## Task 5: Block responder protocol + offline stub

**Files:**
- Create: `Tools/CorpusGenerator/Sources/CorpusGenKit/BlockResponder.swift`
- Test: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/BlockResponderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tools/CorpusGenerator/Tests/CorpusGenKitTests/BlockResponderTests.swift`:

```swift
import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct BlockResponderTests {

    @Test("Stub returns non-empty, phase-appropriate keyword text")
    func stubText() async throws {
        let responder = StubResponder()
        let inductionReq = BlockRequest(phase: .induction, durationSec: 120, ambiguity: .low, seeds: [], priorPhases: [])
        let text = try await responder.text(for: inductionReq)
        #expect(!text.isEmpty)
        // Induction stub contains a canonical induction cue.
        #expect(text.localizedCaseInsensitiveContains("close your eyes"))
    }

    @Test("Stub covers every TrancePhase without crashing")
    func stubAllPhases() async throws {
        let responder = StubResponder()
        for phase in TrancePhase.allCases {
            let req = BlockRequest(phase: phase, durationSec: 60, ambiguity: .low, seeds: [], priorPhases: [])
            let text = try await responder.text(for: req)
            #expect(!text.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Tools/CorpusGenerator && swift test --filter BlockResponderTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'StubResponder'/'BlockRequest' in scope`.

- [ ] **Step 3: Implement the protocol + stub**

Create `Tools/CorpusGenerator/Sources/CorpusGenKit/BlockResponder.swift`:

```swift
//  BlockResponder.swift
//  CorpusGenKit
//
//  Abstraction over "produce the transcript text for one phase block".
//  StubResponder is offline & deterministic (dry-run + tests); ClaudeResponder
//  (in ClaudeClient.swift) hits the Anthropic API.
//
import Foundation
import CorpusKit

/// A real per-phase excerpt sliced from a labeled transcript (few-shot seed).
public struct PhaseSeed: Sendable, Equatable {
    public let phase: TrancePhase
    public let excerpt: String
    public init(phase: TrancePhase, excerpt: String) {
        self.phase = phase; self.excerpt = excerpt
    }
}

public struct BlockRequest: Sendable {
    public let phase: TrancePhase
    public let durationSec: TimeInterval
    public let ambiguity: CorpusAmbiguityLevel
    public let seeds: [PhaseSeed]
    public let priorPhases: [TrancePhase]
    public init(phase: TrancePhase, durationSec: TimeInterval, ambiguity: CorpusAmbiguityLevel,
                seeds: [PhaseSeed], priorPhases: [TrancePhase]) {
        self.phase = phase; self.durationSec = durationSec; self.ambiguity = ambiguity
        self.seeds = seeds; self.priorPhases = priorPhases
    }
}

public protocol BlockResponder: Sendable {
    func text(for request: BlockRequest) async throws -> String
}

/// Deterministic, offline responder. Emits keyword-rich, phase-appropriate text
/// so dry-run output is realistic enough for the analyzer to classify and the
/// harness to score — without any network call.
public struct StubResponder: BlockResponder {
    public init() {}

    public func text(for request: BlockRequest) async throws -> String {
        Self.template(for: request.phase)
    }

    static func template(for phase: TrancePhase) -> String {
        switch phase {
        case .preTalk:
            return "Welcome, and make yourself comfortable. Today we will explore hypnosis together, and I want you to know you are safe. Just relax and listen to the sound of my voice as we begin."
        case .induction:
            return "Now close your eyes and take a slow, deep breath. Let your eyelids grow heavy, so heavy you can barely keep them open, and let them close all the way down. Just relax and let go completely now."
        case .fractionation:
            return "Open your eyes for a moment... and now close them again, twice as deep as before. Up, and back down, deeper each time, sinking further with every cycle."
        case .deepening:
            return "Going deeper now, deeper and deeper with every breath you take. Down, down, ten times more relaxed with each number I count. Drifting further down into this calm, heavy relaxation."
        case .confusion:
            return "And the more you try to follow, the less you need to, because as you wonder you drift, and as you drift you wonder, and none of it matters as you simply let go."
        case .therapy:
            return "In this deep, calm state, imagine your goal clearly in front of you. See yourself confident and capable, achieving exactly what you came here for, feeling stronger with every breath."
        case .suggestions:
            return "From now on, each day you feel calmer, more focused, and more in control. These feelings grow stronger every time you relax like this, and they stay with you long after you wake."
        case .eroticSuggestions:
            return "Each wave of relaxation feels warm and pleasant, a gentle pleasure spreading through you as you sink deeper and surrender more completely to the calm."
        case .brainwashing:
            return "You believe it because it is true, and it is true because you believe it. The words become your thoughts, and your thoughts become the words, again and again."
        case .conditioning:
            return "Whenever you hear my voice, you return to this calm state instantly, every single time. The moment I say relax, you drop down twice as deep, automatically."
        case .emergence:
            return "In a moment I will count up to five, and you will wake feeling refreshed and alert. One, two, three, four, five — eyes open, wide awake, feeling wonderful and fully present."
        case .transitional:
            return "And as one feeling gently gives way to the next, you simply continue to relax, letting the change happen all on its own."
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Tools/CorpusGenerator && swift test --filter BlockResponderTests 2>&1 | tail -15`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Tools/CorpusGenerator/Sources/CorpusGenKit/BlockResponder.swift Tools/CorpusGenerator/Tests/CorpusGenKitTests/BlockResponderTests.swift
git commit -m "feat(corpus-gen): block responder protocol + offline keyword-rich stub"
```

---

## Task 6: Session assembler (plan → CorpusCase with exact truth)

**Files:**
- Create: `Tools/CorpusGenerator/Sources/CorpusGenKit/SessionAssembler.swift`
- Test: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/SessionAssemblerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tools/CorpusGenerator/Tests/CorpusGenKitTests/SessionAssemblerTests.swift`:

```swift
import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct SessionAssemblerTests {

    private func twoBlockPlan() -> PhasePlan {
        PhasePlan(archetype: "test", blocks: [
            PhasePlanBlock(phase: .induction, duration: 60),
            PhasePlanBlock(phase: .deepening, duration: 60),
        ])
    }

    @Test("Truth spans are contiguous, exact, and cover [0, totalDuration]")
    func contiguousTruth() async throws {
        let assembler = SessionAssembler(responder: StubResponder())
        let kase = try await assembler.assemble(
            plan: twoBlockPlan(), ambiguity: .low, idPrefix: "synth", model: nil, seedSetID: nil
        )
        #expect(kase.boundaryMode == .exact)
        #expect(kase.source == .synthetic)
        #expect(kase.duration == 120)
        #expect(kase.truth.count == 2)
        #expect(kase.truth[0].phase == .induction)
        #expect(kase.truth[0].start == 0)
        #expect(kase.truth[0].end == 60)
        #expect(kase.truth[1].phase == .deepening)
        #expect(kase.truth[1].start == 60)
        #expect(kase.truth[1].end == 120)
    }

    @Test("Segments are non-empty and stay within their block window")
    func segmentsWithinWindow() async throws {
        let assembler = SessionAssembler(responder: StubResponder())
        let kase = try await assembler.assemble(
            plan: twoBlockPlan(), ambiguity: .low, idPrefix: "synth", model: nil, seedSetID: nil
        )
        #expect(!kase.segments.isEmpty)
        for seg in kase.segments {
            #expect(seg.timestamp >= 0)
            #expect(seg.timestamp + seg.duration <= kase.duration + 0.001)
        }
        // Induction keyword lands in the first block window (before 60s).
        let early = kase.segments.filter { $0.timestamp < 60 }.map(\.text).joined(separator: " ")
        #expect(early.localizedCaseInsensitiveContains("close your eyes"))
    }

    @Test("Stamps generation provenance and ambiguity")
    func stampsProvenance() async throws {
        let assembler = SessionAssembler(responder: StubResponder())
        let kase = try await assembler.assemble(
            plan: twoBlockPlan(), ambiguity: .high, idPrefix: "synth", model: "claude-x", seedSetID: "seedset-1"
        )
        #expect(kase.ambiguityLevel == .high)
        #expect(kase.generation?.archetype == "test")
        #expect(kase.generation?.ambiguity == "high")
        #expect(kase.generation?.model == "claude-x")
        #expect(kase.generation?.seedSetID == "seedset-1")
        #expect(kase.id.hasPrefix("synth-"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Tools/CorpusGenerator && swift test --filter SessionAssemblerTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'SessionAssembler' in scope`.

- [ ] **Step 3: Implement the assembler**

Create `Tools/CorpusGenerator/Sources/CorpusGenKit/SessionAssembler.swift`:

```swift
//  SessionAssembler.swift
//  CorpusGenKit
//
//  Requests one text block per phase from a BlockResponder, places blocks
//  back-to-back, splits each block's text into evenly-timed segments, and emits
//  one CorpusCase. Because the assembler owns placement, truth spans are exact.
//
import Foundation
import CorpusKit

public struct SessionAssembler: Sendable {
    private let responder: BlockResponder
    public init(responder: BlockResponder) { self.responder = responder }

    public func assemble(
        plan: PhasePlan,
        ambiguity: CorpusAmbiguityLevel,
        idPrefix: String,
        model: String?,
        seedSetID: String?
    ) async throws -> CorpusCase {
        var truth: [PhaseTruthSpan] = []
        var segments: [CorpusSegment] = []
        var cursor: TimeInterval = 0
        var priorPhases: [TrancePhase] = []

        for block in plan.blocks {
            let start = cursor
            let end = cursor + block.duration
            let request = BlockRequest(
                phase: block.phase, durationSec: block.duration,
                ambiguity: ambiguity, seeds: [], priorPhases: priorPhases
            )
            let text = try await responder.text(for: request)
            segments.append(contentsOf: Self.segmentize(text: text, start: start, duration: block.duration))
            truth.append(PhaseTruthSpan(phase: block.phase, start: start, end: end))
            cursor = end
            priorPhases.append(block.phase)
        }

        let shortID = UUID().uuidString.prefix(8).lowercased()
        return CorpusCase(
            id: "\(idPrefix)-\(plan.archetype)-\(shortID)",
            source: .synthetic,
            boundaryMode: .exact,
            ambiguityLevel: ambiguity,
            duration: cursor,
            segments: segments,
            truth: truth,
            expectedContentTypeRaw: "hypnosis",
            expectedPhaseOrder: plan.blocks.map(\.phase),
            minimumPhaseCount: max(1, plan.blocks.count - 1),
            generation: GenerationParams(
                archetype: plan.archetype,
                ambiguity: ambiguity.rawValue,
                seedSetID: seedSetID,
                model: model,
                createdAt: Date()
            )
        )
    }

    /// Splits text into sentence-ish segments distributed evenly across the
    /// block window [start, start+duration]. Always yields at least one segment.
    static func segmentize(text: String, start: TimeInterval, duration: TimeInterval) -> [CorpusSegment] {
        let sentences = text
            .split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let parts = sentences.isEmpty ? [text] : sentences
        let each = duration / Double(parts.count)
        return parts.enumerated().map { idx, sentence in
            CorpusSegment(
                text: sentence,
                timestamp: start + Double(idx) * each,
                duration: each,
                confidence: 1.0
            )
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Tools/CorpusGenerator && swift test --filter SessionAssemblerTests 2>&1 | tail -15`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Tools/CorpusGenerator/Sources/CorpusGenKit/SessionAssembler.swift Tools/CorpusGenerator/Tests/CorpusGenKitTests/SessionAssemblerTests.swift
git commit -m "feat(corpus-gen): session assembler with exact truth spans + provenance"
```

---

## Task 7: Seed library (real LumeLabel files → per-phase seeds)

**Files:**
- Create: `Tools/CorpusGenerator/Sources/CorpusGenKit/SeedLibrary.swift`
- Create: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/Fixtures/label.json`
- Create: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/Fixtures/transcript.json`
- Test: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/SeedLibraryTests.swift`

The real layout (verified): a label file `<dir>/<uuid>.json` has `audioSHA256` and `phases[] = {phase, startTime, endTime}`; the matching transcript is `<dir>/AnalyzerDataset/cache/transcripts/<sha256>.json` with `transcription.segments[] = {text, timestamp, duration, confidence}` and `transcription.duration`.

- [ ] **Step 1: Create trimmed fixtures mirroring the real shape**

Create `Tools/CorpusGenerator/Tests/CorpusGenKitTests/Fixtures/label.json`:

```json
{
  "id": "FIXTURE-0001",
  "audioSHA256": "abc123",
  "audioDuration": 120.0,
  "expectedContentType": "hypnosis",
  "phases": [
    { "phase": "induction", "startTime": 0.0,  "endTime": 60.0 },
    { "phase": "deepening", "startTime": 60.0, "endTime": 120.0 }
  ]
}
```

Create `Tools/CorpusGenerator/Tests/CorpusGenKitTests/Fixtures/transcript.json` (note nested directory must match the real layout; place under `Fixtures/AnalyzerDataset/cache/transcripts/abc123.json`):

> Path: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/Fixtures/AnalyzerDataset/cache/transcripts/abc123.json`

```json
{
  "audioSHA256": "abc123",
  "transcription": {
    "fullText": "close your eyes and relax. going deeper now.",
    "duration": 120.0,
    "locale": "en",
    "segments": [
      { "text": "close your eyes and relax", "timestamp": 10.0, "duration": 8.0, "confidence": 0.9 },
      { "text": "going deeper and deeper now", "timestamp": 80.0, "duration": 8.0, "confidence": 0.9 }
    ]
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `Tools/CorpusGenerator/Tests/CorpusGenKitTests/SeedLibraryTests.swift`:

```swift
import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct SeedLibraryTests {

    private var fixturesDir: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()       // .../CorpusGenKitTests
            .appending(path: "Fixtures")
    }

    @Test("Loads per-phase excerpts by slicing the transcript at phase anchors")
    func loadsSeeds() throws {
        let seeds = try SeedLibrary.load(from: fixturesDir)
        // Two phases in the label → up to two seeds (segments fall in each window).
        #expect(seeds.contains { $0.phase == .induction })
        #expect(seeds.contains { $0.phase == .deepening })
        let induction = seeds.first { $0.phase == .induction }
        #expect(induction?.excerpt.localizedCaseInsensitiveContains("close your eyes") == true)
        let deepening = seeds.first { $0.phase == .deepening }
        #expect(deepening?.excerpt.localizedCaseInsensitiveContains("deeper") == true)
    }

    @Test("Missing directory yields no seeds (graceful zero-shot fallback)")
    func missingDirIsEmpty() throws {
        let seeds = try SeedLibrary.load(from: URL(filePath: "/definitely/not/here"))
        #expect(seeds.isEmpty)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd Tools/CorpusGenerator && swift test --filter SeedLibraryTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'SeedLibrary' in scope`.

- [ ] **Step 4: Implement the seed library**

Create `Tools/CorpusGenerator/Sources/CorpusGenKit/SeedLibrary.swift`:

```swift
//  SeedLibrary.swift
//  CorpusGenKit
//
//  Reads LumeLabel TrainingCorpus files (label JSON + SHA-keyed transcript
//  cache) and slices each transcript by its labeled phase anchors, yielding
//  real per-phase excerpts for few-shot seeding. Optional: a missing or empty
//  directory yields no seeds (zero-shot fallback).
//
import Foundation
import CorpusKit

public enum SeedLibrary {

    // Minimal decoders for the on-disk LumeLabel shapes.
    private struct LabelFile: Decodable {
        let audioSHA256: String
        let phases: [LabelPhase]
    }
    private struct LabelPhase: Decodable {
        let phase: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }
    private struct TranscriptFile: Decodable {
        let transcription: Transcription
        struct Transcription: Decodable {
            let segments: [Segment]
        }
        struct Segment: Decodable {
            let text: String
            let timestamp: TimeInterval
            let duration: TimeInterval
        }
    }

    /// Max characters kept per phase excerpt (keeps the prompt prefix bounded).
    static let maxExcerptChars = 1200

    public static func load(from directory: URL) throws -> [PhaseSeed] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        let transcriptsDir = directory
            .appending(path: "AnalyzerDataset")
            .appending(path: "cache")
            .appending(path: "transcripts")

        let labelURLs = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        var byPhase: [TrancePhase: String] = [:]   // first excerpt wins per phase

        for labelURL in labelURLs {
            guard let label = try? decoder.decode(LabelFile.self, from: Data(contentsOf: labelURL)) else {
                continue   // not a label file (e.g. a manifest) — skip
            }
            let transcriptURL = transcriptsDir.appending(path: "\(label.audioSHA256).json")
            guard fm.fileExists(atPath: transcriptURL.path),
                  let transcript = try? decoder.decode(TranscriptFile.self, from: Data(contentsOf: transcriptURL))
            else { continue }

            for labelPhase in label.phases {
                guard let phase = TrancePhase(rawValue: labelPhase.phase), byPhase[phase] == nil else { continue }
                let excerpt = transcript.transcription.segments
                    .filter { $0.timestamp >= labelPhase.startTime && $0.timestamp < labelPhase.endTime }
                    .map(\.text)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !excerpt.isEmpty else { continue }
                byPhase[phase] = String(excerpt.prefix(maxExcerptChars))
            }
        }

        return byPhase
            .map { PhaseSeed(phase: $0.key, excerpt: $0.value) }
            .sorted { $0.phase.rawValue < $1.phase.rawValue }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd Tools/CorpusGenerator && swift test --filter SeedLibraryTests 2>&1 | tail -15`
Expected: PASS (2 tests).

> If the fixtures are not found, confirm SwiftPM is copying them: the `Fixtures/` directory sits under the test target's path and is read via `#filePath`, not as a bundle resource, so no `resources:` entry is needed in `Package.swift`. The test resolves the directory relative to its own source file.

- [ ] **Step 6: Commit**

```bash
git add Tools/CorpusGenerator/Sources/CorpusGenKit/SeedLibrary.swift Tools/CorpusGenerator/Tests/CorpusGenKitTests/SeedLibraryTests.swift Tools/CorpusGenerator/Tests/CorpusGenKitTests/Fixtures
git commit -m "feat(corpus-gen): seed library slicing real transcripts by phase anchors"
```

---

## Task 8: Claude client (request builder + URLSession responder)

**Files:**
- Create: `Tools/CorpusGenerator/Sources/CorpusGenKit/ClaudeClient.swift`
- Test: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/ClaudeRequestBuilderTests.swift`

Only the **pure request-building** logic is unit-tested (system/seed prefix, per-block user message, JSON body). The live network call is exercised manually in Task 9.

- [ ] **Step 1: Write the failing test**

Create `Tools/CorpusGenerator/Tests/CorpusGenKitTests/ClaudeRequestBuilderTests.swift`:

```swift
import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct ClaudeRequestBuilderTests {

    @Test("System prefix embeds seed excerpts and is marked cacheable")
    func systemPrefixHasSeeds() {
        let builder = ClaudeRequestBuilder(model: "claude-x")
        let seeds = [PhaseSeed(phase: .induction, excerpt: "close your eyes")]
        let body = builder.body(
            for: BlockRequest(phase: .deepening, durationSec: 90, ambiguity: .medium, seeds: seeds, priorPhases: [.induction])
        )
        let system = body["system"] as? [[String: Any]]
        let joined = (system ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        #expect(joined.localizedCaseInsensitiveContains("close your eyes"))
        // Cache control present on the (large, stable) seed block.
        #expect((system ?? []).contains { ($0["cache_control"] as? [String: Any]) != nil })
    }

    @Test("User message names the target phase and duration")
    func userMessageTargets() {
        let builder = ClaudeRequestBuilder(model: "claude-x")
        let body = builder.body(
            for: BlockRequest(phase: .emergence, durationSec: 45, ambiguity: .high, seeds: [], priorPhases: [.therapy])
        )
        let messages = body["messages"] as? [[String: Any]]
        let text = (messages?.first?["content"] as? String) ?? ""
        #expect(text.localizedCaseInsensitiveContains("emergence"))
        #expect(text.contains("45"))
        #expect(body["model"] as? String == "claude-x")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Tools/CorpusGenerator && swift test --filter ClaudeRequestBuilderTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'ClaudeRequestBuilder' in scope`.

- [ ] **Step 3: Implement the request builder + responder**

Create `Tools/CorpusGenerator/Sources/CorpusGenKit/ClaudeClient.swift`:

```swift
//  ClaudeClient.swift
//  CorpusGenKit
//
//  Builds Anthropic Messages API requests (seed excerpts live in a cacheable
//  system prefix per the claude-api skill) and performs them with URLSession.
//  ClaudeResponder conforms to BlockResponder for real generation.
//
import Foundation
import CorpusKit

public struct ClaudeRequestBuilder: Sendable {
    public let model: String
    public let maxTokens: Int
    public init(model: String, maxTokens: Int = 1024) {
        self.model = model; self.maxTokens = maxTokens
    }

    /// JSON body for one phase-block request. Seeds go in the system prefix
    /// with cache_control so the identical prefix is billed once across calls.
    public func body(for request: BlockRequest) -> [String: Any] {
        var system: [[String: Any]] = [[
            "type": "text",
            "text": Self.styleGuide,
        ]]
        if !request.seeds.isEmpty {
            let seedText = request.seeds
                .map { "## \($0.phase.displayName) — real example\n\($0.excerpt)" }
                .joined(separator: "\n\n")
            system.append([
                "type": "text",
                "text": "Use these real transcript excerpts as style references:\n\n\(seedText)",
                "cache_control": ["type": "ephemeral"],
            ])
        }

        let prior = request.priorPhases.map(\.displayName).joined(separator: " → ")
        let ambiguityHint = Self.ambiguityHint(request.ambiguity)
        let user = """
        Write the spoken transcript for ONE phase of a hypnosis session.
        Phase: \(request.phase.displayName).
        Approximate spoken length: \(Int(request.durationSec)) seconds (~\(Int(request.durationSec * 2.3)) words).
        Prior phases so far: \(prior.isEmpty ? "none" : prior).
        \(ambiguityHint)
        Output ONLY the spoken words for this phase — no headings, no stage directions, no quotation marks.
        """

        return [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
    }

    static func ambiguityHint(_ level: CorpusAmbiguityLevel) -> String {
        switch level {
        case .low:
            return "Use direct, recognizable language for this phase, with clear cues."
        case .medium:
            return "Paraphrase and use indirect, Ericksonian language; avoid obvious keywords."
        case .high:
            return "Use fuzzy, metaphor-heavy transitions that bleed into adjacent phases; make boundaries hard to place."
        case .unspecified:
            return ""
        }
    }

    static let styleGuide = """
    You are scripting authentic hypnosis/trance session transcripts for a research \
    corpus. Write natural spoken language as a hypnotist would actually speak it, \
    pacing it to the requested duration. Stay in the voice of a single narrator.
    """
}

public enum ClaudeClientError: Error, CustomStringConvertible {
    case missingAPIKey
    case httpError(status: Int, body: String)
    case malformedResponse
    public var description: String {
        switch self {
        case .missingAPIKey: return "ANTHROPIC_API_KEY is not set"
        case .httpError(let s, let b): return "Anthropic API HTTP \(s): \(b)"
        case .malformedResponse: return "Could not parse Anthropic API response"
        }
    }
}

public struct ClaudeResponder: BlockResponder {
    private let builder: ClaudeRequestBuilder
    private let apiKey: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    public init(model: String, apiKey: String, session: URLSession = .shared) {
        self.builder = ClaudeRequestBuilder(model: model)
        self.apiKey = apiKey
        self.session = session
    }

    /// Reads ANTHROPIC_API_KEY from the environment; nil if unset.
    public static func fromEnvironment(model: String) -> ClaudeResponder? {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
            return nil
        }
        return ClaudeResponder(model: model, apiKey: key)
    }

    public func text(for request: BlockRequest) async throws -> String {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: builder.body(for: request))

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeClientError.httpError(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first = content.first(where: { ($0["type"] as? String) == "text" }),
            let text = first["text"] as? String
        else { throw ClaudeClientError.malformedResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Tools/CorpusGenerator && swift test --filter ClaudeRequestBuilderTests 2>&1 | tail -15`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Tools/CorpusGenerator/Sources/CorpusGenKit/ClaudeClient.swift Tools/CorpusGenerator/Tests/CorpusGenKitTests/ClaudeRequestBuilderTests.swift
git commit -m "feat(corpus-gen): Anthropic request builder + URLSession responder"
```

---

## Task 9: Wire `main`, emit files, and verify end to end

**Files:**
- Replace: `Tools/CorpusGenerator/Sources/CorpusGenerator/main.swift`
- Create: `Tools/CorpusGenerator/Sources/CorpusGenKit/CorpusWriter.swift`
- Test: `Tools/CorpusGenerator/Tests/CorpusGenKitTests/CorpusWriterTests.swift`
- Modify: `.gitignore` (repo root)
- Delete: `Tools/CorpusGenerator/Sources/CorpusGenKit/Placeholder.swift`

- [ ] **Step 1: Write the failing writer test**

Create `Tools/CorpusGenerator/Tests/CorpusGenKitTests/CorpusWriterTests.swift`:

```swift
import Testing
import Foundation
@testable import CorpusGenKit
import CorpusKit

struct CorpusWriterTests {

    @Test("Writes a decodable JSON file named after the case id")
    func writesDecodableFile() throws {
        let tmp = URL.temporaryDirectory.appending(path: "corpusgen-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let kase = CorpusCase(
            id: "synth-classic-deadbeef", source: .synthetic, boundaryMode: .exact,
            ambiguityLevel: .low, duration: 60,
            segments: [CorpusSegment(text: "relax", timestamp: 0, duration: 60, confidence: 1)],
            truth: [PhaseTruthSpan(phase: .induction, start: 0, end: 60)]
        )
        let url = try CorpusWriter.write(kase, to: tmp)
        #expect(url.lastPathComponent == "synth-classic-deadbeef.json")

        let back = try JSONDecoder().decode(CorpusCase.self, from: Data(contentsOf: url))
        #expect(back.id == kase.id)
        #expect(back.truth.first?.phase == .induction)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Tools/CorpusGenerator && swift test --filter CorpusWriterTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'CorpusWriter' in scope`.

- [ ] **Step 3: Implement the writer**

Create `Tools/CorpusGenerator/Sources/CorpusGenKit/CorpusWriter.swift`:

```swift
//  CorpusWriter.swift
//  CorpusGenKit
//
//  Serializes a CorpusCase to <outDir>/<id>.json, creating the directory.
//
import Foundation
import CorpusKit

public enum CorpusWriter {
    public static func write(_ kase: CorpusCase, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appending(path: "\(kase.id).json")
        try encoder.encode(kase).write(to: url, options: .atomic)
        return url
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Tools/CorpusGenerator && swift test --filter CorpusWriterTests 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Replace `main.swift` with the real entry point**

Replace `Tools/CorpusGenerator/Sources/CorpusGenerator/main.swift`:

```swift
//  main.swift
//  CorpusGenerator (corpus-gen)
//
//  Dev-time CLI: generates synthetic hypnosis corpus cases. Uses the offline
//  stub responder for --dry-run or when ANTHROPIC_API_KEY is unset; otherwise
//  calls the Anthropic API. Never ships in the app bundle.
//
import Foundation
import CorpusKit
import CorpusGenKit

func run() async -> Int32 {
    let options: CLIOptions
    do {
        options = try CLIOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    } catch {
        FileHandle.standardError.write(Data("\(error)\n\n\(CLIOptions.helpText)\n".utf8))
        return 2
    }
    if options.showHelp {
        print(CLIOptions.helpText)
        return 0
    }

    // Seeds (optional). Default seed dir = ~/Documents/TrainingCorpus.
    let seedDir = options.seedsDirectory
        ?? URL.homeDirectory.appending(path: "Documents").appending(path: "TrainingCorpus")
    let seeds = (try? SeedLibrary.load(from: seedDir)) ?? []
    let seedSetID = seeds.isEmpty ? nil : "seeds-\(seeds.count)"
    if seeds.isEmpty {
        print("No few-shot seeds found at \(seedDir.path); generating zero-shot.")
    } else {
        print("Loaded \(seeds.count) phase seed(s) from \(seedDir.path).")
    }

    // Responder selection.
    let responder: BlockResponder
    let modelStamp: String?
    if options.dryRun {
        responder = StubResponder()
        modelStamp = nil
        print("Dry run: using offline stub responder.")
    } else if let claude = ClaudeResponder.fromEnvironment(model: options.model) {
        responder = SeededResponder(base: claude, seeds: seeds)
        modelStamp = options.model
        print("Using Anthropic model \(options.model).")
    } else {
        responder = StubResponder()
        modelStamp = nil
        print("ANTHROPIC_API_KEY not set: falling back to offline stub responder.")
    }

    let assembler = SessionAssembler(responder: responder)
    var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970))

    for _ in 0..<options.count {
        let plan = PhasePlan.classic(using: &rng)
        do {
            let kase = try await assembler.assemble(
                plan: plan, ambiguity: options.ambiguity,
                idPrefix: "synth", model: modelStamp, seedSetID: seedSetID
            )
            let url = try CorpusWriter.write(kase, to: options.outDirectory)
            print("Wrote \(url.path)  (\(kase.truth.count) phases, \(Int(kase.duration))s)")
        } catch {
            FileHandle.standardError.write(Data("Generation failed: \(error)\n".utf8))
            return 1
        }
    }
    return 0
}

exit(await run())
```

- [ ] **Step 6: Add the seed-injecting responder wrapper**

The `SessionAssembler` passes empty `seeds` in each `BlockRequest`; this wrapper injects the loaded seeds into requests destined for the real Claude responder. Append to `Tools/CorpusGenerator/Sources/CorpusGenKit/BlockResponder.swift`:

```swift

/// Wraps a base responder, injecting loaded few-shot seeds into each request.
public struct SeededResponder: BlockResponder {
    private let base: BlockResponder
    private let seeds: [PhaseSeed]
    public init(base: BlockResponder, seeds: [PhaseSeed]) {
        self.base = base; self.seeds = seeds
    }
    public func text(for request: BlockRequest) async throws -> String {
        let relevant = seeds.filter { $0.phase == request.phase }
        let enriched = BlockRequest(
            phase: request.phase, durationSec: request.durationSec,
            ambiguity: request.ambiguity, seeds: relevant, priorPhases: request.priorPhases
        )
        return try await base.text(for: enriched)
    }
}
```

- [ ] **Step 7: Delete the placeholder and gitignore generated output**

```bash
rm Tools/CorpusGenerator/Sources/CorpusGenKit/Placeholder.swift
```

Append to the repo-root `.gitignore`:

```gitignore
# corpus-gen output (generated dev artifacts; not committed)
Corpus/synthetic/*.json
```

- [ ] **Step 8: Full package test + offline end-to-end dry run**

Run: `cd Tools/CorpusGenerator && swift test 2>&1 | tail -20`
Expected: PASS — all suites (`CorpusCaseDecodingTests`, `CLIOptionsTests`, `PhasePlanTests`, `BlockResponderTests`, `SessionAssemblerTests`, `SeedLibraryTests`, `ClaudeRequestBuilderTests`, `CorpusWriterTests`).

Run (offline emit to a temp dir, no key): `cd Tools/CorpusGenerator && swift run corpus-gen --dry-run --out /tmp/corpusgen-smoke 2>&1 | tail -6 && ls /tmp/corpusgen-smoke`
Expected: prints `Wrote /tmp/corpusgen-smoke/synth-classic-XXXXXXXX.json (5 phases, …s)` and the file is listed.

Run (proves the harness loader decodes generated output — copy the dry-run file into the scored path, run the timeline test, then clean up):
```bash
cd /Users/byronquine/Documents/Programing/Swift/Practice/Ilumionate
cp /tmp/corpusgen-smoke/*.json Corpus/synthetic/
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:IlumionateTests/KeywordPipelineEvaluationTests/timelineMetricsOverCorpus 2>&1 | tail -20
rm Corpus/synthetic/synth-classic-*.json
```
Expected: PASS — `timelineMetricsOverCorpus` loads the generated case (now N+1 truth-bearing cases) and stays at or above the 0.40 floor. The keyword-rich stub text scores well enough not to drop the floor. (If the floor is borderline, that is signal for Phase-1 tuning, not a plan failure — note the observed value.)

- [ ] **Step 9: Commit**

```bash
git add Tools/CorpusGenerator .gitignore
git commit -m "feat(corpus-gen): wire CLI end-to-end with dry-run + seed injection"
```

- [ ] **Step 10: Real generation smoke (manual, optional — requires API key)**

This is a manual confirmation of DoD #3, not a committed/CI step:
```bash
cd /Users/byronquine/Documents/Programing/Swift/Practice/Ilumionate/Tools/CorpusGenerator
ANTHROPIC_API_KEY=… swift run corpus-gen --count 1 --out /tmp/corpusgen-real
cat /tmp/corpusgen-real/*.json | head -40
```
Expected: a genuine synthetic case with real Claude-authored phase text, exact truth spans, and `generation.model` stamped. Inspect that induction/deepening text reads naturally and that seeds were loaded (the run logs the seed count).

---

## Self-Review

**Spec coverage:**
- Shared `CorpusKit` module (no drift) → Task 1 (extract) + Task 2 (link app/tests/LumeLabel). ✓
- `Tools/CorpusGenerator/` package layout → Task 1. ✓
- Generation one phase block at a time → Task 6 (`SessionAssembler`). ✓
- Exact, free boundary truth → Task 6 (contiguous truth spans test). ✓
- Few-shot seeding from real label+transcript files, optional with zero-shot fallback → Task 7 + Task 9 (`SeededResponder`, missing-dir fallback). ✓
- Ambiguity knob (low/medium/high, default low) → Task 3 + Task 8 (`ambiguityHint`). ✓
- `ANTHROPIC_API_KEY` from env, never hardcoded; URLSession Messages API; seeds in cacheable prefix → Task 8. ✓
- Determinism/provenance stamping → `GenerationParams` (Task 1) stamped in Task 6; seeded RNG (Task 4). ✓
- Offline `--dry-run`, no network in unit tests → Task 5 stub + Task 9 dry-run path. ✓
- Harness loads & scores generated file with no harness change → Task 9 Step 8 (copy into `Corpus/synthetic/`, run existing `timelineMetricsOverCorpus`). ✓
- Dev-time only, never ships → only `CorpusKit` library is linked into Xcode targets; `corpus-gen`/`CorpusGenKit` are not (Task 2 Step 1). ✓

**Placeholder scan:** No TBD/TODO. Every code step shows complete code. The one GUI step (Task 2 Step 1) is explicit with a stated fallback (Task 2 Step 6). The "add import if the compiler flags it" instruction (Task 2 Step 5) is compiler-driven, with the known pre-seeded set listed.

**Type consistency:** `CorpusCase`, `CorpusSegment`, `PhaseTruthSpan`, `GenerationParams`, `TrancePhase`, `CorpusAmbiguityLevel`, `CorpusLoader` (CorpusKit); `CLIOptions`, `SeededRNG`, `PhasePlan`, `PhasePlanBlock`, `BlockRequest`, `BlockResponder`, `StubResponder`, `SeededResponder`, `PhaseSeed`, `SessionAssembler`, `SeedLibrary`, `ClaudeRequestBuilder`, `ClaudeResponder`, `CorpusWriter` (CorpusGenKit). Method names consistent across tasks: `text(for:)`, `assemble(plan:ambiguity:idPrefix:model:seedSetID:)`, `SeedLibrary.load(from:)`, `CorpusWriter.write(_:to:)`, `PhasePlan.classic(using:)`, `body(for:)`. The assembler stamps `expectedContentTypeRaw: "hypnosis"`, matching the DTO field renamed in Task 1.

**Cross-task risk note for the implementer:** Task 2 is the gate. Do not start Task 3 until `xcodebuild build` and `IlumionateTests` are green. If local-package linking cannot be made to work in this environment, use the Task 2 Step 6 fallback (shared physical files via target membership) before proceeding — every later task only depends on the SwiftPM package, which is unaffected by the fallback.
