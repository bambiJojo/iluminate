//
//  ChunkedPhaseAnalyzerSmoothingTests.swift
//  IlumionateTests
//
//  Tests for Step 3.2: ChunkedPhaseAnalyzer+Smoothing static functions.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - enforcePhaseOrdering

struct ChunkedEnforcePhaseOrderingTests {

    @Test func alreadyOrderedTimelineIsUnchanged() {
        let timeline: [HypnosisMetadata.Phase?] = [.preTalk, .induction, .deepening, .therapy]
        let result = ChunkedPhaseAnalyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result == [.induction, .induction, .deepening, .suggestions])
    }

    @Test func sustainedBackwardTransitionIsPreserved() {
        let timeline: [HypnosisMetadata.Phase?] = [.suggestions, .deepening]
        let result = ChunkedPhaseAnalyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result == timeline)
    }

    @Test func nilElementsArePreserved() {
        let timeline: [HypnosisMetadata.Phase?] = [.suggestions, nil, .deepening]
        let result = ChunkedPhaseAnalyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result[1] == nil)
        #expect(result[2] == .deepening)
    }

    @Test func emptyReturnsEmpty() {
        let result = ChunkedPhaseAnalyzer.enforcePhaseOrdering(timeline: [])
        #expect(result.isEmpty)
    }
}

// MARK: - Split classification assembly

struct ChunkedSplitClassificationTests {

    @Test func splitClassificationsPreserveBothHalfTimelines() {
        let classifications = [
            ChunkedPhaseAnalyzer.TimedClassification(start: 0, end: 45, phase: .induction),
            ChunkedPhaseAnalyzer.TimedClassification(start: 45, end: 90, phase: .deepening)
        ]

        let timeline = ChunkedPhaseAnalyzer.assembleTimeline(
            bucketCount: 90,
            classifications: classifications
        )

        #expect(timeline[20] == .induction)
        #expect(timeline[70] == .deepening)
    }
}

// MARK: - consolidatePhaseSegments

struct ChunkedConsolidateTests {

    @Test func uniformTimelineProducesOneSegment() {
        let timeline: [HypnosisMetadata.Phase?] = Array(repeating: .therapy, count: 120)
        let segments = ChunkedPhaseAnalyzer.consolidatePhaseSegments(timeline: timeline, duration: 120)
        #expect(segments.count == 1)
        #expect(segments[0].phase == .therapy)
    }

    @Test func lastSegmentEndsAtDuration() {
        let timeline: [HypnosisMetadata.Phase?] = Array(repeating: .induction, count: 10)
        let segments = ChunkedPhaseAnalyzer.consolidatePhaseSegments(timeline: timeline, duration: 600)
        #expect(segments.last?.endTime == 600)
    }

    @Test func emptyTimelineReturnsEmpty() {
        let segments = ChunkedPhaseAnalyzer.consolidatePhaseSegments(timeline: [], duration: 60)
        #expect(segments.isEmpty)
    }

    @Test func segmentsHaveHighConfidence() {
        let timeline: [HypnosisMetadata.Phase?] = [.preTalk, .preTalk, .therapy, .therapy]
        let segments = ChunkedPhaseAnalyzer.consolidatePhaseSegments(timeline: timeline, duration: 4)
        for seg in segments {
            #expect(seg.confidenceLevel == .high, "AI-sourced segments must be .high confidence")
        }
    }

    @Test func consecutiveDifferentPhasesProduceMultipleSegments() {
        var timeline: [HypnosisMetadata.Phase?] = Array(repeating: .preTalk, count: 30)
        timeline += Array(repeating: .therapy, count: 30)
        timeline += Array(repeating: .emergence, count: 30)
        let segments = ChunkedPhaseAnalyzer.consolidatePhaseSegments(timeline: timeline, duration: 90)
        #expect(segments.count == 3)
        #expect(segments[0].phase == .preTalk)
        #expect(segments[1].phase == .therapy)
        #expect(segments[2].phase == .emergence)
    }
}

// MARK: - tranceDepthForPhase

struct TranceDepthTests {

    @Test func preTalkIsNearlySurface() {
        #expect(ChunkedPhaseAnalyzer.tranceDepthForPhase(.preTalk) == TrancePhase.preTalk.tranceDepthEstimate)
    }

    @Test func therapyIsDeepest() {
        let therapy = ChunkedPhaseAnalyzer.tranceDepthForPhase(.therapy)
        let others: [HypnosisMetadata.Phase] = [.preTalk, .induction, .deepening, .suggestions, .conditioning, .emergence]
        for phase in others {
            #expect(therapy > ChunkedPhaseAnalyzer.tranceDepthForPhase(phase),
                "therapy must have greatest trance depth; \(phase.rawValue) was deeper")
        }
    }

    @Test func emergenceIsShallowerThanTherapy() {
        let emergence = ChunkedPhaseAnalyzer.tranceDepthForPhase(.emergence)
        let therapy   = ChunkedPhaseAnalyzer.tranceDepthForPhase(.therapy)
        #expect(emergence < therapy)
    }

    @Test func allPhasesWithinRange() {
        let phases: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence, .transitional
        ]
        for phase in phases {
            let depth = ChunkedPhaseAnalyzer.tranceDepthForPhase(phase)
            #expect(depth >= 0.0 && depth <= 1.0,
                "\(phase.rawValue) depth \(depth) is out of [0, 1]")
        }
    }
}
