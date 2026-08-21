//
//  TrancePhaseCodecTests.swift
//  IlumionateTests
//
//  `TrancePhase` used to collapse ten labelled phases into five inside its own
//  Codable conformance — `pre_talk` decoded as `.induction` and encoded back as
//  "induction". The projection is wanted; doing it in the codec was not.
//
//  Two consequences, both measured on the training corpus:
//
//  - Opening a label file and saving it rewrote the labels on disk. Every one of
//    the four hand-annotated files lost its `pre_talk → induction` boundary, and
//    roughly 40% of all labelled boundaries never reached the training export.
//  - `SessionGenerator.intensityContour` has a distinct contour for
//    `.fractionation`, which no persisted analysis could ever reach, because
//    storage rewrote it to `.deepening`.
//
//  The five-bucket view is still how light is chosen; `labelingPhase` supplies
//  it at the point of use, which is what the rest of the codebase already does.
//

import Testing
import Foundation
import CorpusKit
@testable import Ilumionate

struct TrancePhaseCodecTests {

    private func roundTrip(_ phase: TrancePhase) throws -> TrancePhase {
        let data = try JSONEncoder().encode(phase)
        return try JSONDecoder().decode(TrancePhase.self, from: data)
    }

    @Test(
        "A labelled phase survives a save and reload",
        arguments: [
            TrancePhase.preTalk,
            .fractionation,
            .confusion,
            .eroticSuggestions,
            .conditioning,
            .therapy,
            .induction,
            .deepening,
            .suggestions,
            .brainwashing,
            .emergence,
            .transitional
        ]
    )
    func phasesRoundTripWithoutCollapsing(phase: TrancePhase) throws {
        #expect(try roundTrip(phase) == phase)
    }

    @Test("A phase decodes from the spelling the corpus actually stores")
    func decodesCorpusSpellings() throws {
        let json = Data(#"["pre_talk","erotic_suggestions","post_hypnotic_conditioning"]"#.utf8)
        let decoded = try JSONDecoder().decode([TrancePhase].self, from: json)

        #expect(decoded == [.preTalk, .eroticSuggestions, .conditioning])
    }

    @Test("An unknown phase is still rejected rather than silently remapped")
    func unknownPhaseThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TrancePhase.self, from: Data(#""hypnodrome""#.utf8))
        }
    }

    /// The projection onto the seven phases the analyzer is trained to emit.
    ///
    /// `fractionation` and `conditioning` now pass through: collapsing them was
    /// the most expensive part of the old five-phase target. Fractionation lost
    /// a unique contour and moved depth 0.42 → 0.62; conditioning is *shallower*
    /// than suggestions (0.58 against 0.72), so folding it in made the light
    /// deeper than intended across long closing sections.
    @Test("Only phases with identical or near-identical light are folded away")
    func projectionKeepsWhatChangesTheLight() {
        // Identical light to their targets.
        #expect(TrancePhase.preTalk.labelingPhase == .induction)
        #expect(TrancePhase.confusion.labelingPhase == .deepening)

        // Distinct light, and therefore targets in their own right.
        #expect(TrancePhase.fractionation.labelingPhase == .fractionation)
        #expect(TrancePhase.conditioning.labelingPhase == .conditioning)

        // Nearest target by depth, at the smallest losses available.
        #expect(TrancePhase.eroticSuggestions.labelingPhase == .suggestions)
        #expect(TrancePhase.therapy.labelingPhase == .suggestions)
    }

    /// A target phase must project to itself, or training data would carry a
    /// label the analyzer is never asked to emit.
    @Test("Every target phase is its own projection")
    func targetPhasesAreFixedPoints() {
        for phase in TrancePhase.orderedHypnosisPhases {
            #expect(phase.labelingPhase == phase)
        }
    }
}

// MARK: - Light behaviour

struct PhaseIntensityContourTests {

    private let generator = SessionGenerator()

    /// The bug the codec was hiding: fractionation has its own oscillation and
    /// no stored analysis could reach it.
    @Test("Fractionation gets its own contour, not deepening's")
    func fractionationIsDistinctFromDeepening() {
        let fractionation = generator.intensityContour(for: .fractionation, progress: 0.5)
        let deepening = generator.intensityContour(for: .deepening, progress: 0.5)

        #expect(fractionation != deepening)
    }

    /// Phases that previously reached the contour only *via* the collapse must
    /// keep the behaviour they had, or removing the collapse silently changes
    /// the light for every existing session.
    @Test("Pre-talk keeps the contour it had through the collapse")
    func preTalkMatchesInduction() {
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            #expect(
                generator.intensityContour(for: .preTalk, progress: progress)
                    == generator.intensityContour(for: .induction, progress: progress)
            )
        }
    }

    @Test("Erotic suggestions keep the contour they had through the collapse")
    func eroticSuggestionsMatchSuggestions() {
        for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
            #expect(
                generator.intensityContour(for: .eroticSuggestions, progress: progress)
                    == generator.intensityContour(for: .suggestions, progress: progress)
            )
        }
    }
}
