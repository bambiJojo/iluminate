//
//  HypnosisPhaseAnalyzerTests.swift
//  IlumionateTests
//
//  Tests for Step 3.1: HypnosisPhaseAnalyzer pure functions.
//  All functions under test are deterministic and have no side effects.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Helpers

private func makeWord(_ text: String, at time: Double, dur: Double = 1.0) -> WordTimestamp {
    WordTimestamp(word: text, startTime: time, duration: dur)
}

private func makeSegment(text: String, start: Double, duration: Double) -> AudioTranscriptionSegment {
    AudioTranscriptionSegment(text: text, timestamp: start, duration: duration, confidence: 1.0)
}

// MARK: - approximateWordTimestamps Tests

struct ApproximateWordTimestampsTests {

    private let analyzer = HypnosisPhaseAnalyzer()

    @Test func emptySegmentsReturnsEmpty() {
        let result = analyzer.approximateWordTimestamps(from: [])
        #expect(result.isEmpty)
    }

    @Test func singleWordSegmentProducesOneTimestamp() {
        let seg = makeSegment(text: "relax", start: 0, duration: 2.0)
        let result = analyzer.approximateWordTimestamps(from: [seg])
        #expect(result.count == 1)
        #expect(result[0].word == "relax")
        #expect(abs(result[0].startTime - 0.0) < 0.001)
    }

    @Test func twoWordSegmentDistributesEvenly() {
        let seg = makeSegment(text: "deeply relax", start: 10.0, duration: 4.0)
        let result = analyzer.approximateWordTimestamps(from: [seg])
        #expect(result.count == 2)
        // Each word gets 4.0/2 = 2.0 seconds
        #expect(abs(result[0].startTime - 10.0) < 0.001)
        #expect(abs(result[1].startTime - 12.0) < 0.001)
    }

    @Test func multipleSegmentsProduceConcatenatedTimestamps() {
        let segments = [
            makeSegment(text: "relax now", start: 0, duration: 2.0),
            makeSegment(text: "breathe deeply", start: 5.0, duration: 4.0)
        ]
        let result = analyzer.approximateWordTimestamps(from: segments)
        #expect(result.count == 4)
    }

    @Test func emptyTextSegmentIsSkipped() {
        let segments = [
            makeSegment(text: "", start: 0, duration: 1.0),
            makeSegment(text: "relax", start: 2.0, duration: 1.0)
        ]
        let result = analyzer.approximateWordTimestamps(from: segments)
        #expect(result.count == 1)
    }
}

// MARK: - enforcePhaseOrdering Tests

struct EnforcePhaseOrderingTests {

    private let analyzer = HypnosisPhaseAnalyzer()

    @Test func alreadyOrderedTimelinePassesThrough() {
        let timeline: [HypnosisMetadata.Phase?] = [.preTalk, .induction, .deepening, .therapy, .emergence]
        let result = analyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result == timeline)
    }

    @Test func backwardJumpIsCorrectedToCurrentMax() {
        // therapy followed by induction is illegal — should become therapy
        let timeline: [HypnosisMetadata.Phase?] = [.therapy, .induction]
        let result = analyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result[0] == .therapy)
        #expect(result[1] == .therapy, "backward jump must be corrected")
    }

    @Test func nilBucketsArePreserved() {
        let timeline: [HypnosisMetadata.Phase?] = [.preTalk, nil, .induction]
        let result = analyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result[1] == nil, "nil buckets must remain nil")
    }

    @Test func highestPhaseIsTrackedAcrossNils() {
        // preTalk → nil → induction → nil → preTalk (backward) → must become induction
        let timeline: [HypnosisMetadata.Phase?] = [.preTalk, nil, .induction, nil, .preTalk]
        let result = analyzer.enforcePhaseOrdering(timeline: timeline)
        #expect(result[4] == .induction, "backward jump past nil gap must be corrected")
    }

    @Test func emptyTimelineReturnsEmpty() {
        let result = analyzer.enforcePhaseOrdering(timeline: [])
        #expect(result.isEmpty)
    }
}

// MARK: - majorityVoteSmooth Tests

struct MajorityVoteSmoothTests {

    private let analyzer = HypnosisPhaseAnalyzer()

    @Test func singleIsolatedPhaseSurroundedByDominantIsReplaced() {
        // Single .induction spike surrounded by .therapy
        let timeline: [HypnosisMetadata.Phase?] = [
            .therapy, .therapy, .induction, .therapy, .therapy
        ]
        let result = analyzer.majorityVoteSmooth(timeline: timeline, windowSize: 5)
        #expect(result[2] == .therapy, "single spike must be smoothed to dominant")
    }

    @Test func windowSizeOneReturnsIdentical() {
        let timeline: [HypnosisMetadata.Phase?] = [.preTalk, .induction, .therapy]
        let result = analyzer.majorityVoteSmooth(timeline: timeline, windowSize: 1)
        #expect(result == timeline)
    }

    @Test func nilGapsAreForwardFilled() {
        // Forward-fill only runs when windowSize > 1
        let timeline: [HypnosisMetadata.Phase?] = [.therapy, nil, nil, nil]
        let result = analyzer.majorityVoteSmooth(timeline: timeline, windowSize: 5)
        // After majority-vote + forward-fill, nils should be filled by therapy
        #expect(result.allSatisfy { $0 == .therapy })
    }

    @Test func emptyTimelineReturnsEmpty() {
        let result = analyzer.majorityVoteSmooth(timeline: [], windowSize: 5)
        #expect(result.isEmpty)
    }
}

// MARK: - consolidatePhaseSegments Tests

struct ConsolidatePhaseSegmentsTests {

    private let analyzer = HypnosisPhaseAnalyzer()

    @Test func singlePhaseProducesOneSegment() {
        let timeline: [HypnosisMetadata.Phase?] = Array(repeating: .therapy, count: 60)
        let segments = analyzer.consolidatePhaseSegments(timeline: timeline, duration: 60)
        #expect(segments.count == 1)
        #expect(segments[0].phase == .therapy)
        #expect(segments[0].startTime == 0)
        #expect(segments[0].endTime == 60)
    }

    @Test func twoPhasesProduceTwoSegments() {
        var timeline: [HypnosisMetadata.Phase?] = Array(repeating: .preTalk, count: 30)
        timeline += Array(repeating: .therapy, count: 30)
        let segments = analyzer.consolidatePhaseSegments(timeline: timeline, duration: 60)
        #expect(segments.count == 2)
        #expect(segments[0].phase == .preTalk)
        #expect(segments[1].phase == .therapy)
    }

    @Test func segmentsAreChronologicallyOrdered() {
        var timeline: [HypnosisMetadata.Phase?] = Array(repeating: .preTalk, count: 20)
        timeline += Array(repeating: .induction, count: 20)
        timeline += Array(repeating: .deepening, count: 20)
        let segments = analyzer.consolidatePhaseSegments(timeline: timeline, duration: 60)
        for idx in 0..<(segments.count - 1) {
            #expect(segments[idx].endTime <= segments[idx + 1].startTime,
                "segments must be chronologically ordered")
        }
    }

    @Test func lastSegmentEndsAtDuration() {
        let timeline: [HypnosisMetadata.Phase?] = Array(repeating: .emergence, count: 10)
        let segments = analyzer.consolidatePhaseSegments(timeline: timeline, duration: 300)
        #expect(segments.last?.endTime == 300, "last segment must end at session duration")
    }

    @Test func emptyTimelineReturnsEmpty() {
        let segments = analyzer.consolidatePhaseSegments(timeline: [], duration: 60)
        #expect(segments.isEmpty)
    }
}
