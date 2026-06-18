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
        let allNone = tokens.allSatisfy { $0.pause == .none }
        #expect(allNone)
    }

    @Test func emptyStringYieldsNoTokens() {
        #expect(WordTokenizer.tokenize("   ").isEmpty)
    }

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
}
