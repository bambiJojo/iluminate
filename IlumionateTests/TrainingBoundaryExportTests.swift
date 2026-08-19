//
//  TrainingBoundaryExportTests.swift
//  IlumionateTests
//
//  `denseTimeline` cannot express a boundary between two identically-labelled
//  phases: it stores one label per second, so three consecutive `deepening`
//  segments read as one unbroken run. DFTC.mp3 in the training corpus is
//  labelled exactly that way.
//
//  The boundaries were never actually lost — `phaseSegments` has always carried
//  them — but reading the dense timeline instead is an easy mistake to make, and
//  it was made: the structural detector was scored against 4 boundaries for
//  BF.mp3 where the labeller had marked 6. `boundarySeconds` exists so the
//  correct source is the obvious one.
//

import Testing
import Foundation
import CorpusKit
@testable import Ilumionate

private func segment(
    _ phase: TrancePhase,
    _ start: TimeInterval,
    _ end: TimeInterval
) -> AnalyzerTrainingExample.PhaseSegment {
    AnalyzerTrainingExample.PhaseSegment(
        id: UUID(),
        phase: phase,
        startTime: start,
        endTime: end,
        durationSeconds: end - start,
        notes: nil
    )
}

struct TrainingBoundaryExportTests {

    @Test("Every phase change after the first is a boundary")
    func boundariesFollowPhaseChanges() {
        let segments = [
            segment(.preTalk, 0, 83),
            segment(.induction, 83, 994),
            segment(.deepening, 994, 1503),
            segment(.emergence, 1503, 1800)
        ]

        #expect(AnalyzerTrainingExample.boundarySeconds(from: segments) == [83, 994, 1503])
    }

    /// The case the dense timeline cannot represent. DFTC.mp3 is labelled with
    /// three consecutive `deepening` segments and real boundaries between them.
    @Test("A boundary between two identically-labelled phases survives")
    func repeatedPhaseStillYieldsABoundary() {
        let segments = [
            segment(.deepening, 0, 300),
            segment(.deepening, 300, 600),
            segment(.deepening, 600, 900)
        ]

        #expect(AnalyzerTrainingExample.boundarySeconds(from: segments) == [300, 600])
    }

    @Test("The file opening is not a boundary")
    func firstSegmentIsNotABoundary() {
        #expect(AnalyzerTrainingExample.boundarySeconds(from: [segment(.induction, 0, 600)]).isEmpty)
    }

    @Test("Segments are ordered before boundaries are read off them")
    func unsortedInputIsHandled() {
        let segments = [
            segment(.emergence, 1503, 1800),
            segment(.preTalk, 0, 83),
            segment(.induction, 83, 1503)
        ]

        #expect(AnalyzerTrainingExample.boundarySeconds(from: segments) == [83, 1503])
    }

    @Test("No phases means no boundaries")
    func emptyInputIsEmpty() {
        #expect(AnalyzerTrainingExample.boundarySeconds(from: []).isEmpty)
    }
}
