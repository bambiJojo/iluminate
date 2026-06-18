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
