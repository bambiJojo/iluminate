# Text Trance — M1 Implementation Plan (Core Engine + Bundled Library + Screens)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a dedicated "Text Trance" screen that plays hand-reviewed hypnosis scripts as RSVP word-streams with ORP focus-letter anchoring, composing with the existing light and binaural layers, supporting both `fullText` and `handoff` session arcs.

**Architecture:** A pure, fully unit-tested core (`TranceScript` model → `TextPacingEngine` schedule → `ORPCalculator`) feeds an `@Observable @MainActor` coordinator (`TextTranceSession`) that orchestrates the existing `FlashController` and `BinauralBeatsEngine` through small protocols, rendered by three SwiftUI screens reached from a new tab. Scripts are bundled JSON resources, loaded and validated like `LightScoreReader` does for sessions.

**Tech Stack:** Swift 6.2, SwiftUI, `@Observable`, Swift Testing (`import Testing`), CorpusKit (`TrancePhase`), existing `FlashController` + `BinauralBeatsEngine`.

**Spec:** `docs/superpowers/specs/2026-06-10-text-trance-design.md`

---

## Deviations from the Spec (intentional, locked during planning)

1. **No `handoffCue` `TrancePhase` case.** `TrancePhase` lives in the shared CorpusKit package and feeds the analyzer/evaluation harness; adding a case there is invasive and semantically wrong (it's a script-authoring concept, not an analysis phase). Instead, a segment carries an optional `triggersHandoff: Bool`. The eyes-close cue is a `transitional` segment (NOT `emergence` — emergence means "wake back up", which is the opposite of the eyes-close handoff intent) tagged `arcs: ["handoff"]` with `triggersHandoff: true`, and carries an explicit slow `baseWPM` so its pace doesn't default to the fast emergence depth. Segment `phase` values must be valid CorpusKit `TrancePhase` raw values (e.g. `suggestions`, plural — not `suggestion`).
2. **Deepening curve derives from `TrancePhase.tranceDepthEstimate`** (already defined) when a segment omits an explicit `baseWPM`. When a segment *provides* `baseWPM`, that author intent is used directly (no double-applied slowdown).
3. **`FlashController` runs only in the handoff tail in M1**, because `start()` forces screen brightness to 1.0 — unsuitable behind eyes-open reading. Concurrent reading-time light + the entrainment-lock text mode are deferred to M2. The "Light pulse" toggle therefore appears in Setup only for the `handoff` arc in M1.

## File Structure

All new app code under `Ilumionate/TextTrance/`. All new tests under `IlumionateTests/TextTrance/`.

| File | Responsibility |
|---|---|
| `Ilumionate/TextTrance/TranceScript.swift` | Codable models: `TranceScript`, `TranceScriptSegment`, `SegmentPacing`, `ScriptArc`, `ScriptTheme`, `ScriptSource` |
| `Ilumionate/TextTrance/ORPCalculator.swift` | Pure pivot-index function (ORP rule) |
| `Ilumionate/TextTrance/WordTokenizer.swift` | Split segment text into tokens; sentence-end detection |
| `Ilumionate/TextTrance/TextPacingEngine.swift` | Pure: `TranceScript` + settings → `[PacedWord]` schedule |
| `Ilumionate/TextTrance/TranceScriptLibrary.swift` | Parse / validate / discover bundled scripts |
| `Ilumionate/TextTrance/TextTranceLayers.swift` | `LightLayerControlling` / `AudioLayerControlling` protocols + conformances |
| `Ilumionate/TextTrance/TextTranceSession.swift` | `@Observable @MainActor` coordinator: playback loop, arc/layer orchestration |
| `Ilumionate/TextTrance/TextTranceRootView.swift` | NavigationStack host for the tab |
| `Ilumionate/TextTrance/TextTranceLibraryView.swift` | Script picker (theme filter, cards) |
| `Ilumionate/TextTrance/TextTranceSetupView.swift` | Arc / layers / speed selection → builds settings |
| `Ilumionate/TextTrance/TextTrancePlayerView.swift` | Control-free ORP word player |
| `Ilumionate/TextTrance/Scripts/deep-drift.json` | Bundled relaxation script (both arcs) |
| `Ilumionate/TextTrance/Scripts/shoreline-sleep.json` | Bundled sleep script (handoff, no emergence) |
| `Ilumionate/TextTrance/Scripts/clear-signal.json` | Bundled focus script (fullText, eyes-open) |
| `Ilumionate/TranceTabBar.swift` (modify) | Add `.read` tab case |
| `Ilumionate/ContentView.swift` (modify) | Route `.read` → `TextTranceRootView` |

---

## Task 1: TranceScript models

**Files:**
- Create: `Ilumionate/TextTrance/TranceScript.swift`
- Test: `IlumionateTests/TextTrance/TranceScriptDecodingTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  TranceScriptDecodingTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

struct TranceScriptDecodingTests {

    static let sampleJSON = """
    {
      "schemaVersion": 1,
      "id": "deep-drift-01",
      "title": "Deep Drift",
      "theme": "relaxation",
      "supportedArcs": ["fullText", "handoff"],
      "language": "en",
      "source": { "kind": "bundled", "generator": "hand-authored", "reviewed": true },
      "segments": [
        { "phase": "induction",  "text": "Allow your eyes to rest.", "pacing": { "baseWPM": 140 } },
        { "phase": "deepening",  "text": "Deeper and deeper." },
        { "phase": "emergence",  "text": "Return now, refreshed.", "arcs": ["fullText"] },
        { "phase": "transitional",  "text": "Let your eyes close.", "arcs": ["handoff"], "triggersHandoff": true }
      ]
    }
    """

    @Test func decodesAllFields() throws {
        let data = Data(Self.sampleJSON.utf8)
        let script = try JSONDecoder().decode(TranceScript.self, from: data)

        #expect(script.id == "deep-drift-01")
        #expect(script.title == "Deep Drift")
        #expect(script.theme == .relaxation)
        #expect(script.supportedArcs == [.fullText, .handoff])
        #expect(script.source.reviewed == true)
        #expect(script.segments.count == 4)
        #expect(script.segments[0].phase == .induction)
        #expect(script.segments[0].pacing?.baseWPM == 140)
        #expect(script.segments[1].pacing == nil)
        #expect(script.segments[2].arcs == [.fullText])
        #expect(script.segments[3].triggersHandoff == true)
        #expect(script.segments[0].triggersHandoff == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/TranceScriptDecodingTests`
Expected: FAIL — `cannot find 'TranceScript' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
//  TranceScript.swift
//  Ilumionate
//
//  Data model for a Text Trance reading script: phase-structured plain-text
//  segments plus metadata. Loaded from bundled JSON, paced at runtime.

import Foundation

/// Which session arc a script (or segment) supports.
enum ScriptArc: String, Codable, Sendable, CaseIterable, Identifiable {
    case fullText   // eyes-open from induction through read emergence
    case handoff    // text inducts, then eyes close; light/binaural finish

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullText: return "Read everything"
        case .handoff:  return "Read, then eyes close"
        }
    }
}

/// High-level intent of a script. Distinct from `TrancePhase` (which is
/// per-segment). Drives the library theme filter.
enum ScriptTheme: String, Codable, Sendable, CaseIterable, Identifiable {
    case relaxation
    case sleep
    case focus
    case suggestion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relaxation: return "Relaxation"
        case .sleep:      return "Sleep"
        case .focus:      return "Focus"
        case .suggestion: return "Self-Suggestion"
        }
    }
}

/// Provenance + review status of a script's content.
struct ScriptSource: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case bundled
        case generated
    }
    let kind: Kind
    let generator: String?
    let reviewed: Bool
}

/// Per-segment pacing hint. `baseWPM` is a target words-per-minute the engine
/// multiplies by the user speed setting; never a hard timing.
struct SegmentPacing: Codable, Sendable, Equatable {
    let baseWPM: Double
}

/// One phase-tagged chunk of script text.
struct TranceScriptSegment: Codable, Sendable {
    let phase: TrancePhase
    let text: String
    let pacing: SegmentPacing?
    /// Arcs this segment plays in. `nil` => plays in every arc.
    let arcs: [ScriptArc]?
    /// When true (handoff arc only), reaching the end of this segment ends the
    /// reading portion and triggers the light/binaural handoff tail.
    let triggersHandoff: Bool?
}

/// A complete Text Trance script.
struct TranceScript: Codable, Sendable, Identifiable {
    let schemaVersion: Int
    let id: String
    let title: String
    let theme: ScriptTheme
    let supportedArcs: [ScriptArc]
    let language: String
    let source: ScriptSource
    let segments: [TranceScriptSegment]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/TranceScriptDecodingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TranceScript.swift IlumionateTests/TextTrance/TranceScriptDecodingTests.swift
git commit -m "feat(text-trance): TranceScript model + JSON decoding"
```

---

## Task 2: ORPCalculator (pivot-letter rule)

**Files:**
- Create: `Ilumionate/TextTrance/ORPCalculator.swift`
- Test: `IlumionateTests/TextTrance/ORPCalculatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  ORPCalculatorTests.swift
//  IlumionateTests

import Testing
@testable import Ilumionate

struct ORPCalculatorTests {

    @Test("Pivot index follows the standard ORP rule",
          arguments: [
            ("a", 0),        // 1 letter -> 1st
            ("to", 1),       // 2-5 -> 2nd
            ("rest", 1),     // 2-5 -> 2nd
            ("softly", 2),   // 6-9 -> 3rd
            ("downward", 2), // 6-9 -> 3rd (8 letters)
            ("consciously", 3) // 10+ -> 4th
          ])
    func pivotIndex(word: String, expected: Int) {
        #expect(ORPCalculator.pivotIndex(for: word) == expected)
    }

    @Test func emptyWordIsZero() {
        #expect(ORPCalculator.pivotIndex(for: "") == 0)
    }

    @Test func pivotIgnoresTrailingPunctuationForLength() {
        // "deeper." has 6 letters + 1 punctuation; pivot computed on letters only.
        #expect(ORPCalculator.pivotIndex(for: "deeper.") == 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/ORPCalculatorTests`
Expected: FAIL — `cannot find 'ORPCalculator' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
//  ORPCalculator.swift
//  Ilumionate
//
//  Optimal Recognition Point: the index of the letter to align to the fixed
//  anchor and tint. Standard Spritz-style rule based on letter count.

import Foundation

enum ORPCalculator {
    /// Zero-based index of the pivot letter, computed over letters only
    /// (trailing/leading punctuation does not shift the pivot).
    static func pivotIndex(for word: String) -> Int {
        let letters = word.count { $0.isLetter || $0.isNumber }
        switch letters {
        case 0, 1: return 0
        case 2...5: return 1
        case 6...9: return 2
        default:    return 3
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/ORPCalculatorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/ORPCalculator.swift IlumionateTests/TextTrance/ORPCalculatorTests.swift
git commit -m "feat(text-trance): ORP pivot-letter calculator"
```

---

## Task 3: WordTokenizer

**Files:**
- Create: `Ilumionate/TextTrance/WordTokenizer.swift`
- Test: `IlumionateTests/TextTrance/WordTokenizerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  WordTokenizerTests.swift
//  IlumionateTests

import Testing
@testable import Ilumionate

struct WordTokenizerTests {

    @Test func splitsOnWhitespaceAndDropsEmpties() {
        let tokens = WordTokenizer.tokenize("Allow  your   eyes")
        #expect(tokens.map(\.text) == ["Allow", "your", "eyes"])
    }

    @Test func flagsSentenceEndingPunctuation() {
        let tokens = WordTokenizer.tokenize("Rest now. Drift deeper…")
        #expect(tokens.map(\.endsSentence) == [false, true, false, true])
    }

    @Test func treatsQuestionAndExclamationAsSentenceEnds() {
        let tokens = WordTokenizer.tokenize("Ready? Yes!")
        #expect(tokens.map(\.endsSentence) == [true, true])
    }

    @Test func emptyStringYieldsNoTokens() {
        #expect(WordTokenizer.tokenize("   ").isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/WordTokenizerTests`
Expected: FAIL — `cannot find 'WordTokenizer' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
//  WordTokenizer.swift
//  Ilumionate
//
//  Splits segment text into display tokens, flagging sentence-ending words so
//  the pacing engine can insert a hold pause (the hypnotic "breathing room").

import Foundation

struct WordToken: Equatable, Sendable {
    let text: String
    let endsSentence: Bool
}

enum WordTokenizer {
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]

    static func tokenize(_ text: String) -> [WordToken] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map { raw in
                let word = String(raw)
                let ends = word.last.map { sentenceEnders.contains($0) } ?? false
                return WordToken(text: word, endsSentence: ends)
            }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/WordTokenizerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/WordTokenizer.swift IlumionateTests/TextTrance/WordTokenizerTests.swift
git commit -m "feat(text-trance): word tokenizer with sentence-end detection"
```

---

## Task 4: TextPacingEngine

**Files:**
- Create: `Ilumionate/TextTrance/TextPacingEngine.swift`
- Test: `IlumionateTests/TextTrance/TextPacingEngineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  TextPacingEngineTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

struct TextPacingEngineTests {

    // Two-word induction segment with explicit 120 WPM (=> 0.5 s/word at 1.0x).
    private func script(arcs: [ScriptArc],
                        segments: [TranceScriptSegment]) -> TranceScript {
        TranceScript(
            schemaVersion: 1, id: "t", title: "T", theme: .relaxation,
            supportedArcs: arcs, language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: segments
        )
    }

    @Test func explicitWPMSetsWordDuration() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "rest now",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural))
        #expect(schedule.count == 2)
        // 60 / 120 = 0.5 s per word; "now" ends sentence? no period -> no hold.
        #expect(abs(schedule[0].duration - 0.5) < 0.0001)
        #expect(schedule[0].startTime == 0)
        #expect(abs(schedule[1].startTime - 0.5) < 0.0001)
        #expect(schedule[0].pivotIndex == ORPCalculator.pivotIndex(for: "rest"))
        #expect(schedule[0].phase == .induction)
    }

    @Test func sentenceEndAddsHold() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "rest.",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural))
        // 0.5 base * 2.5 hold = 1.25 s
        #expect(abs(schedule[0].duration - 1.25) < 0.0001)
    }

    @Test func speedMultiplierScalesDuration() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "rest now",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil)
        ])
        let brisk = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .brisk))
        // brisk = 1.35x WPM => duration / 1.35
        #expect(abs(brisk[0].duration - (0.5 / 1.35)) < 0.0001)
    }

    @Test func missingWPMUsesDepthDerivedPace() {
        // deepening depth ~0.62 -> slower than induction depth ~0.22
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "one",
                                pacing: nil, arcs: nil, triggersHandoff: nil),
            TranceScriptSegment(phase: .deepening, text: "two",
                                pacing: nil, arcs: nil, triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural))
        #expect(schedule[1].duration > schedule[0].duration)
    }

    @Test func fullTextArcExcludesHandoffOnlySegments() {
        let s = script(arcs: [.fullText, .handoff], segments: [
            TranceScriptSegment(phase: .induction, text: "read me",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil),
            TranceScriptSegment(phase: .emergence, text: "eyes close",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: [.handoff], triggersHandoff: true)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural))
        #expect(schedule.map(\.text) == ["read", "me"])
    }

    @Test func handoffArcStopsAfterTriggerSegment() {
        let s = script(arcs: [.fullText, .handoff], segments: [
            TranceScriptSegment(phase: .induction, text: "read me",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil),
            TranceScriptSegment(phase: .emergence, text: "eyes close",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: [.handoff], triggersHandoff: true),
            TranceScriptSegment(phase: .emergence, text: "should not appear",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: [.handoff], triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .handoff, speed: .natural))
        #expect(schedule.map(\.text) == ["read", "me", "eyes", "close"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/TextPacingEngineTests`
Expected: FAIL — `cannot find 'TextPacingEngine' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
//  TextPacingEngine.swift
//  Ilumionate
//
//  Pure transform: a TranceScript + user settings -> a fully-timed schedule of
//  words to display. No UI, no clock, no script content knowledge beyond text.
//  Same philosophy as the light engine: deterministic, unit-testable.

import Foundation

/// One scheduled word ready to render.
struct PacedWord: Equatable, Sendable {
    let text: String
    let pivotIndex: Int
    let phase: TrancePhase
    let startTime: TimeInterval  // cumulative seconds from reading start
    let duration: TimeInterval   // how long this word is held
}

/// User-tunable pacing inputs.
struct TextPacingSettings: Sendable {
    enum Speed: String, CaseIterable, Sendable, Identifiable {
        case slow, natural, brisk
        var id: String { rawValue }
        var multiplier: Double {
            switch self {
            case .slow:    return 0.75
            case .natural: return 1.0
            case .brisk:   return 1.35
            }
        }
        var displayName: String {
            switch self {
            case .slow: return "Slow"
            case .natural: return "Natural"
            case .brisk: return "Brisk"
            }
        }
    }
    let arc: ScriptArc
    let speed: Speed
}

enum TextPacingEngine {
    /// WPM used when a segment omits an explicit pacing hint, before the
    /// depth-derived slowdown is applied.
    static let defaultBaseWPM: Double = 150
    /// Sentence-ending words are held this many times longer.
    static let sentenceHoldMultiplier: Double = 2.5
    /// Slowest depth factor (applied at max trance depth) for depth-derived pace.
    static let deepeningFloor: Double = 0.55

    static func schedule(for script: TranceScript,
                         settings: TextPacingSettings) -> [PacedWord] {
        var result: [PacedWord] = []
        var cursor: TimeInterval = 0

        for segment in script.segments {
            guard segmentPlays(segment, in: settings.arc) else { continue }

            let wpm = effectiveWPM(for: segment, speed: settings.speed)
            let baseDuration = 60.0 / wpm

            for token in WordTokenizer.tokenize(segment.text) {
                let duration = token.endsSentence
                    ? baseDuration * sentenceHoldMultiplier
                    : baseDuration
                result.append(PacedWord(
                    text: token.text,
                    pivotIndex: ORPCalculator.pivotIndex(for: token.text),
                    phase: segment.phase,
                    startTime: cursor,
                    duration: duration
                ))
                cursor += duration
            }

            // In the handoff arc, stop once the trigger segment is consumed.
            if settings.arc == .handoff, segment.triggersHandoff == true {
                break
            }
        }
        return result
    }

    private static func segmentPlays(_ segment: TranceScriptSegment,
                                     in arc: ScriptArc) -> Bool {
        guard let arcs = segment.arcs else { return true }
        return arcs.contains(arc)
    }

    private static func effectiveWPM(for segment: TranceScriptSegment,
                                     speed: TextPacingSettings.Speed) -> Double {
        if let hint = segment.pacing?.baseWPM {
            return hint * speed.multiplier
        }
        // Depth-derived: deeper phases read slower.
        let depth = segment.phase.tranceDepthEstimate            // 0...1
        let depthFactor = 1.0 - depth * (1.0 - deepeningFloor)   // [floor, 1]
        return defaultBaseWPM * depthFactor * speed.multiplier
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/TextPacingEngineTests`
Expected: PASS (all 6 cases).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextPacingEngine.swift IlumionateTests/TextTrance/TextPacingEngineTests.swift
git commit -m "feat(text-trance): runtime pacing engine (RSVP schedule)"
```

---

## Task 5: TranceScriptLibrary (parse / validate / load)

**Files:**
- Create: `Ilumionate/TextTrance/TranceScriptLibrary.swift`
- Test: `IlumionateTests/TextTrance/TranceScriptLibraryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  TranceScriptLibraryTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

struct TranceScriptLibraryTests {

    private let valid = Data(TranceScriptDecodingTests.sampleJSON.utf8)

    @Test func parseAcceptsValidScript() throws {
        let script = try TranceScriptLibrary.parse(valid)
        #expect(script.id == "deep-drift-01")
    }

    @Test func validateRejectsEmptySegments() {
        let script = TranceScript(
            schemaVersion: 1, id: "x", title: "X", theme: .focus,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [])
        #expect(throws: TranceScriptLibrary.LibraryError.self) {
            try TranceScriptLibrary.validate(script)
        }
    }

    @Test func validateRejectsUnknownSchemaVersion() {
        let script = TranceScript(
            schemaVersion: 99, id: "x", title: "X", theme: .focus,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [TranceScriptSegment(phase: .induction, text: "hi",
                pacing: nil, arcs: nil, triggersHandoff: nil)])
        #expect(throws: TranceScriptLibrary.LibraryError.self) {
            try TranceScriptLibrary.validate(script)
        }
    }

    @Test func loadAllSkipsInvalidFilesAndKeepsValidOnes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "tt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try valid.write(to: dir.appending(path: "good.json"))
        try Data("{ not a script }".utf8).write(to: dir.appending(path: "bad.json"))

        let scripts = TranceScriptLibrary.loadAll(inDirectory: dir)
        #expect(scripts.map(\.id) == ["deep-drift-01"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/TranceScriptLibraryTests`
Expected: FAIL — `cannot find 'TranceScriptLibrary' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
//  TranceScriptLibrary.swift
//  Ilumionate
//
//  Discovers, decodes, and validates bundled Text Trance scripts. Mirrors the
//  LightScoreReader posture: malformed files are skipped with a log, never
//  crashing the picker.

import Foundation
import os

enum TranceScriptLibrary {

    static let currentSchemaVersion = 1

    enum LibraryError: LocalizedError {
        case unsupportedSchemaVersion(Int)
        case emptySegments
        case emptySupportedArcs
        case missingIdentifier

        var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let v):
                return "Unsupported script schema version: \(v)"
            case .emptySegments:    return "Script has no segments"
            case .emptySupportedArcs: return "Script supports no arcs"
            case .missingIdentifier: return "Script id/title is empty"
            }
        }
    }

    static func parse(_ data: Data) throws -> TranceScript {
        let script = try JSONDecoder().decode(TranceScript.self, from: data)
        try validate(script)
        return script
    }

    static func validate(_ script: TranceScript) throws {
        guard script.schemaVersion == currentSchemaVersion else {
            throw LibraryError.unsupportedSchemaVersion(script.schemaVersion)
        }
        guard !script.id.isEmpty, !script.title.isEmpty else {
            throw LibraryError.missingIdentifier
        }
        guard !script.supportedArcs.isEmpty else {
            throw LibraryError.emptySupportedArcs
        }
        guard !script.segments.isEmpty else {
            throw LibraryError.emptySegments
        }
    }

    /// Load every valid `.json` script in a directory, skipping invalid ones.
    static func loadAll(inDirectory dir: URL) -> [TranceScript] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }

        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                do {
                    return try parse(Data(contentsOf: url))
                } catch {
                    Log.audio.info("[TranceScriptLibrary] Skipping \(url.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }
    }

    /// Discover bundled scripts shipped under the app's `Scripts` resource group.
    static func bundled(in bundle: Bundle = .main) -> [TranceScript] {
        guard let urls = bundle.urls(
            forResourcesWithExtension: "json", subdirectory: nil) else { return [] }
        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in try? parse(Data(contentsOf: url)) }
    }
}
```

> Note: `bundled()` attempt-decodes every bundled `.json`; existing session JSONs fail `TranceScript` decoding and are naturally excluded. `Log.audio` is the existing `os.Logger` category used across the app (see `BinauralBeatsEngine`).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/TranceScriptLibraryTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TranceScriptLibrary.swift IlumionateTests/TextTrance/TranceScriptLibraryTests.swift
git commit -m "feat(text-trance): script library loader + validation"
```

---

## Task 6: Author bundled scripts + content regression tests

**Files:**
- Create: `Ilumionate/TextTrance/Scripts/deep-drift.json`
- Create: `Ilumionate/TextTrance/Scripts/shoreline-sleep.json`
- Create: `Ilumionate/TextTrance/Scripts/clear-signal.json`
- Test: `IlumionateTests/TextTrance/BundledTranceScriptTests.swift`

- [ ] **Step 1: Author `deep-drift.json` (relaxation, both arcs)**

```json
{
  "schemaVersion": 1,
  "id": "deep-drift",
  "title": "Deep Drift",
  "theme": "relaxation",
  "supportedArcs": ["fullText", "handoff"],
  "language": "en",
  "source": { "kind": "bundled", "generator": "hand-authored", "reviewed": true },
  "segments": [
    { "phase": "induction", "text": "Allow your gaze to rest softly on each word as it arrives. There is nothing to do here but receive. Each word settles into you like a slow, warm breath.", "pacing": { "baseWPM": 150 } },
    { "phase": "deepening", "text": "And with every word you take in, you sink a little further. Down, and down, and gently down. Heavier now. Calmer now. Carried.", "pacing": { "baseWPM": 110 } },
    { "phase": "suggestions", "text": "Stillness is easy for you. Your mind grows quiet and clear, like water with no wind. You hold this calm long after the words are gone.", "pacing": { "baseWPM": 95 } },
    { "phase": "emergence", "text": "In a moment you will lift gently back, bringing the calm with you, awake, clear, and rested.", "pacing": { "baseWPM": 135 }, "arcs": ["fullText"] },
    { "phase": "transitional", "text": "And now, with the next slow breath, let your eyes drift softly closed, and simply keep drifting.", "pacing": { "baseWPM": 90 }, "arcs": ["handoff"], "triggersHandoff": true }
  ]
}
```

- [ ] **Step 2: Author `shoreline-sleep.json` (sleep, handoff only, no emergence)**

```json
{
  "schemaVersion": 1,
  "id": "shoreline-sleep",
  "title": "Shoreline Sleep",
  "theme": "sleep",
  "supportedArcs": ["handoff"],
  "language": "en",
  "source": { "kind": "bundled", "generator": "hand-authored", "reviewed": true },
  "segments": [
    { "phase": "induction", "text": "Let each word arrive like a small, slow wave on a quiet shore. You do not have to hold any of them. They simply come, and go, and ease you down.", "pacing": { "baseWPM": 130 } },
    { "phase": "deepening", "text": "Warmer. Softer. Heavier with every line. The sand holds you. The tide breathes for you. Lower, and slower, and further from the day.", "pacing": { "baseWPM": 95 } },
    { "phase": "deepening", "text": "And now you no longer need the words at all. Let your eyes close, and let the tide carry you the rest of the way down into sleep.", "pacing": { "baseWPM": 80 }, "triggersHandoff": true }
  ]
}
```

- [ ] **Step 3: Author `clear-signal.json` (focus, fullText only, eyes-open)**

```json
{
  "schemaVersion": 1,
  "id": "clear-signal",
  "title": "Clear Signal",
  "theme": "focus",
  "supportedArcs": ["fullText"],
  "language": "en",
  "source": { "kind": "bundled", "generator": "hand-authored", "reviewed": true },
  "segments": [
    { "phase": "induction", "text": "Keep your attention on the single point where each word appears. One word. Then the next. The noise around the edges begins to fall away.", "pacing": { "baseWPM": 170 } },
    { "phase": "deepening", "text": "Your focus narrows to a clean, bright line. Sharp. Steady. Everything that does not matter goes quiet, and what matters stands out clearly.", "pacing": { "baseWPM": 150 } },
    { "phase": "suggestions", "text": "You hold this clarity easily. Your mind is a clear signal now, ready, precise, and fully here.", "pacing": { "baseWPM": 145 } },
    { "phase": "emergence", "text": "Carry this sharpness forward as you lift your eyes, alert, focused, and ready to begin.", "pacing": { "baseWPM": 165 } }
  ]
}
```

- [ ] **Step 4: Add the three JSON files to the app target's bundled resources**

Open `Ilumionate.xcodeproj` in Xcode. Confirm `Ilumionate/TextTrance/Scripts/*.json` appear under the Ilumionate target's "Copy Bundle Resources" build phase (with the synchronized file group they are normally added automatically; if not, drag the `Scripts` folder into the target and ensure "Copy Bundle Resources" lists all three). Build once to confirm:

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Write the content regression test**

```swift
//  BundledTranceScriptTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

struct BundledTranceScriptTests {

    /// Locate the source Scripts directory relative to this test file so the
    /// shipped JSON is validated regardless of test-bundle packaging.
    private static var scriptsDir: URL {
        URL(filePath: #filePath)            // .../IlumionateTests/TextTrance/BundledTranceScriptTests.swift
            .deletingLastPathComponent()    // .../IlumionateTests/TextTrance
            .deletingLastPathComponent()    // .../IlumionateTests
            .deletingLastPathComponent()    // repo root
            .appending(path: "Ilumionate/TextTrance/Scripts")
    }

    private static let eyesClosurePhrases = [
        "close your eyes", "eyes closed", "let your eyes close",
        "let your eyes drift", "eyes drift closed", "eyes gently closed"
    ]

    @Test func everyBundledScriptParsesAndValidates() throws {
        let scripts = TranceScriptLibrary.loadAll(inDirectory: Self.scriptsDir)
        #expect(scripts.count >= 3)
        let ids = Set(scripts.map(\.id))
        #expect(ids.isSuperset(of: ["deep-drift", "shoreline-sleep", "clear-signal"]))
    }

    @Test func everyScriptIsHumanReviewed() {
        let scripts = TranceScriptLibrary.loadAll(inDirectory: Self.scriptsDir)
        #expect(scripts.allSatisfy { $0.source.reviewed })
    }

    @Test func eachSupportedArcProducesANonEmptySchedule() {
        for script in TranceScriptLibrary.loadAll(inDirectory: Self.scriptsDir) {
            for arc in script.supportedArcs {
                let schedule = TextPacingEngine.schedule(
                    for: script, settings: .init(arc: arc, speed: .natural))
                #expect(!schedule.isEmpty, "\(script.id)/\(arc.rawValue) empty")
            }
        }
    }

    @Test func fullTextSchedulesContainNoEyesClosurePhrasing() {
        for script in TranceScriptLibrary.loadAll(inDirectory: Self.scriptsDir)
            where script.supportedArcs.contains(.fullText) {
            let schedule = TextPacingEngine.schedule(
                for: script, settings: .init(arc: .fullText, speed: .natural))
            let joined = schedule.map(\.text).joined(separator: " ").lowercased()
            for phrase in Self.eyesClosurePhrases {
                #expect(!joined.contains(phrase),
                        "\(script.id) fullText contains '\(phrase)'")
            }
        }
    }

    @Test func handoffScriptsEndOnATriggerSegment() {
        for script in TranceScriptLibrary.loadAll(inDirectory: Self.scriptsDir)
            where script.supportedArcs.contains(.handoff) {
            let hasTrigger = script.segments.contains {
                ($0.triggersHandoff == true) &&
                ($0.arcs?.contains(.handoff) ?? true)
            }
            #expect(hasTrigger, "\(script.id) handoff arc has no trigger segment")
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/BundledTranceScriptTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Ilumionate/TextTrance/Scripts IlumionateTests/TextTrance/BundledTranceScriptTests.swift Ilumionate.xcodeproj
git commit -m "feat(text-trance): bundled starter scripts + content regression tests"
```

---

## Task 7: Layer protocols + conformances

**Files:**
- Create: `Ilumionate/TextTrance/TextTranceLayers.swift`
- Test: `IlumionateTests/TextTrance/TextTranceLayerMocks.swift` (test support only — no `@Test` yet)

- [ ] **Step 1: Write the protocols + conformances**

```swift
//  TextTranceLayers.swift
//  Ilumionate
//
//  Minimal control surfaces over the existing light and audio engines so the
//  session coordinator depends on protocols (testable with mocks) rather than
//  the concrete CADisplayLink / AVAudioEngine classes.

import Foundation

@MainActor
protocol LightLayerControlling: AnyObject {
    func start()
    func stop()
}

@MainActor
protocol AudioLayerControlling: AnyObject {
    func start()
    func stop()
    func syncBeatFrequency(to frequency: Double)
}

extension FlashController: LightLayerControlling {}

extension BinauralBeatsEngine: AudioLayerControlling {}
```

> `FlashController` already has `start()`/`stop()`; `BinauralBeatsEngine` already has `start()`/`stop()`/`syncBeatFrequency(to:)`. These extensions only declare conformance.

- [ ] **Step 2: Write the test mocks**

```swift
//  TextTranceLayerMocks.swift
//  IlumionateTests

import Foundation
@testable import Ilumionate

@MainActor
final class MockLightLayer: LightLayerControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
}

@MainActor
final class MockAudioLayer: AudioLayerControlling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastBeatFrequency: Double?
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func syncBeatFrequency(to frequency: Double) { lastBeatFrequency = frequency }
}
```

- [ ] **Step 3: Build to verify conformances compile**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build-for-testing -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceLayers.swift IlumionateTests/TextTrance/TextTranceLayerMocks.swift
git commit -m "feat(text-trance): light/audio layer protocols + test mocks"
```

---

## Task 8: TextTranceSession coordinator

**Files:**
- Create: `Ilumionate/TextTrance/TextTranceSession.swift`
- Test: `IlumionateTests/TextTrance/TextTranceSessionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
//  TextTranceSessionTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct TextTranceSessionTests {

    private func handoffScript() -> TranceScript {
        TranceScript(
            schemaVersion: 1, id: "h", title: "H", theme: .relaxation,
            supportedArcs: [.fullText, .handoff], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [
                TranceScriptSegment(phase: .induction, text: "one two",
                    pacing: SegmentPacing(baseWPM: 600), arcs: nil, triggersHandoff: nil),
                TranceScriptSegment(phase: .emergence, text: "close",
                    pacing: SegmentPacing(baseWPM: 600), arcs: [.handoff], triggersHandoff: true)
            ])
    }

    // Immediate sleep so the playback loop runs synchronously in tests.
    private let noSleep: @Sendable (Duration) async -> Void = { _ in }

    @Test func handoffArcStartsLightAfterReadingAndStopsAllAtEnd() async {
        let light = MockLightLayer()
        let audio = MockAudioLayer()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .handoff, speed: .natural,
                lightEnabled: true, binauralEnabled: true,
                beatFrequency: 10, postHandoffDuration: 1),
            light: light, audio: audio, sleep: noSleep)

        await session.begin()

        #expect(audio.startCount == 1)
        #expect(audio.lastBeatFrequency == 10)
        #expect(light.startCount == 1)       // engaged for the handoff tail
        #expect(light.stopCount == 1)
        #expect(audio.stopCount == 1)
        #expect(session.isComplete)
    }

    @Test func fullTextArcNeverStartsLight() async {
        let light = MockLightLayer()
        let audio = MockAudioLayer()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speed: .natural,
                lightEnabled: true, binauralEnabled: true,
                beatFrequency: 10, postHandoffDuration: 1),
            light: light, audio: audio, sleep: noSleep)

        await session.begin()

        #expect(light.startCount == 0)
        #expect(audio.stopCount == 1)
        #expect(session.isComplete)
    }

    @Test func disabledBinauralNeverStartsAudio() async {
        let light = MockLightLayer()
        let audio = MockAudioLayer()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speed: .natural,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 1),
            light: light, audio: audio, sleep: noSleep)

        await session.begin()
        #expect(audio.startCount == 0)
    }

    @Test func lastReadWordIsExposed() async {
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speed: .natural,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: noSleep)
        await session.begin()
        // fullText reads "one two close"? "close" is handoff-only -> excluded.
        #expect(session.currentWord == "two")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/TextTranceSessionTests`
Expected: FAIL — `cannot find 'TextTranceSession' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
//  TextTranceSession.swift
//  Ilumionate
//
//  Observable coordinator for a running Text Trance session. Drives the RSVP
//  word stream from the pacing schedule and orchestrates the optional light /
//  binaural layers across the arc (reading -> optional handoff tail -> done).

import Foundation

/// Everything the player needs to run one session.
struct TextTranceSessionSettings: Sendable {
    let arc: ScriptArc
    let speed: TextPacingSettings.Speed
    let lightEnabled: Bool
    let binauralEnabled: Bool
    let beatFrequency: Double
    let postHandoffDuration: TimeInterval
}

@MainActor
@Observable
final class TextTranceSession {

    // Rendered state
    private(set) var currentWord: String = ""
    private(set) var currentPivotIndex: Int = 0
    private(set) var currentPhase: TrancePhase = .preTalk
    private(set) var isReading = false
    private(set) var lightActive = false
    private(set) var isComplete = false

    let script: TranceScript
    let settings: TextTranceSessionSettings

    private let light: LightLayerControlling?
    private let audio: AudioLayerControlling?
    private let sleep: @Sendable (Duration) async -> Void
    private var cancelled = false

    init(script: TranceScript,
         settings: TextTranceSessionSettings,
         light: LightLayerControlling?,
         audio: AudioLayerControlling?,
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.script = script
        self.settings = settings
        self.light = light
        self.audio = audio
        self.sleep = sleep
    }

    /// Run the full session to completion (or until `end()` cancels it).
    func begin() async {
        let pacing = TextPacingSettings(arc: settings.arc, speed: settings.speed)
        let schedule = TextPacingEngine.schedule(for: script, settings: pacing)

        if settings.binauralEnabled, let audio {
            audio.syncBeatFrequency(to: settings.beatFrequency)
            audio.start()
        }

        isReading = true
        for word in schedule {
            if cancelled { break }
            currentWord = word.text
            currentPivotIndex = word.pivotIndex
            currentPhase = word.phase
            await sleep(.seconds(word.duration))
        }
        isReading = false

        if settings.arc == .handoff, !cancelled {
            if settings.lightEnabled, let light {
                light.start()
                lightActive = true
            }
            await sleep(.seconds(settings.postHandoffDuration))
            light?.stop()
            lightActive = false
        }

        audio?.stop()
        isComplete = true
    }

    /// Stop everything immediately (user tap-and-hold to end).
    func end() {
        cancelled = true
        light?.stop()
        audio?.stop()
        lightActive = false
        isReading = false
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:IlumionateTests/TextTranceSessionTests`
Expected: PASS (all 4 cases).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceSession.swift IlumionateTests/TextTrance/TextTranceSessionTests.swift
git commit -m "feat(text-trance): session coordinator with arc/layer orchestration"
```

---

## Task 9: TextTrancePlayerView (ORP word rendering)

**Files:**
- Create: `Ilumionate/TextTrance/TextTrancePlayerView.swift`

> UI task — verified by build + Xcode Preview rather than unit tests (rendering is visual; the logic it depends on is already covered).

- [ ] **Step 1: Implement the player view**

```swift
//  TextTrancePlayerView.swift
//  Ilumionate
//
//  Control-free RSVP player. Renders the current word with its pivot letter
//  aligned to a fixed horizontal anchor and tinted with the Trance accent.
//  Tap-and-hold to end (no visible controls, to avoid breaking trance).

import SwiftUI

struct TextTrancePlayerView: View {
    @State private var session: TextTranceSession
    @Environment(\.dismiss) private var dismiss

    @State private var holdProgress: Double = 0
    @State private var backgroundPulse = false

    init(session: TextTranceSession) {
        _session = State(initialValue: session)
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            // Subtle decorative background pulse (not the entrainment light layer).
            RadialGradient(
                colors: [Color.roseGold.opacity(backgroundPulse ? 0.22 : 0.08), .clear],
                center: .center, startRadius: 20, endRadius: 420)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true),
                           value: backgroundPulse)

            if session.isReading {
                AnchoredWord(text: session.currentWord, pivot: session.currentPivotIndex)
                    .transition(.opacity)
            } else if session.lightActive {
                Text("…")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.textSecondary)
            }

            if holdProgress > 0 {
                VStack {
                    Spacer()
                    ProgressView(value: holdProgress)
                        .tint(Color.roseGold)
                        .padding(.horizontal, 60)
                        .padding(.bottom, 40)
                }
            }
        }
        .contentShape(.rect)
        .gesture(endHoldGesture)
        .task {
            backgroundPulse = true
            await session.begin()
            if session.isComplete { dismiss() }
        }
        .onChange(of: session.isComplete) { _, done in
            if done { dismiss() }
        }
        .statusBarHidden()
    }

    private var endHoldGesture: some Gesture {
        LongPressGesture(minimumDuration: 1.2)
            .onChanged { _ in withAnimation { holdProgress = 1 } }
            .onEnded { _ in
                session.end()
                dismiss()
            }
    }
}

/// One word laid out so its pivot letter sits on a fixed center anchor.
private struct AnchoredWord: View {
    let text: String
    let pivot: Int

    var body: some View {
        let chars = Array(text)
        let safePivot = min(max(pivot, 0), max(chars.count - 1, 0))
        return HStack(spacing: 0) {
            ForEach(chars.enumerated(), id: \.offset) { index, char in
                Text(String(char))
                    .foregroundStyle(index == safePivot ? Color.roseGold : Color.textPrimary)
            }
        }
        .font(.system(size: 34, weight: .regular, design: .serif))
        .monospaced()
        // Shift so the pivot letter is centered: (pivot + 0.5) chars left of center.
        .alignmentGuide(HorizontalAlignment.center) { d in
            d[.leading] + charWidth * (Double(safePivot) + 0.5)
        }
        .frame(maxWidth: .infinity)
    }

    // Monospaced 34pt serif advance width (approx); pivot alignment only needs consistency.
    private var charWidth: Double { 20 }
}

#Preview {
    let script = TranceScript(
        schemaVersion: 1, id: "p", title: "Preview", theme: .relaxation,
        supportedArcs: [.fullText], language: "en",
        source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
        segments: [TranceScriptSegment(phase: .induction,
            text: "drifting softly downward now",
            pacing: SegmentPacing(baseWPM: 60), arcs: nil, triggersHandoff: nil)])
    let session = TextTranceSession(
        script: script,
        settings: TextTranceSessionSettings(arc: .fullText, speed: .slow,
            lightEnabled: false, binauralEnabled: false,
            beatFrequency: 10, postHandoffDuration: 0),
        light: nil, audio: nil)
    return TextTrancePlayerView(session: session)
}
```

> The `charWidth` constant gives a consistent pivot alignment for a monospaced font. If visual testing shows drift, replace the fixed constant by measuring with `TextRenderer`/`ImageRenderer`; for M1 a constant is sufficient because the font is monospaced.

- [ ] **Step 2: Build + render preview**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED. Open the file in Xcode and confirm the `#Preview` renders a word with one rose-gold pivot letter at center.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TextTrance/TextTrancePlayerView.swift
git commit -m "feat(text-trance): ORP-anchored RSVP player view"
```

---

## Task 10: TextTranceSetupView

**Files:**
- Create: `Ilumionate/TextTrance/TextTranceSetupView.swift`

- [ ] **Step 1: Implement the setup view**

```swift
//  TextTranceSetupView.swift
//  Ilumionate
//
//  Configure a session for the chosen script: arc, optional layers, speed.
//  Builds a TextTranceSession and pushes the player.

import SwiftUI

struct TextTranceSetupView: View {
    let script: TranceScript

    @State private var arc: ScriptArc
    @State private var speed: TextPacingSettings.Speed = .natural
    @State private var lightEnabled = true
    @State private var binauralEnabled = false
    @State private var startPlayer = false

    init(script: TranceScript) {
        self.script = script
        _arc = State(initialValue: script.supportedArcs.first ?? .fullText)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.section) {
                arcCard
                layersCard
                speedCard
            }
            .padding(TranceSpacing.screen)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Begin", systemImage: "play.fill") { startPlayer = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.roseGold)
                .controlSize(.large)
                .padding(TranceSpacing.screen)
        }
        .navigationDestination(isPresented: $startPlayer) {
            TextTrancePlayerView(session: makeSession())
                .navigationBarBackButtonHidden()
        }
    }

    private var arcCard: some View {
        GlassCard(label: "Arc") {
            Picker("Arc", selection: $arc) {
                ForEach(script.supportedArcs) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var layersCard: some View {
        GlassCard(label: "Layers") {
            VStack(spacing: TranceSpacing.list) {
                Toggle("Binaural beats", isOn: $binauralEnabled)
                Text("Requires headphones")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Light pulse is only meaningful for the handoff tail in M1.
                if arc == .handoff {
                    Toggle("Light pulse after handoff", isOn: $lightEnabled)
                }
            }
            .tint(Color.roseGold)
        }
    }

    private var speedCard: some View {
        GlassCard(label: "Reading speed") {
            Picker("Speed", selection: $speed) {
                ForEach(TextPacingSettings.Speed.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func makeSession() -> TextTranceSession {
        TextTranceSession(
            script: script,
            settings: TextTranceSessionSettings(
                arc: arc,
                speed: speed,
                lightEnabled: arc == .handoff && lightEnabled,
                binauralEnabled: binauralEnabled,
                beatFrequency: 10,
                postHandoffDuration: 600),
            light: FlashController(frequency: 10, intensity: 0.7, pattern: .sine),
            audio: BinauralBeatsEngine())
    }
}
```

> `GlassCard`, `TranceSpacing`, `TranceTypography`, and `Color.roseGold`/`.bgPrimary`/`.textSecondary` are existing design-system symbols (see `MindMachineView+Binaural.swift`, `TranceTabBar.swift`). `MindMachineModel.LightPattern.sine` is the existing pattern enum used by `FlashController.init`.

- [ ] **Step 2: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceSetupView.swift
git commit -m "feat(text-trance): session setup screen"
```

---

## Task 11: TextTranceLibraryView

**Files:**
- Create: `Ilumionate/TextTrance/TextTranceLibraryView.swift`

- [ ] **Step 1: Implement the library view**

```swift
//  TextTranceLibraryView.swift
//  Ilumionate
//
//  Script picker: theme filter + cards. Tapping a card pushes setup.

import SwiftUI

struct TextTranceLibraryView: View {
    @State private var scripts: [TranceScript] = []
    @State private var themeFilter: ScriptTheme?

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.section) {
                themeChips
                ForEach(filteredScripts) { script in
                    NavigationLink(value: script.id) {
                        ScriptCard(script: script)
                    }
                    .buttonStyle(.plain)
                }
                generatePlaceholder
            }
            .padding(TranceSpacing.screen)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Text Trance")
        .navigationDestination(for: String.self) { id in
            if let script = scripts.first(where: { $0.id == id }) {
                TextTranceSetupView(script: script)
            }
        }
        .task {
            if scripts.isEmpty { scripts = TranceScriptLibrary.bundled() }
        }
    }

    private var filteredScripts: [TranceScript] {
        guard let themeFilter else { return scripts }
        return scripts.filter { $0.theme == themeFilter }
    }

    private var themeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: TranceSpacing.list) {
                FilterChip(title: "All", isOn: themeFilter == nil) { themeFilter = nil }
                ForEach(ScriptTheme.allCases) { theme in
                    FilterChip(title: theme.displayName, isOn: themeFilter == theme) {
                        themeFilter = theme
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var generatePlaceholder: some View {
        GlassCard(label: nil) {
            HStack {
                Image(systemName: "sparkles")
                VStack(alignment: .leading) {
                    Text("Generate new script")
                        .font(TranceTypography.body)
                    Text("Coming soon")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .foregroundStyle(Color.textSecondary)
        }
        .opacity(0.6)
    }
}

private struct ScriptCard: View {
    let script: TranceScript
    var body: some View {
        GlassCard(label: nil) {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Text(script.title).font(TranceTypography.title)
                Text(script.theme.displayName)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: 6) {
                    ForEach(script.supportedArcs) { arc in
                        TagChip(text: arc.displayName)
                    }
                    if script.source.reviewed { TagChip(text: "Reviewed") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TagChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(TranceTypography.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.roseGold.opacity(0.18), in: .capsule)
            .foregroundStyle(Color.roseGold)
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(TranceTypography.caption)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(isOn ? Color.roseGold.opacity(0.22) : Color.glassBorder.opacity(0.4),
                        in: .capsule)
            .foregroundStyle(isOn ? Color.roseGold : Color.textSecondary)
            .buttonStyle(.plain)
    }
}
```

> Confirm `GlassCard` accepts a `label: nil` (optional) — if its initializer requires a non-optional label, pass `label: ""` or use the existing label-less initializer. `TranceTypography.title` is the existing heading style (see usages in `MindMachineView`). `Color.glassBorder` is used in `TranceTabBar.swift`.

- [ ] **Step 2: Build**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED. (If `GlassCard(label: nil)` fails to compile, adjust to the existing initializer signature and rebuild.)

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceLibraryView.swift
git commit -m "feat(text-trance): script library picker view"
```

---

## Task 12: Root view + tab integration

**Files:**
- Create: `Ilumionate/TextTrance/TextTranceRootView.swift`
- Modify: `Ilumionate/TranceTabBar.swift` (add `.read` case)
- Modify: `Ilumionate/ContentView.swift:50-78` (route `.read`)

- [ ] **Step 1: Create the root view**

```swift
//  TextTranceRootView.swift
//  Ilumionate
//
//  NavigationStack host for the Text Trance tab.

import SwiftUI

struct TextTranceRootView: View {
    var body: some View {
        NavigationStack {
            TextTranceLibraryView()
        }
    }
}

#Preview { TextTranceRootView() }
```

- [ ] **Step 2: Add the `.read` tab case**

In `Ilumionate/TranceTabBar.swift`, extend the `TranceTab` enum:

```swift
enum TranceTab: String, CaseIterable {
    case home    = "home"
    case signal  = "signal"
    case library = "library"
    case read    = "read"
    case create  = "create"

    var title: String {
        switch self {
        case .home:    "Home"
        case .signal:  "Signal"
        case .library: "Library"
        case .read:    "Read"
        case .create:  "Create"
        }
    }

    var sfSymbol: String {
        switch self {
        case .home:    "house.fill"
        case .signal:  "rectangle.stack.fill"
        case .library: "books.vertical.fill"
        case .read:    "text.aligncenter"
        case .create:  "lightbulb.fill"
        }
    }
}
```

- [ ] **Step 3: Route the tab in ContentView**

In `Ilumionate/ContentView.swift`, inside the tab-switch block (currently around lines 50-78), add a branch for `.read` following the existing pattern (each branch carries `.transition(.opacity)`):

```swift
                } else if selectedTab == .read {
                    TextTranceRootView()
                        .transition(.opacity)
                } else if selectedTab == .create {
```

(Insert the `.read` branch immediately before the existing `.create` branch; keep the existing `.library` branch above it.)

- [ ] **Step 4: Build + launch to confirm the tab works end to end**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

Manually (or via the ios-simulator skill): launch the app, tap the new **Read** tab, confirm the three script cards appear, tap **Deep Drift**, choose an arc + speed, tap **Begin**, and confirm words stream with a rose-gold pivot letter; tap-and-hold to end.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceRootView.swift Ilumionate/TranceTabBar.swift Ilumionate/ContentView.swift
git commit -m "feat(text-trance): root view + Read tab integration"
```

---

## Task 13: Full suite + final verification

- [ ] **Step 1: Run the entire Text Trance test suite**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:IlumionateTests/TranceScriptDecodingTests \
  -only-testing:IlumionateTests/ORPCalculatorTests \
  -only-testing:IlumionateTests/WordTokenizerTests \
  -only-testing:IlumionateTests/TextPacingEngineTests \
  -only-testing:IlumionateTests/TranceScriptLibraryTests \
  -only-testing:IlumionateTests/BundledTranceScriptTests \
  -only-testing:IlumionateTests/TextTranceSessionTests
```
Expected: all tests PASS.

- [ ] **Step 2: Run the full project test suite to confirm no regressions**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: existing suite still green; new tests included.

- [ ] **Step 3: Confirm no `print()` debugging slipped in**

Run: `grep -rn "print(" Ilumionate/TextTrance/`
Expected: no output (use `Log.*` if logging is needed).

- [ ] **Step 4: Final commit (if any cleanup was needed)**

```bash
git add -A
git commit -m "chore(text-trance): M1 verification pass"
```

---

## Self-Review

**Spec coverage:**
- Three composable layers (light/binaural/reading) → Tasks 7, 8 (light + audio orchestration; reading is the engine). Note: concurrent reading-time light deferred to M2 per Deviation 3.
- Hybrid sourcing (bundled v1, AI later) → Task 6 (bundled), Task 11 greyed-out "Generate" placeholder. AI generation = M3 (out of scope).
- RSVP base + entrainment-lock → RSVP in Tasks 4/9; entrainment-lock = M2 (out of scope, Deviation 3).
- ORP pivot letter → Tasks 2, 9.
- Dedicated screen/tab → Tasks 11, 12.
- Per-session arc (fullText/handoff) → Tasks 1, 4, 8, 10.
- v1 themes (relax/sleep/focus/suggestion) → `ScriptTheme` (Task 1); Task 6 ships relaxation/sleep/focus. *Gap:* no `suggestion`-themed bundled script in Task 6. **Resolution:** intentional for M1 — self-suggestion content carries the heaviest review burden (spec §8) and is best authored deliberately; the theme + filter exist so it slots in without code change. Flag to the user during execution.
- Script JSON schema → Task 1 matches spec §4 except `handoffCue` phase replaced by `triggersHandoff` flag (Deviation 1).
- Runtime pacing engine → Task 4.
- Error handling (malformed skipped, arc not offered, binaural failure) → Task 5 (skip+log); arc filtering Task 10 (only `supportedArcs` shown); binaural failure handled inside existing `BinauralBeatsEngine.start()` (logs, no crash).
- Testing strategy (engine/library/session/bundled/safety) → Tasks 2-8; safety (photosensitivity) = M2.

**Placeholder scan:** No "TBD"/"implement later". Every code step is complete. UI tasks note the two existing-symbol assumptions to verify at build time (`GlassCard(label:)` optionality, `TranceTypography.title`) with explicit fallbacks.

**Type consistency:** `TextTranceSessionSettings` (session-level: includes layer toggles, beat/handoff) vs `TextPacingSettings` (pacing-only: arc + speed) are distinct by design; the session derives the latter from the former in `begin()`. `ScriptArc`, `TrancePhase`, `PacedWord`, `SegmentPacing` names are consistent across Tasks 1, 4, 8. `light.start()/stop()` and `audio.start()/stop()/syncBeatFrequency(to:)` match the protocols (Task 7) and existing engine APIs.

**Outstanding execution-time confirmations** (call out, don't block):
1. Simulator name — adjust `iPhone 16` to an installed simulator. **Resolved during execution: no iPhone 16 exists; use `platform=iOS Simulator,name=iPhone 17` (iOS 26.2) in all commands.**
2. `GlassCard` initializer label optionality.
3. Whether a `suggestion`-themed starter script should be authored in M1 or deferred.

---

## Read Tab = Unified Reading Hub (architecture note, added 2026-06-11)

Per product direction, the **Read tab is the single home for everything Text Trance**:
- **Bundled scripts** we author (Tasks 1–13).
- **External script discovery** — curated source lists + user-added URLs — via the **Reading Sources** companion feature (Part B below). This is **link-only**: it opens external sites in the browser. It does **not** fetch, scrape, parse, cache, or import third-party page text. Actual text import into the RSVP reader is a separate future milestone requiring a rights/import design and App Store compliance review (see handoff `docs/superpowers/handoffs/2026-06-11-reading-sources-handoff.md`).
- **Session controls** — reading speed, audio/binaural, light/flash — live in the per-session Setup screen (Task 10) reached from this tab.

The Text Trance core (Tasks 5–13) is built first; the Read tab initially shows the bundled-script library. The Reading Sources entry point is wired in Part B after the core is green, to keep core tasks independent of the (currently untracked) Reading Sources files.

---

## Part B: Reading Sources Integration (deferred — execute AFTER Task 13)

**Status:** The Reading Sources feature is **already implemented** in the working tree (untracked) from a parallel session — model, store, directory view, tests, and a Library-tab entry point — documented in `docs/superpowers/handoffs/2026-06-11-reading-sources-handoff.md`. Part B brings that work into committed history under the project's verify+review flow and connects it to the Read tab. It does **not** re-implement it.

Existing files (untracked / modified):
- `Ilumionate/TextTrance/ReadingSource.swift` — `ReadingSource`, `ReadingSourceCatalog.curatedSources` (6 link-only sources), category/license/import-policy/content-rating enums. Metadata-only; stores no page content.
- `Ilumionate/TextTrance/ReadingSourceStore.swift` — `@Observable ReadingSourceStore.shared`; curated + user-added aggregation; `UserDefaults` persistence (key `readingSourceCustomLinks`); URL normalization; HTTP/HTTPS-only validation; duplicate rejection; delete/reset.
- `Ilumionate/TextTrance/ReadingSourceDirectoryView.swift` — searchable directory, category chips, source cards, external `openURL`, Add-Source sheet.
- `IlumionateTests/TextTrance/ReadingSourceStoreTests.swift` — curated-shape, HTTP/HTTPS, no-`adultOnly`-by-default, normalization/persistence, duplicate rejection, invalid-URL, delete-isolation.
- `Ilumionate/LibraryView.swift` (modified) — adds a "Reading Sources" row → `ReadingSourceDirectoryView`.

**Link-only policy (must hold for M1):** no background fetch; no parse/cache/summarize/transform/save of website text; user-added links are private bookmarks (`linkOnly`, `licenseKind == .userProvided`); no `adultOnly` sources in the default catalog. Release gate language: a reviewer can describe the shipped feature as "a curated external links directory plus user bookmarks" without caveats.

### Task B1: Verify + review + commit the existing Reading Sources files

**Files (commit as-is unless review finds issues):** the five files listed above.

- [ ] **Step 1: Independently verify the build** (controller runs this, not a self-report)

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/ReadingSourceStoreTests 2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED|error:"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Spec/policy compliance review** — dispatch a reviewer to confirm against the handoff: model is metadata-only (no content storage), store is HTTP/HTTPS-only with duplicate rejection, no `adultOnly` curated source ships, and the view only opens external URLs (no fetch/parse). Verify by reading code, not the handoff.

- [ ] **Step 3: Code-quality review** — `ReadingSource.swift`, `ReadingSourceStore.swift`, `ReadingSourceDirectoryView.swift` for single-responsibility, naming, error handling, file size; confirm `LibraryView.swift` change is minimal and scoped.

- [ ] **Step 4: Commit** (only these five files; never the unrelated dirty items `xcschememanagement.plist`, `lightMapCreationTool`):
```bash
git add Ilumionate/TextTrance/ReadingSource.swift \
        Ilumionate/TextTrance/ReadingSourceStore.swift \
        Ilumionate/TextTrance/ReadingSourceDirectoryView.swift \
        IlumionateTests/TextTrance/ReadingSourceStoreTests.swift \
        Ilumionate/LibraryView.swift
git commit -m "feat(text-trance): reading sources directory (link-only external discovery)"
```

### Task B2: Wire the Reading Sources entry point into the Read tab

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceLibraryView.swift` (from Task 11)

- [ ] **Step 1:** Add a "Find more scripts online" row/section in `TextTranceLibraryView` that navigates to `ReadingSourceDirectoryView` (reuse the existing view; do not duplicate). Use the existing `GlassCard`/`TranceSpacing`/`TranceTypography`/color system, matching the Task 11 styling. Include one-line copy clarifying that links open external websites and content/rights vary.

- [ ] **Step 2:** Build and verify the Read tab → Reading Sources navigation works (controller runs the build; manual sim check of the path). Keep the Library-tab row in place (both entry points coexist).

- [ ] **Step 3: Commit:**
```bash
git add Ilumionate/TextTrance/TextTranceLibraryView.swift
git commit -m "feat(text-trance): surface Reading Sources from the Read tab"
```

### Task B3: Capture release gates (documentation only)

- [ ] Copy the handoff's production-readiness gates (curated-source review, App Store compliance for external content + no medical claims + adult-content exclusion, accessibility/VoiceOver, expanded store tests, analytics/privacy on custom URLs) into a tracked checklist at `docs/superpowers/specs/reading-sources-release-gates.md`. These are **pre-ship gates**, not M1 code tasks. No code changes. Commit the doc.

**Part B explicitly out of scope (future milestone):** importing/extracting script text from any source into the RSVP reader; in-app web views for third-party content; adult-content sources/gating. Import requires its own approved spec + rights review per handoff §10.
