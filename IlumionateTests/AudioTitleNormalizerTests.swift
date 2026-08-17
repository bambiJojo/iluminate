//
//  AudioTitleNormalizerTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct AudioTitleNormalizerTests {
    @Test("Strips path, extension, case and punctuation")
    func reducesToComparableTokens() {
        #expect(AudioTitleNormalizer.normalize("/tmp/Deep_Relaxation!.mp3") == "deep relaxation")
        #expect(AudioTitleNormalizer.normalize("Deep   Relaxation") == "deep relaxation")
        #expect(AudioTitleNormalizer.normalize("Déjà Calm") == "deja calm")
    }

    @Test("Drops disposable production suffixes")
    func dropsDisposableSuffixes() {
        #expect(AudioTitleNormalizer.normalize("Deep Relaxation official") == "deep relaxation")
        #expect(AudioTitleNormalizer.normalize("Deep Relaxation HQ remastered") == "deep relaxation")
    }

    // The old normaliser stripped a leading number of up to three digits, so
    // every entry in a numbered series reduced to the same key and the importer
    // could not tell track 01 from track 02.
    @Test("Numbered series stay distinct")
    func numberedSeriesStayDistinct() {
        let first = AudioTitleNormalizer.normalize("01 Bambi Sleep")
        let second = AudioTitleNormalizer.normalize("02 Bambi Sleep")

        #expect(first != second)
        #expect(first == "01 bambi sleep")
    }

    @Test("Reads the leading track number when there is one")
    func readsLeadingTrackNumber() {
        #expect(AudioTitleNormalizer.leadingTrackNumber("02 Bambi Sleep") == 2)
        #expect(AudioTitleNormalizer.leadingTrackNumber("Bambi Sleep") == nil)
        // Four digits is a year or a catalogue code, not a track position.
        #expect(AudioTitleNormalizer.leadingTrackNumber("2024 Bambi Sleep") == nil)
    }

    @Test("An empty or punctuation-only name normalizes to empty")
    func emptyNameNormalizesToEmpty() {
        #expect(AudioTitleNormalizer.normalize("") == "")
        #expect(AudioTitleNormalizer.normalize("---.mp3") == "")
    }
}
