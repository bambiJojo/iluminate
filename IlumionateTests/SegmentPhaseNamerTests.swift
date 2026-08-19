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
    @Test("An ascending count near the end marks the emergence")
    func ascendingCountNamesEmergence() {
        let names = SegmentPhaseNamer.name(
            segments: [segment(0, 300), segment(300, 900), segment(900, 1200)],
            countingRuns: [countingRun(.ascending, at: 910)],
            prosody: nil,
            duration: 1200
        )

        #expect(names.last == .emergence)
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
