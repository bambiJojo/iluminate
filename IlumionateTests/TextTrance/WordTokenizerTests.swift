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
