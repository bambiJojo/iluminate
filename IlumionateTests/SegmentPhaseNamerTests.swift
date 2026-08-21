//
//  SegmentPhaseNamerTests.swift
//  IlumionateTests
//
//  Naming matters roughly three times more than boundary placement: holding
//  boundaries fixed and swapping correct labels for the shipping analyser's own
//  took BF.mp3 from 9% to 28% frequency deviation, and Tick Tock from 11% to
//  32%. A wrong label selects a different light behaviour outright — decay,
//  oscillation, or rise — while a misplaced boundary only shifts when the right
//  behaviour starts.
//
//  So the naming target is the behaviour, not the vocabulary. These tests pin
//  the distinctions the light engine actually acts on.
//

import Testing
import Foundation
import CorpusKit
@testable import Ilumionate

private func segment(_ start: TimeInterval, _ end: TimeInterval) -> StructuralSegment {
    StructuralSegment(startTime: start, endTime: end, confidence: 0.3)
}

private func countingRun(
    _ direction: CountingRun.Direction,
    at start: TimeInterval
) -> CountingRun {
    CountingRun(direction: direction, startTime: start, endTime: start + 10, length: 5)
}

struct SegmentPhaseNamerTests {

    @Test("A descending count marks a deepening, not an emergence")
    func descendingCountNamesDeepening() {
        let names = SegmentPhaseNamer.name(
            segments: [segment(0, 300), segment(300, 900), segment(900, 1200)],
            countingRuns: [countingRun(.descending, at: 310)],
            prosody: nil,
            duration: 1200
        )

        #expect(names[1] == .deepening)
    }

    /// The most expensive confusion in the whole system: emergence rises,
    /// deepening decays. Getting these the wrong way round inverts the light.
    ///
    /// The count sits at 98% of the file, which is where the corpus actually puts
    /// them — labelled emergences begin at 92-99% and run for 0.9-8.1% of the
    /// duration. An earlier version of this test placed it at 76% and passed,
    /// encoding a guess the labels contradict.
    @Test("An ascending count at the very end marks the emergence")
    func ascendingCountNamesEmergence() {
        let names = SegmentPhaseNamer.name(
            segments: [segment(0, 300), segment(300, 1140), segment(1140, 1200)],
            countingRuns: [countingRun(.ascending, at: 1176)],
            prosody: nil,
            duration: 1200
        )

        #expect(names.last == .emergence)
    }

    /// Mind Melt.mp3 has no counts at all, and the namer claimed its last 5.5
    /// minutes as emergence on position alone. The real emergence is 21 seconds.
    @Test("Emergence is not claimed for the last fifth of a file")
    func emergenceIsConfinedToTheEnd() {
        let segments = [
            segment(0, 1200), segment(1200, 2100),
            segment(2100, 2232), segment(2232, 2328), segment(2328, 2434)
        ]
        let names = SegmentPhaseNamer.name(
            segments: segments, countingRuns: [], prosody: nil, duration: 2434
        )

        // 2100-2232s is 86-92% of the file, and is labelled conditioning.
        #expect(names[2] != .emergence)
    }

    /// BF.mp3 counts up at 47% and DFTC at 34%; neither is an emergence. Counting
    /// up mid-file happens in fractionation, and treating it as an emergence
    /// inverts the light for the rest of the session.
    @Test("An ascending count mid-file is not an emergence")
    func midFileAscendingCountIsNotEmergence() {
        let names = SegmentPhaseNamer.name(
            segments: [segment(0, 400), segment(400, 800), segment(800, 1200)],
            countingRuns: [countingRun(.ascending, at: 560)],
            prosody: nil,
            duration: 1200
        )

        #expect(names[1] != .emergence)
    }

    @Test("A file opens with an induction")
    func openingIsInduction() {
        let names = SegmentPhaseNamer.name(
            segments: [segment(0, 300), segment(300, 900), segment(900, 1200)],
            countingRuns: [],
            prosody: nil,
            duration: 1200
        )

        #expect(names.first == .induction)
    }

    /// A session does not return to its induction after emerging. Allowing it
    /// would let one noisy segment reverse the light for the rest of the file.
    @Test("Phases never run backwards")
    func phasesAdvanceMonotonically() {
        let segments = (0..<8).map { segment(Double($0) * 150, Double($0 + 1) * 150) }
        let names = SegmentPhaseNamer.name(
            segments: segments,
            countingRuns: [countingRun(.ascending, at: 160)],
            prosody: nil,
            duration: 1200
        )

        let ordered = SegmentPhaseNamer.namedPhases
        let indices = names.compactMap { ordered.firstIndex(of: $0) }
        #expect(indices == indices.sorted())
    }

    /// The pure-deepener case. One segment must not be forced through an arc.
    @Test("A single segment is named once, not made into an arc")
    func singleSegmentGetsOneName() {
        let names = SegmentPhaseNamer.name(
            segments: [segment(0, 900)],
            countingRuns: [],
            prosody: nil,
            duration: 900
        )

        #expect(names.count == 1)
    }

    @Test("A descending count in a one-segment file still names a deepening")
    func singleSegmentRespectsItsCount() {
        let names = SegmentPhaseNamer.name(
            segments: [segment(0, 900)],
            countingRuns: [countingRun(.descending, at: 100)],
            prosody: nil,
            duration: 900
        )

        #expect(names == [.deepening])
    }

    @Test("Every segment is named")
    func namesMatchSegmentCount() {
        let segments = (0..<6).map { segment(Double($0) * 200, Double($0 + 1) * 200) }
        #expect(
            SegmentPhaseNamer.name(
                segments: segments, countingRuns: [], prosody: nil, duration: 1200
            ).count == 6
        )
    }

    @Test("No segments means no names")
    func emptyInputIsEmpty() {
        #expect(
            SegmentPhaseNamer.name(
                segments: [], countingRuns: [], prosody: nil, duration: 0
            ).isEmpty
        )
    }

    /// Conditioning sits immediately before the emergence in every labelled
    /// file — 66.7-91.9%, 88.2-99.1%, 90.4-96.0% and 95.0-98.0% — and is
    /// *shallower* than suggestions (0.58 against 0.72), so naming it as
    /// suggestions lights the close of a session deeper than intended.
    @Test("The run-up to an emergence is named conditioning")
    func lateSegmentBeforeEmergenceIsConditioning() {
        let names = SegmentPhaseNamer.name(
            segments: [
                segment(0, 600), segment(600, 1500),
                segment(1500, 1900), segment(1900, 2000)
            ],
            countingRuns: [countingRun(.ascending, at: 1960)],
            prosody: nil,
            duration: 2000
        )

        #expect(names.last == .emergence)
        #expect(names[2] == .conditioning)
    }

    @Test("Conditioning is not named early in a file")
    func conditioningIsNotNamedEarly() {
        let segments = (0..<6).map { segment(Double($0) * 200, Double($0 + 1) * 200) }
        let names = SegmentPhaseNamer.name(
            segments: segments, countingRuns: [], prosody: nil, duration: 1200
        )

        #expect(names.prefix(3).contains(.conditioning) == false)
    }

    /// Fractionation is induction applied repeatedly — down, up, down, each pass
    /// landing deeper — so it is named from the *shape* of the counting rather
    /// than from where it falls. That distinction matters: no corpus file shows
    /// where fractionation occurs within a file, so a positional prior could not
    /// be checked, while alternating counts follow from what the technique is.
    @Test("Fractionation is detectable but not named, pending one labelled example")
    func fractionationIsNotNamedYet() {
        let names = SegmentPhaseNamer.name(
            segments: [segment(0, 200), segment(200, 700), segment(700, 1600), segment(1600, 2000)],
            countingRuns: [
                countingRun(.descending, at: 250),
                countingRun(.ascending, at: 400),
                countingRun(.descending, at: 550)
            ],
            prosody: nil,
            duration: 2000
        )

        #expect(SegmentPhaseNamer.namedPhases.contains(.fractionation) == false)
        #expect(names.contains(.fractionation) == false)
    }

    /// A lone deepener is not fractionation, however early it falls.
    @Test("A single count down is a deepening, not a fractionation")
    func loneDescendingCountIsNotFractionation() {
        let names = SegmentPhaseNamer.name(
            segments: [segment(0, 300), segment(300, 900), segment(900, 1200)],
            countingRuns: [countingRun(.descending, at: 350)],
            prosody: nil,
            duration: 1200
        )

        #expect(names[1] == .deepening)
    }

    /// Each named phase must land in a distinct light behaviour, or naming
    /// cannot express the difference that was measured to matter.
    ///
    /// Compared as trajectories rather than at one instant: the suggestions
    /// oscillation passes exactly through the decay value at progress 0.5, where
    /// `sin(π)` is zero, so a single sample makes two different behaviours look
    /// identical.
    @Test("The vocabulary spans the light behaviours it exists to select")
    func vocabularyCoversDistinctBehaviours() {
        let generator = SessionGenerator()
        let samples = [0.0, 0.25, 0.5, 0.75, 1.0]
        let trajectories = Set(
            SegmentPhaseNamer.namedPhases.map { phase in
                samples
                    .map { generator.intensityContour(for: phase, progress: $0).formatted(.number.precision(.fractionLength(4))) }
                    .joined(separator: ",")
            }
        )

        #expect(trajectories.count >= 3)
    }
}
