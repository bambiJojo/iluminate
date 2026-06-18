# Punctuation-Driven Reader Word Stream — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strip punctuation from the Text Trance RSVP reader's displayed glyphs and promote it into control signals for word timing, motion (breath/drift fades), hyphen-splitting, and an opt-in subliminal fast-flash layer.

**Architecture:** A deterministic, pure transform. `WordTokenizer` produces clean display tokens carrying a `PauseKind` and an authored-subliminal flag; `TextPacingEngine.schedule` resolves the subliminal layer (authored marks first, lexicon fallback, feature toggle) and maps everything to timed `PacedWord`s, preserving the existing `startTime`/`duration` cumulative-timeline contract. `TextTranceSession` publishes the per-word fade/duration; `TextTrancePlayerView` animates opacity; `TextTranceSetupView` exposes the subliminal toggle + speed.

**Tech Stack:** Swift 6.2, SwiftUI, `@Observable`, Swift Testing (`import Testing`), Xcode project (`Ilumionate.xcodeproj`).

**Spec:** `docs/superpowers/specs/2026-06-17-reader-punctuation-driven-stream-design.md`

---

## Conventions used in every task

**Test run command** (Swift Testing via xcodebuild). Adjust the simulator name to one installed locally (project default is iPhone 17):

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/<SuiteName>
```

Full suite (final verification):

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

**Build-only command** (for UI tasks with no unit test):

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build
```

**Target membership note:** New `.swift` files added under `Ilumionate/TextTrance/` and `IlumionateTests/TextTrance/` are picked up automatically by the project's file-system synchronized groups. After adding a new file, if a build reports "cannot find … in scope", confirm the file landed inside the synchronized folder (no manual Xcode membership step should be required).

---

## File Structure

**Modified:**
- `Ilumionate/TextTrance/WordTokenizer.swift` — new `WordToken` (`text`, `pause`, `isSubliminal`), `PauseKind`, full tokenizer pipeline (drops `endsSentence`).
- `Ilumionate/TextTrance/TextPacingEngine.swift` — `FadeKind`, extended `PacedWord`, pause→hold mapping, subliminal resolution, `SubliminalSpeed` + settings fields.
- `Ilumionate/TextTrance/TextTranceSession.swift` — thread subliminal settings into `TextPacingSettings`; publish `currentFade` + `currentDuration`.
- `Ilumionate/TextTrance/TextTrancePlayerView.swift` — opacity reset + breath/drift fade animation.
- `Ilumionate/TextTrance/TextTranceSetupView.swift` — Subliminal card; thread settings into `makeSession`.
- `IlumionateTests/TextTrance/WordTokenizerTests.swift` — replace `endsSentence` tests with pause/strip/split/mark tests.

**Created:**
- `Ilumionate/TextTrance/SubliminalLexicon.swift` — suggestion-word set + `contains`.
- `IlumionateTests/TextTrance/TextPacingEngineTests.swift` — schedule mapping + subliminal resolution tests.

---

## Task 1: Extend `PacedWord` with `fade` + `isSubliminal` (compile-safe defaults)

Adds the new fields first so the type is stable, with an explicit init that defaults them — existing `PacedWord(...)` call sites in `TextTranceWordSizingTests.swift` keep compiling.

**Files:**
- Modify: `Ilumionate/TextTrance/TextPacingEngine.swift:11-17` (the `PacedWord` struct) and add `FadeKind`.

- [ ] **Step 1: Add `FadeKind` and extend `PacedWord`**

Replace the existing `PacedWord` struct (lines 11-17) with:

```swift
/// How a word leaves the screen — drives the breath/drift opacity fade.
enum FadeKind: Equatable, Sendable {
    case none
    case breath   // sentence-end: visible hold then fade
    case drift    // ellipsis: longest, slowest fade
}

/// One scheduled word ready to render.
struct PacedWord: Equatable, Sendable {
    let text: String
    let pivotIndex: Int
    let phase: TrancePhase
    let startTime: TimeInterval  // cumulative seconds from reading start
    let duration: TimeInterval   // how long this word is held
    let fade: FadeKind
    let isSubliminal: Bool

    init(text: String,
         pivotIndex: Int,
         phase: TrancePhase,
         startTime: TimeInterval,
         duration: TimeInterval,
         fade: FadeKind = .none,
         isSubliminal: Bool = false) {
        self.text = text
        self.pivotIndex = pivotIndex
        self.phase = phase
        self.startTime = startTime
        self.duration = duration
        self.fade = fade
        self.isSubliminal = isSubliminal
    }
}
```

- [ ] **Step 2: Update the existing `PacedWord` construction in `schedule`**

In `TextPacingEngine.schedule` the existing `result.append(PacedWord(...))` (around line 67) does not yet pass `fade`/`isSubliminal`; the defaults cover it, so no change is required here yet. Leave it as-is for this task.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build`
Expected: BUILD SUCCEEDED (existing word-sizing tests still reference the labeled init, which now resolves to the defaulted init).

- [ ] **Step 4: Run the word-sizing suite to confirm no regression**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/TextTranceWordSizingTests
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextPacingEngine.swift
git commit -m "feat(reader): add FadeKind and fade/isSubliminal to PacedWord"
```

---

## Task 2: Replace `WordToken`/tokenizer core + wire pause→hold in the engine

Coordinated breaking change: new `WordToken` (drops `endsSentence`) **and** the engine that consumes it, so the project compiles. This task covers the **basic** tokenizer (whitespace split, trailing-punctuation strip + classify) and the **pause→hold + fade** mapping. Hyphen/em-dash, authored marks, and quote/empty handling come in later tasks.

**Files:**
- Modify: `Ilumionate/TextTrance/WordTokenizer.swift` (full rewrite)
- Modify: `Ilumionate/TextTrance/TextPacingEngine.swift` (constants + `schedule` body)
- Modify: `IlumionateTests/TextTrance/WordTokenizerTests.swift` (replace `endsSentence` tests)

- [ ] **Step 1: Write the failing tokenizer tests**

Replace the entire contents of `IlumionateTests/TextTrance/WordTokenizerTests.swift` with:

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

    @Test func stripsTrailingPunctuationFromDisplay() {
        let tokens = WordTokenizer.tokenize("Rest now. Drift deeper")
        #expect(tokens.map(\.text) == ["Rest", "now", "Drift", "deeper"])
    }

    @Test func classifiesSentenceEndsAsBreath() {
        let tokens = WordTokenizer.tokenize("now. Ready? Yes!")
        #expect(tokens.map(\.pause) == [.breath, .breath, .breath])
    }

    @Test func classifiesEllipsisAsDrift() {
        let tokens = WordTokenizer.tokenize("deeper… and down...")
        #expect(tokens.map(\.pause) == [.drift, .none, .drift])
    }

    @Test func classifiesCommaSemicolonColonAsBrief() {
        let tokens = WordTokenizer.tokenize("slowly, softly; here:")
        #expect(tokens.map(\.pause) == [.brief, .brief, .brief])
    }

    @Test func plainWordsHaveNoPause() {
        let tokens = WordTokenizer.tokenize("drifting softly downward")
        #expect(tokens.allSatisfy { $0.pause == .none })
    }

    @Test func emptyStringYieldsNoTokens() {
        #expect(WordTokenizer.tokenize("   ").isEmpty)
    }
}
```

- [ ] **Step 2: Run tokenizer tests to verify they fail**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/WordTokenizerTests
```
Expected: FAIL (compile error: `WordToken` has no member `pause`; `PauseKind` undefined).

- [ ] **Step 3: Rewrite `WordTokenizer.swift`**

Replace the entire contents of `Ilumionate/TextTrance/WordTokenizer.swift` with:

```swift
//  WordTokenizer.swift
//  Ilumionate
//
//  Splits segment text into display tokens. Punctuation is removed from the
//  displayed glyphs and promoted into control signals: a trailing-punctuation
//  PauseKind, and (later) an authored-subliminal flag.

import Foundation

/// Strength-ordered so pauses can be merged with `max`. Raw values are the rank.
enum PauseKind: Int, Equatable, Sendable {
    case none = 0
    case brief      // , ; :
    case medium     // em-dash
    case breath     // . ! ?
    case drift      // …
}

struct WordToken: Equatable, Sendable {
    let text: String          // display glyphs only — punctuation stripped
    let pause: PauseKind      // derived from trailing punctuation
    let isSubliminal: Bool    // authored [[ ]] mark (engine resolves the rest)
}

enum WordTokenizer {

    static func tokenize(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        for piece in text.split(whereSeparator: \.isWhitespace) {
            appendWord(String(piece), into: &tokens)
        }
        return tokens
    }

    /// Strip a single whitespace piece into a display token (basic version:
    /// trailing-punctuation strip + classify; subliminal always false for now).
    private static func appendWord(_ piece: String, into tokens: inout [WordToken]) {
        let cleaned = stripped(piece)
        guard !cleaned.display.isEmpty else { return }
        tokens.append(WordToken(text: cleaned.display,
                                pause: cleaned.pause,
                                isSubliminal: false))
    }

    private static let trailingMarks: [Character: PauseKind] = [
        ".": .breath, "!": .breath, "?": .breath, "…": .drift,
        ",": .brief, ";": .brief, ":": .brief
    ]

    /// Strip trailing punctuation; return display text + the strongest pause.
    private static func stripped(_ word: String) -> (display: String, pause: PauseKind) {
        var chars = Array(word)
        var pause: PauseKind = .none
        while let last = chars.last {
            // literal "..." → ellipsis/drift
            if last == ".", chars.count >= 3, chars.suffix(3).allSatisfy({ $0 == "." }) {
                pause = strongest(pause, .drift)
                chars.removeLast(3)
                continue
            }
            if let kind = trailingMarks[last] {
                pause = strongest(pause, kind)
                chars.removeLast()
            } else {
                break
            }
        }
        return (String(chars), pause)
    }

    static func strongest(_ a: PauseKind, _ b: PauseKind) -> PauseKind {
        a.rawValue >= b.rawValue ? a : b
    }
}
```

- [ ] **Step 4: Update `TextPacingEngine.schedule` to consume the new token**

In `Ilumionate/TextTrance/TextPacingEngine.swift`:

First, replace the constants block (the `defaultBaseWPM` / `sentenceHoldMultiplier` / `deepeningFloor` lines, ~44-50) with:

```swift
    /// WPM used when a segment omits an explicit pacing hint, before the
    /// depth-derived slowdown is applied.
    static let defaultBaseWPM: Double = 150
    /// Slowest depth factor (applied at max trance depth) for depth-derived pace.
    static let deepeningFloor: Double = 0.55

    // Pause hold multipliers on the segment's base word duration.
    static let briefHoldMultiplier:  Double = 1.6
    static let mediumHoldMultiplier: Double = 2.2
    static let breathHoldMultiplier: Double = 3.0
    static let driftHoldMultiplier:  Double = 4.5
```

Then replace the inner token loop in `schedule` (the `for token in WordTokenizer.tokenize(...)` block, ~63-75) with:

```swift
            for token in WordTokenizer.tokenize(segment.text) {
                let duration = baseDuration * holdMultiplier(token.pause)
                result.append(PacedWord(
                    text: token.text,
                    pivotIndex: ORPCalculator.pivotIndex(for: token.text),
                    phase: segment.phase,
                    startTime: cursor,
                    duration: duration,
                    fade: fadeKind(token.pause),
                    isSubliminal: false
                ))
                cursor += duration
            }
```

Finally, add these two helpers inside the `TextPacingEngine` enum (e.g. after `effectiveWPM`):

```swift
    static func holdMultiplier(_ pause: PauseKind) -> Double {
        switch pause {
        case .none:   return 1.0
        case .brief:  return briefHoldMultiplier
        case .medium: return mediumHoldMultiplier
        case .breath: return breathHoldMultiplier
        case .drift:  return driftHoldMultiplier
        }
    }

    static func fadeKind(_ pause: PauseKind) -> FadeKind {
        switch pause {
        case .breath: return .breath
        case .drift:  return .drift
        default:      return .none
        }
    }
```

- [ ] **Step 5: Run tokenizer tests to verify they pass**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/WordTokenizerTests
```
Expected: PASS (7 tests).

- [ ] **Step 6: Run the session + word-sizing suites to confirm no regression**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/TextTranceSessionTests \
  -only-testing:IlumionateTests/TextTranceWordSizingTests
```
Expected: PASS. (The session test `lastReadWordIsExposed` expects `"two"` — still correct, no trailing punctuation in that script.)

- [ ] **Step 7: Commit**

```bash
git add Ilumionate/TextTrance/WordTokenizer.swift Ilumionate/TextTrance/TextPacingEngine.swift IlumionateTests/TextTrance/WordTokenizerTests.swift
git commit -m "feat(reader): strip trailing punctuation into PauseKind; map pause to hold+fade"
```

---

## Task 3: Hyphen + em-dash splitting

Split hyphenated compounds into separate short words; an em-dash split assigns a `medium` pause to the **preceding** sub-word.

**Files:**
- Modify: `Ilumionate/TextTrance/WordTokenizer.swift`
- Modify: `IlumionateTests/TextTrance/WordTokenizerTests.swift`

- [ ] **Step 1: Add the failing tests**

Append these tests inside the `WordTokenizerTests` struct in `IlumionateTests/TextTrance/WordTokenizerTests.swift`:

```swift
    @Test func splitsHyphenatedCompoundIntoSeparateWords() {
        let tokens = WordTokenizer.tokenize("deeper-and-deeper now")
        #expect(tokens.map(\.text) == ["deeper", "and", "deeper", "now"])
    }

    @Test func trailingPunctuationRidesLastHyphenPiece() {
        let tokens = WordTokenizer.tokenize("you drift half-asleep.")
        #expect(tokens.map(\.text) == ["you", "drift", "half", "asleep"])
        #expect(tokens.last?.pause == .breath)
        #expect(tokens[2].pause == .none) // "half" carries no pause
    }

    @Test func emDashSplitGivesPrecedingWordMediumPause() {
        // "heavy—warm" → heavy (medium pause), warm
        let tokens = WordTokenizer.tokenize("hands heavy—warm still")
        #expect(tokens.map(\.text) == ["hands", "heavy", "warm", "still"])
        #expect(tokens[1].pause == .medium)
        #expect(tokens[2].pause == .none)
    }

    @Test func standaloneEmDashBecomesMediumPauseOnPreviousWord() {
        let tokens = WordTokenizer.tokenize("hands — heavy")
        #expect(tokens.map(\.text) == ["hands", "heavy"])
        #expect(tokens[0].pause == .medium)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/WordTokenizerTests
```
Expected: FAIL (`deeper-and-deeper` returns one token; em-dash not split).

- [ ] **Step 3: Implement hyphen/em-dash splitting**

In `Ilumionate/TextTrance/WordTokenizer.swift`, replace the `appendWord` method with the split-aware version below, and add the supporting `Segment` type, `splitOnHyphens`, and `mergePauseIntoPrevious` helper:

```swift
    /// Split a whitespace piece on hyphen / em-dash into display sub-words.
    private static func appendWord(_ piece: String, into tokens: inout [WordToken]) {
        for segment in splitOnHyphens(piece) {
            // An em-dash before this segment is a medium pause on the previous word.
            if segment.precededByEmDash { mergePauseIntoPrevious(.medium, &tokens) }

            let cleaned = stripped(segment.text)
            guard !cleaned.display.isEmpty else {
                // pure punctuation / empty: fold its pause into the previous word
                mergePauseIntoPrevious(cleaned.pause, &tokens)
                continue
            }
            tokens.append(WordToken(text: cleaned.display,
                                    pause: cleaned.pause,
                                    isSubliminal: false))
        }
    }

    private struct Segment { let text: String; let precededByEmDash: Bool }

    /// Split on "-" (U+002D) and "—" (U+2014), recording whether each segment
    /// was preceded by an em-dash so the previous word can take a medium pause.
    private static func splitOnHyphens(_ piece: String) -> [Segment] {
        var segments: [Segment] = []
        var current = ""
        var precededByEmDash = false
        for ch in piece {
            if ch == "-" || ch == "\u{2014}" {
                segments.append(Segment(text: current, precededByEmDash: precededByEmDash))
                current = ""
                precededByEmDash = (ch == "\u{2014}")
            } else {
                current.append(ch)
            }
        }
        segments.append(Segment(text: current, precededByEmDash: precededByEmDash))
        return segments
    }

    private static func mergePauseIntoPrevious(_ pause: PauseKind, _ tokens: inout [WordToken]) {
        guard pause != .none, let last = tokens.last else { return }
        tokens[tokens.count - 1] = WordToken(
            text: last.text,
            pause: strongest(last.pause, pause),
            isSubliminal: last.isSubliminal)
    }
```

> Note: this replaces the basic `appendWord` from Task 2. The `stripped` and `strongest` helpers from Task 2 stay unchanged.

- [ ] **Step 4: Run to verify all tokenizer tests pass**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/WordTokenizerTests
```
Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/WordTokenizer.swift IlumionateTests/TextTrance/WordTokenizerTests.swift
git commit -m "feat(reader): split hyphen/em-dash compounds; em-dash → medium pause"
```

---

## Task 4: Authored `[[ ]]` subliminal marks

Parse `[[word]]` (single) and `[[let go]]` (phrase) marks, set `isSubliminal` on those words, and strip the delimiters from display.

**Files:**
- Modify: `Ilumionate/TextTrance/WordTokenizer.swift`
- Modify: `IlumionateTests/TextTrance/WordTokenizerTests.swift`

- [ ] **Step 1: Add the failing tests**

Append inside `WordTokenizerTests`:

```swift
    @Test func authoredMarkFlagsSingleWordAndStripsDelimiters() {
        let tokens = WordTokenizer.tokenize("you [[relax]] now")
        #expect(tokens.map(\.text) == ["you", "relax", "now"])
        #expect(tokens.map(\.isSubliminal) == [false, true, false])
    }

    @Test func authoredMarkFlagsMultiWordPhrase() {
        let tokens = WordTokenizer.tokenize("just [[let go]] completely")
        #expect(tokens.map(\.text) == ["just", "let", "go", "completely"])
        #expect(tokens.map(\.isSubliminal) == [false, true, true, false])
    }

    @Test func authoredMarkCoexistsWithTrailingPunctuation() {
        let tokens = WordTokenizer.tokenize("and [[deeper]].")
        #expect(tokens.map(\.text) == ["and", "deeper"])
        #expect(tokens.last?.isSubliminal == true)
        #expect(tokens.last?.pause == .breath)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/WordTokenizerTests
```
Expected: FAIL (`[[relax]]` kept literally, `isSubliminal` always false).

- [ ] **Step 3: Implement mark parsing**

In `Ilumionate/TextTrance/WordTokenizer.swift`, replace `tokenize` and `appendWord` so the whitespace loop tracks an "inside marks" state and threads the subliminal flag through:

```swift
    static func tokenize(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var insideMark = false
        for piece in text.split(whereSeparator: \.isWhitespace) {
            var word = String(piece)
            let opens = word.contains("[[")
            let closes = word.contains("]]")
            word = word.replacing("[[", with: "").replacing("]]", with: "")
            let subliminal = insideMark || opens
            if opens { insideMark = true }
            if closes { insideMark = false }
            appendWord(word, subliminal: subliminal, into: &tokens)
        }
        return tokens
    }

    /// Split a whitespace piece on hyphen / em-dash into display sub-words.
    private static func appendWord(_ piece: String,
                                   subliminal: Bool,
                                   into tokens: inout [WordToken]) {
        for segment in splitOnHyphens(piece) {
            if segment.precededByEmDash { mergePauseIntoPrevious(.medium, &tokens) }

            let cleaned = stripped(segment.text)
            guard !cleaned.display.isEmpty else {
                mergePauseIntoPrevious(cleaned.pause, &tokens)
                continue
            }
            tokens.append(WordToken(text: cleaned.display,
                                    pause: cleaned.pause,
                                    isSubliminal: subliminal))
        }
    }
```

> The `splitOnHyphens`, `Segment`, `mergePauseIntoPrevious`, `stripped`, `trailingMarks`, and `strongest` members from Tasks 2-3 are unchanged.

- [ ] **Step 4: Run to verify all tokenizer tests pass**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/WordTokenizerTests
```
Expected: PASS (14 tests).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/WordTokenizer.swift IlumionateTests/TextTrance/WordTokenizerTests.swift
git commit -m "feat(reader): parse [[ ]] authored subliminal marks"
```

---

## Task 5: Quote stripping + internal-punctuation preservation

Strip surrounding quotes/brackets; keep internal apostrophes (`you're`) and internal periods (`3.5`).

**Files:**
- Modify: `Ilumionate/TextTrance/WordTokenizer.swift`
- Modify: `IlumionateTests/TextTrance/WordTokenizerTests.swift`

- [ ] **Step 1: Add the failing tests**

Append inside `WordTokenizerTests`:

```swift
    @Test func preservesInternalApostrophes() {
        let tokens = WordTokenizer.tokenize("you're calm and don't resist")
        #expect(tokens.map(\.text) == ["you're", "calm", "and", "don't", "resist"])
    }

    @Test func preservesInternalPeriodsInNumbers() {
        let tokens = WordTokenizer.tokenize("count 3.5 breaths")
        #expect(tokens.map(\.text) == ["count", "3.5", "breaths"])
    }

    @Test func stripsSurroundingDoubleQuotes() {
        let tokens = WordTokenizer.tokenize("she said \"relax\" softly")
        #expect(tokens.map(\.text) == ["she", "said", "relax", "softly"])
    }

    @Test func stripsTrailingQuoteButKeepsSentencePause() {
        // word followed by a closing quote then a period: drop quote, keep breath
        let tokens = WordTokenizer.tokenize("\"let go.\"")
        #expect(tokens.map(\.text) == ["let", "go"])
        #expect(tokens.last?.pause == .breath)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/WordTokenizerTests
```
Expected: FAIL (`"relax"` keeps quotes; `go."` keeps the trailing quote).

- [ ] **Step 3: Extend `stripped` to handle quotes (leading + trailing)**

In `Ilumionate/TextTrance/WordTokenizer.swift`, add the strippable-quote sets and update `stripped` so it removes leading quotes/brackets, then strips trailing quotes/brackets interleaved with pause-bearing marks. Replace the `trailingMarks` declaration and `stripped` method with:

```swift
    private static let trailingMarks: [Character: PauseKind] = [
        ".": .breath, "!": .breath, "?": .breath, "…": .drift,
        ",": .brief, ";": .brief, ":": .brief
    ]
    // Removed from display but contribute no pause.
    private static let neutralTrailing: Set<Character> =
        ["\"", "'", ")", "]", "\u{201D}", "\u{2019}"]   // " ' ) ] ” ’
    private static let neutralLeading: Set<Character> =
        ["\"", "'", "(", "[", "\u{201C}", "\u{2018}"]   // " ' ( [ “ ‘

    /// Strip surrounding quotes/brackets + trailing punctuation; return the
    /// display text and the strongest trailing pause. Internal apostrophes and
    /// periods (contractions, decimals) are preserved.
    private static func stripped(_ word: String) -> (display: String, pause: PauseKind) {
        var chars = Array(word)
        while let first = chars.first, neutralLeading.contains(first) {
            chars.removeFirst()
        }
        var pause: PauseKind = .none
        while let last = chars.last {
            if last == ".", chars.count >= 3, chars.suffix(3).allSatisfy({ $0 == "." }) {
                pause = strongest(pause, .drift)
                chars.removeLast(3)
                continue
            }
            if let kind = trailingMarks[last] {
                pause = strongest(pause, kind)
                chars.removeLast()
            } else if neutralTrailing.contains(last) {
                chars.removeLast()
            } else {
                break
            }
        }
        return (String(chars), pause)
    }
```

> The `"3.5"` case stops at the digit `5` (not punctuation) → preserved. `"you're"` stops at `e`. The trailing `'` in `neutralTrailing` only strips a *final* apostrophe, never an internal one.

- [ ] **Step 4: Run to verify all tokenizer tests pass**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/WordTokenizerTests
```
Expected: PASS (18 tests).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/WordTokenizer.swift IlumionateTests/TextTrance/WordTokenizerTests.swift
git commit -m "feat(reader): strip surrounding quotes, preserve internal apostrophes/periods"
```

---

## Task 6: `SubliminalLexicon`

The fallback suggestion-word set used when a script has no authored marks.

**Files:**
- Create: `Ilumionate/TextTrance/SubliminalLexicon.swift`
- Create: `IlumionateTests/TextTrance/SubliminalLexiconTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/TextTrance/SubliminalLexiconTests.swift`:

```swift
//  SubliminalLexiconTests.swift
//  IlumionateTests

import Testing
@testable import Ilumionate

struct SubliminalLexiconTests {

    @Test func matchesKnownSuggestionWordsCaseInsensitively() {
        #expect(SubliminalLexicon.contains("deeper"))
        #expect(SubliminalLexicon.contains("Relax"))
        #expect(SubliminalLexicon.contains("SLEEP"))
    }

    @Test func doesNotMatchOrdinaryWords() {
        #expect(!SubliminalLexicon.contains("table"))
        #expect(!SubliminalLexicon.contains(""))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/SubliminalLexiconTests
```
Expected: FAIL (compile error: `SubliminalLexicon` undefined).

- [ ] **Step 3: Create the lexicon**

Create `Ilumionate/TextTrance/SubliminalLexicon.swift`:

```swift
//  SubliminalLexicon.swift
//  Ilumionate
//
//  Fallback suggestion-word set. Applied only when a script contains no authored
//  [[ ]] subliminal marks. Tunable.

import Foundation

enum SubliminalLexicon {
    static let words: Set<String> = [
        "deeper", "relax", "sleep", "now", "drift", "calm", "down", "heavy",
        "let", "go", "breathe", "release", "still", "sink", "deep", "rest",
        "soften", "surrender"
    ]

    static func contains(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/SubliminalLexiconTests
```
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/SubliminalLexicon.swift IlumionateTests/TextTrance/SubliminalLexiconTests.swift
git commit -m "feat(reader): add SubliminalLexicon fallback word set"
```

---

## Task 7: `SubliminalSpeed` + pacing-settings fields

Add the user-facing speed enum and the two new settings fields, with a defaulted init so `TextTranceSession`'s `TextPacingSettings(arc:speed:)` keeps compiling.

**Files:**
- Modify: `Ilumionate/TextTrance/TextPacingEngine.swift` (the `TextPacingSettings` struct, ~19-41)

- [ ] **Step 1: Extend `TextPacingSettings`**

In `Ilumionate/TextTrance/TextPacingEngine.swift`, replace the `TextPacingSettings` struct with:

```swift
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

    /// How fast subliminal words flash past. Lower = faster = less consciously legible.
    enum SubliminalSpeed: String, CaseIterable, Sendable, Identifiable {
        case gentle, medium, deep
        var id: String { rawValue }
        var flashDuration: TimeInterval {
            switch self {
            case .gentle: return 0.12
            case .medium: return 0.09
            case .deep:   return 0.065
            }
        }
        var displayName: String {
            switch self {
            case .gentle: return "Gentle"
            case .medium: return "Medium"
            case .deep:   return "Deep"
            }
        }
    }

    let arc: ScriptArc
    let speed: Speed
    let subliminalEnabled: Bool
    let subliminalSpeed: SubliminalSpeed

    init(arc: ScriptArc,
         speed: Speed,
         subliminalEnabled: Bool = true,
         subliminalSpeed: SubliminalSpeed = .medium) {
        self.arc = arc
        self.speed = speed
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build`
Expected: BUILD SUCCEEDED (existing `TextPacingSettings(arc:speed:)` calls resolve via defaults).

- [ ] **Step 3: Commit**

```bash
git add Ilumionate/TextTrance/TextPacingEngine.swift
git commit -m "feat(reader): add SubliminalSpeed and subliminal pacing settings"
```

---

## Task 8: Subliminal resolution in `schedule`

Resolve the final subliminal flag (authored-first, lexicon-fallback, feature toggle) and apply the flash duration. Restructure `schedule` into a two-pass build so the lexicon fallback can see the whole script.

**Files:**
- Modify: `Ilumionate/TextTrance/TextPacingEngine.swift` (the `schedule` method)
- Create: `IlumionateTests/TextTrance/TextPacingEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `IlumionateTests/TextTrance/TextPacingEngineTests.swift`:

```swift
//  TextPacingEngineTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

struct TextPacingEngineTests {

    private func script(_ text: String, wpm: Double = 600) -> TranceScript {
        TranceScript(
            schemaVersion: 1, id: "t", title: "T", theme: .relaxation,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [TranceScriptSegment(
                phase: .induction, text: text,
                pacing: SegmentPacing(baseWPM: wpm), arcs: nil, triggersHandoff: nil)])
    }

    private func settings(subliminalEnabled: Bool = true,
                          subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium)
    -> TextPacingSettings {
        TextPacingSettings(arc: .fullText, speed: .natural,
                           subliminalEnabled: subliminalEnabled,
                           subliminalSpeed: subliminalSpeed)
    }

    @Test func breathWordHoldsLongerThanPlainWordAndFades() {
        let words = TextPacingEngine.schedule(for: script("rest now."), settings: settings(subliminalEnabled: false))
        // base = 60/600 = 0.1s
        #expect(abs(words[0].duration - 0.1) < 1e-9)             // "rest" plain
        #expect(abs(words[1].duration - 0.1 * 3.0) < 1e-9)       // "now" breath
        #expect(words[1].fade == .breath)
        #expect(words[0].fade == .none)
    }

    @Test func driftWordUsesDriftMultiplierAndFade() {
        let words = TextPacingEngine.schedule(for: script("deeper…"), settings: settings(subliminalEnabled: false))
        #expect(abs(words[0].duration - 0.1 * 4.5) < 1e-9)
        #expect(words[0].fade == .drift)
    }

    @Test func authoredMarkFlashesOnlyThatWord() {
        let words = TextPacingEngine.schedule(for: script("you [[relax]] table"), settings: settings())
        // "you" and "table" are lexicon non-matches; "relax" is authored.
        #expect(words.map(\.isSubliminal) == [false, true, false])
        #expect(abs(words[1].duration - 0.09) < 1e-9)           // medium flash
    }

    @Test func lexiconAppliesOnlyWhenNoAuthoredMarks() {
        // No authored marks → lexicon flags "relax" and "deeper".
        let words = TextPacingEngine.schedule(for: script("you relax deeper table"), settings: settings())
        #expect(words.map(\.isSubliminal) == [false, true, true, false])
    }

    @Test func lexiconIgnoredWhenAuthoredMarksPresent() {
        // Authored mark exists → lexicon word "deeper" is NOT auto-flashed.
        let words = TextPacingEngine.schedule(for: script("[[relax]] deeper"), settings: settings())
        #expect(words.map(\.isSubliminal) == [true, false])
    }

    @Test func subliminalDisabledFlagsNothing() {
        let words = TextPacingEngine.schedule(for: script("you [[relax]] deeper"), settings: settings(subliminalEnabled: false))
        #expect(words.allSatisfy { !$0.isSubliminal })
    }

    @Test func subliminalSpeedControlsFlashDuration() {
        let deep = TextPacingEngine.schedule(for: script("relax"), settings: settings(subliminalSpeed: .deep))
        let gentle = TextPacingEngine.schedule(for: script("relax"), settings: settings(subliminalSpeed: .gentle))
        #expect(abs(deep[0].duration - 0.065) < 1e-9)
        #expect(abs(gentle[0].duration - 0.12) < 1e-9)
    }

    @Test func startTimeIsCumulativeSumOfDurations() {
        let words = TextPacingEngine.schedule(for: script("rest now. drift"), settings: settings(subliminalEnabled: false))
        var cursor = 0.0
        for word in words {
            #expect(abs(word.startTime - cursor) < 1e-9)
            cursor += word.duration
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/TextPacingEngineTests
```
Expected: FAIL (subliminal always false; flash durations not applied).

- [ ] **Step 3: Restructure `schedule` for two-pass subliminal resolution**

In `Ilumionate/TextTrance/TextPacingEngine.swift`, replace the entire `schedule` method with:

```swift
    static func schedule(for script: TranceScript,
                         settings: TextPacingSettings) -> [PacedWord] {
        // Pass 1: flatten to pending words (text, pause, authored flag, base duration).
        var pending: [Pending] = []
        for segment in script.segments {
            guard segmentPlays(segment, in: settings.arc) else { continue }
            let baseDuration = 60.0 / effectiveWPM(for: segment, speed: settings.speed)
            for token in WordTokenizer.tokenize(segment.text) {
                pending.append(Pending(text: token.text,
                                       pause: token.pause,
                                       authoredSubliminal: token.isSubliminal,
                                       phase: segment.phase,
                                       baseDuration: baseDuration))
            }
            if settings.arc == .handoff, segment.triggersHandoff == true { break }
        }

        let hasAuthored = pending.contains { $0.authoredSubliminal }

        // Pass 2: resolve subliminal + compute the timed schedule.
        var result: [PacedWord] = []
        var cursor: TimeInterval = 0
        for item in pending {
            let subliminal = resolveSubliminal(item, hasAuthored: hasAuthored, settings: settings)
            let duration = subliminal
                ? settings.subliminalSpeed.flashDuration
                : item.baseDuration * holdMultiplier(item.pause)
            let fade: FadeKind = subliminal ? .none : fadeKind(item.pause)
            result.append(PacedWord(
                text: item.text,
                pivotIndex: ORPCalculator.pivotIndex(for: item.text),
                phase: item.phase,
                startTime: cursor,
                duration: duration,
                fade: fade,
                isSubliminal: subliminal))
            cursor += duration
        }
        return result
    }

    private struct Pending {
        let text: String
        let pause: PauseKind
        let authoredSubliminal: Bool
        let phase: TrancePhase
        let baseDuration: TimeInterval
    }

    private static func resolveSubliminal(_ item: Pending,
                                          hasAuthored: Bool,
                                          settings: TextPacingSettings) -> Bool {
        guard settings.subliminalEnabled else { return false }
        if hasAuthored { return item.authoredSubliminal }
        return SubliminalLexicon.contains(item.text)
    }
```

> This removes the old single-pass loop. `segmentPlays`, `effectiveWPM`, `holdMultiplier`, and `fadeKind` are unchanged.

- [ ] **Step 4: Run the engine tests to verify they pass**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/TextPacingEngineTests
```
Expected: PASS (8 tests).

- [ ] **Step 5: Run session + word-sizing suites for regression**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/TextTranceSessionTests \
  -only-testing:IlumionateTests/TextTranceWordSizingTests
```
Expected: PASS. (Session scripts use plain words with no lexicon matches, so default `subliminalEnabled: true` does not change `currentWord`.)

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/TextTrance/TextPacingEngine.swift IlumionateTests/TextTrance/TextPacingEngineTests.swift
git commit -m "feat(reader): resolve subliminal layer (authored→lexicon→toggle) in schedule"
```

---

## Task 9: Thread subliminal settings + publish fade/duration in the session

`TextTranceSessionSettings` gains the two subliminal fields (defaulted), the session forwards them into `TextPacingSettings`, and the loop publishes `currentFade` + `currentDuration` for the view.

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSession.swift`

- [ ] **Step 1: Add a test asserting the session forwards subliminal settings**

Append to `IlumionateTests/TextTrance/TextTranceSessionTests.swift` (inside the `TextTranceSessionTests` struct):

```swift
    @Test func lexiconWordFlashesFastInSchedule() async {
        // "deeper" is a lexicon word → should be subliminal-fast (0.09s at .medium),
        // far shorter than the 600-wpm base of 0.1s, proving settings are threaded.
        let script = TranceScript(
            schemaVersion: 1, id: "x", title: "X", theme: .relaxation,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [TranceScriptSegment(phase: .induction, text: "go deeper",
                pacing: SegmentPacing(baseWPM: 600), arcs: nil, triggersHandoff: nil)])
        let words = TextPacingEngine.schedule(
            for: script,
            settings: TextPacingSettings(arc: .fullText, speed: .natural))
        // both "go" and "deeper" are lexicon words → both flash
        #expect(words.allSatisfy(\.isSubliminal))
    }
```

> This is an engine-level assertion placed here for convenience; it does not require new session API. The session-threading itself is verified by Step 4's build + the player using `currentFade`.

- [ ] **Step 2: Extend `TextTranceSessionSettings` with defaulted subliminal fields**

In `Ilumionate/TextTrance/TextTranceSession.swift`, replace the `TextTranceSessionSettings` struct (lines 11-18) with:

```swift
/// Everything the player needs to run one session.
struct TextTranceSessionSettings: Sendable {
    let arc: ScriptArc
    let speed: TextPacingSettings.Speed
    let lightEnabled: Bool
    let binauralEnabled: Bool
    let beatFrequency: Double
    let postHandoffDuration: TimeInterval
    let subliminalEnabled: Bool
    let subliminalSpeed: TextPacingSettings.SubliminalSpeed

    init(arc: ScriptArc,
         speed: TextPacingSettings.Speed,
         lightEnabled: Bool,
         binauralEnabled: Bool,
         beatFrequency: Double,
         postHandoffDuration: TimeInterval,
         subliminalEnabled: Bool = true,
         subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium) {
        self.arc = arc
        self.speed = speed
        self.lightEnabled = lightEnabled
        self.binauralEnabled = binauralEnabled
        self.beatFrequency = beatFrequency
        self.postHandoffDuration = postHandoffDuration
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
    }
}
```

- [ ] **Step 3: Publish `currentFade`/`currentDuration` and forward settings**

In `Ilumionate/TextTrance/TextTranceSession.swift`:

(a) Add two published properties next to `currentWord` (after line 30, `private(set) var isComplete = false`):

```swift
    private(set) var currentFade: FadeKind = .none
    private(set) var currentDuration: TimeInterval = 0
```

(b) In `init`, replace the `TextPacingSettings(...)` used for `readerReferenceCharacterCount` (line 52) with the fully-threaded version:

```swift
            for: TextPacingEngine.schedule(
                for: script,
                settings: TextPacingSettings(arc: settings.arc,
                                             speed: settings.speed,
                                             subliminalEnabled: settings.subliminalEnabled,
                                             subliminalSpeed: settings.subliminalSpeed)
            )
```

(c) In `begin`, replace the `let pacing = TextPacingSettings(arc: settings.arc, speed: settings.speed)` line (line 66) with:

```swift
        let pacing = TextPacingSettings(arc: settings.arc,
                                        speed: settings.speed,
                                        subliminalEnabled: settings.subliminalEnabled,
                                        subliminalSpeed: settings.subliminalSpeed)
```

(d) In the reading loop, replace the body that sets the current word (lines 77-80) with:

```swift
            currentWord = word.text
            currentPivotIndex = word.pivotIndex
            currentPhase = word.phase
            currentFade = word.fade
            currentDuration = word.duration
            await sleep(.seconds(word.duration))
```

- [ ] **Step 4: Build + run session tests**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:IlumionateTests/TextTranceSessionTests
```
Expected: PASS (existing 6 tests + the new `lexiconWordFlashesFastInSchedule`).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceSession.swift IlumionateTests/TextTrance/TextTranceSessionTests.swift
git commit -m "feat(reader): thread subliminal settings; publish currentFade/currentDuration"
```

---

## Task 10: Breath/drift fade rendering in the player

Reset opacity instantly on each new word; for breath/drift words, animate opacity → 0 across the word's duration so it reads as a "breath". (UI — verified by build + manual run, no unit test.)

**Files:**
- Modify: `Ilumionate/TextTrance/TextTrancePlayerView.swift`

- [ ] **Step 1: Add opacity state + fade-driving `onChange`**

In `Ilumionate/TextTrance/TextTrancePlayerView.swift`, add a state property after `@State private var backgroundPulse = false` (line 14):

```swift
    @State private var wordOpacity: Double = 1
```

Then replace the `if session.isReading { … }` block (lines 33-43) with:

```swift
            if session.isReading {
                AnchoredWord(
                    text: session.currentWord,
                    pivot: session.currentPivotIndex,
                    referenceCharacterCount: session.readerReferenceCharacterCount
                )
                .opacity(wordOpacity)
                .onChange(of: session.currentWord) { _, _ in
                    applyWordFade()
                }
            } else if session.lightActive {
                Text("…")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.textSecondary)
            }
```

- [ ] **Step 2: Add the `applyWordFade` helper**

Add this method to `TextTrancePlayerView` (e.g. after `body`, before `endHoldGesture`):

```swift
    /// Snap to full opacity for every word, then fade breath/drift words out
    /// across their hold so sentence-ends and ellipses "breathe".
    private func applyWordFade() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { wordOpacity = 1 }

        switch session.currentFade {
        case .none:
            break
        case .breath:
            withAnimation(.easeIn(duration: session.currentDuration)) { wordOpacity = 0.05 }
        case .drift:
            withAnimation(.easeIn(duration: session.currentDuration)) { wordOpacity = 0 }
        }
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification (run on simulator)**

Run the app, open a Text Trance script, and Begin. Confirm:
- Words show with no trailing punctuation.
- After a sentence-ending word the text fades out (a breath); ellipses fade slower.
- The next word snaps back to full brightness (no lingering ghost).

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/TextTrancePlayerView.swift
git commit -m "feat(reader): breath/drift opacity fade in the player"
```

---

## Task 11: Subliminal setup card

Expose the on/off toggle + Gentle/Medium/Deep speed, and thread the choices into the built session. (UI — verified by build + preview.)

**Files:**
- Modify: `Ilumionate/TextTrance/TextTranceSetupView.swift`

- [ ] **Step 1: Add state + card to the setup view**

In `Ilumionate/TextTrance/TextTranceSetupView.swift`, add two state properties after `@State private var binauralEnabled = false` (line 15):

```swift
    @State private var subliminalEnabled = true
    @State private var subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium
```

Add the card to the `VStack` (after `SpeedCard(speed: $speed)`, line 30):

```swift
                    SpeedCard(speed: $speed)
                    SubliminalCard(enabled: $subliminalEnabled, speed: $subliminalSpeed)
```

- [ ] **Step 2: Thread the choices into `makeSession`**

In `makeSession`, replace the `TextTranceSessionSettings(...)` initializer (lines 54-60) with:

```swift
            settings: TextTranceSessionSettings(
                arc: arc,
                speed: speed,
                lightEnabled: useLight,
                binauralEnabled: binauralEnabled,
                beatFrequency: 10,
                postHandoffDuration: 600,
                subliminalEnabled: subliminalEnabled,
                subliminalSpeed: subliminalSpeed),
```

- [ ] **Step 3: Add the `SubliminalCard` view**

Add this view struct near the other private cards (e.g. after `SpeedCard`, before `#Preview`):

```swift
private struct SubliminalCard: View {
    @Binding var enabled: Bool
    @Binding var speed: TextPacingSettings.SubliminalSpeed

    var body: some View {
        LiminalCard(label: "Subliminal suggestions") {
            VStack(spacing: TranceSpacing.list) {
                Toggle("Flash suggestion words", isOn: $enabled)
                    .tint(.auroraTeal)
                if enabled {
                    Picker("Flash speed", selection: $speed) {
                        ForEach(TextPacingSettings.SubliminalSpeed.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual verification**

Run the app → open a script → confirm the "Subliminal suggestions" card appears, the toggle hides/shows the speed picker, and Begin still launches the reader. With the toggle off, no words flash fast; with it on (default), lexicon words (or authored marks) flash.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/TextTrance/TextTranceSetupView.swift
git commit -m "feat(reader): subliminal toggle + speed card in setup"
```

---

## Task 12: Full-suite verification

- [ ] **Step 1: Run the entire test suite**

Run:
```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate test \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expected: PASS — including `WordTokenizerTests` (18), `TextPacingEngineTests` (8), `SubliminalLexiconTests` (2), `TextTranceSessionTests` (7), `TextTranceWordSizingTests` (4), and all pre-existing suites.

- [ ] **Step 2: If any pre-existing suite fails**, inspect whether it depended on punctuation-in-display or the old `endsSentence` behavior, and reconcile (the design preserves the `startTime`/`duration` contract, so failures most likely indicate a display-text expectation that should be updated to the clean text).

- [ ] **Step 3: Final manual smoke test** on the simulator: read a script end-to-end with subliminal on, then off; confirm hyphenated compounds split and sentence-ends breathe.

---

## Self-Review Notes (author)

- **Spec coverage:** strip-from-display (Task 2/5), hyphen split (Task 3), pause→timing+fade (Task 2/8), authored `[[ ]]` marks (Task 4), lexicon fallback + precedence + toggle (Task 6/8), `SubliminalSpeed` settings + UI (Task 7/11), identical subliminal rendering / opacity reset / fade (Task 10), session plumbing (Task 9), timeline contract preserved (Task 8 test `startTimeIsCumulativeSumOfDurations`). Feature 2 is out of scope by design.
- **Subliminal precedence over pause/fade:** a subliminal word uses `flashDuration` and `fade = .none` regardless of trailing punctuation (Task 8) — matches the spec table.
- **Type consistency:** `PauseKind` (Int-backed for `strongest`), `FadeKind`, `SubliminalSpeed`, `WordToken{text,pause,isSubliminal}`, `PacedWord{…,fade,isSubliminal}` are used identically across tasks. Defaulted inits on `PacedWord`, `TextPacingSettings`, and `TextTranceSessionSettings` keep all pre-existing call sites compiling.
