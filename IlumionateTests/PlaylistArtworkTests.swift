//
//  PlaylistArtworkTests.swift
//  IlumionateTests
//
//  Tests for the shared playlist artwork content-type derivation.
//

import Testing
@testable import Ilumionate

@Suite("PlaylistArtwork.distinctTypes")
struct PlaylistArtworkTests {

    @Test("Deduplicates preserving first-seen order")
    func deduplicates() {
        let input: [AudioContentType?] = [.hypnosis, .hypnosis, .music, .hypnosis]
        #expect(PlaylistArtwork.distinctTypes(from: input) == [.hypnosis, .music])
    }

    @Test("Drops nil and .unknown")
    func dropsNilAndUnknown() {
        let input: [AudioContentType?] = [nil, .unknown, .meditation, nil]
        #expect(PlaylistArtwork.distinctTypes(from: input) == [.meditation])
    }

    @Test("Caps at 4 types")
    func capsAtFour() {
        let input: [AudioContentType?] = [.hypnosis, .meditation, .music, .guidedImagery, .affirmations]
        #expect(PlaylistArtwork.distinctTypes(from: input) == [.hypnosis, .meditation, .music, .guidedImagery])
    }

    @Test("Empty input yields empty")
    func emptyYieldsEmpty() {
        #expect(PlaylistArtwork.distinctTypes(from: []) == [])
    }
}
