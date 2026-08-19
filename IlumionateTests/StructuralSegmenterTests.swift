//
//  StructuralSegmenterTests.swift
//  IlumionateTests
//
//  The behaviour that matters most here is the one the current pipeline cannot
//  express: a file with no internal structure must come back as one segment,
//  not as a failure. ChunkedPhaseAnalyzer treats a single phase as a fault
//  (`distinctCount >= 2`), which makes a pure deepener indistinguishable from a
//  crash. These tests pin the opposite behaviour.
//

import Testing
import Foundation
@testable import Ilumionate

private func repeated(
    _ phrase: String,
    from start: Double,
    to end: Double,
    rate: Double = 1
) -> [WordTimestamp] {
    let tokens = phrase.split(separator: " ").map(String.init)
    var words: [WordTimestamp] = []
    var time = start
    var index = 0
    while time < end {
        words.append(
            WordTimestamp(word: tokens[index % tokens.count], startTime: time, duration: rate * 0.7)
        )
        time += rate
        index += 1
    }
    return words
}

struct StructuralSegmenterTests {

    /// The case the whole design exists for.
    @Test("A file with no internal contrast returns exactly one segment")
    func pureDeepenerIsOneSegment() {
        let words = repeated("deeper and deeper down you drift", from: 0, to: 600)

        let result = StructuralSegmenter.segment(words: words, prosody: nil, duration: 600)

        #expect(result.segments.count == 1)
        #expect(result.segments.first?.startTime == 0)
        #expect(result.segments.first?.endTime == 600)
    }

    @Test("A file with two contrasting halves splits near the seam")
    func contrastingHalvesSplit() {
        let first = repeated("sinking heavy warm calm still", from: 0, to: 300)
        let second = repeated("bright energy rising alert awake", from: 300, to: 600)

        let result = StructuralSegmenter.segment(words: first + second, prosody: nil, duration: 600)

        #expect(result.segments.count == 2)
        let boundary = try! #require(result.segments.last?.startTime)
        #expect(abs(boundary - 300) <= StructuralFrames.defaultFrameDuration)
    }

    /// A count is strong enough evidence to place a boundary even where the
    /// vocabulary either side is otherwise identical.
    @Test("A counting run places a boundary that novelty alone would miss")
    func countingAnchorsABoundary() {
        var words = repeated("deeper and deeper down you drift", from: 0, to: 600)
        words += [
            WordTimestamp(word: "one", startTime: 300, duration: 0.5),
            WordTimestamp(word: "two", startTime: 302, duration: 0.5),
            WordTimestamp(word: "three", startTime: 304, duration: 0.5),
            WordTimestamp(word: "four", startTime: 306, duration: 0.5),
            WordTimestamp(word: "five", startTime: 308, duration: 0.5)
        ]

        let result = StructuralSegmenter.segment(
            words: words.sorted { $0.startTime < $1.startTime },
            prosody: nil,
            duration: 600
        )

        #expect(result.segments.count >= 2)
        #expect(result.countingRuns.contains { $0.direction == .ascending })
    }

    @Test("Segments tile the file with no gaps or overlaps")
    func segmentsTileTheFile() {
        let first = repeated("sinking heavy warm calm still", from: 0, to: 300)
        let second = repeated("bright energy rising alert awake", from: 300, to: 600)

        let result = StructuralSegmenter.segment(words: first + second, prosody: nil, duration: 600)

        #expect(result.segments.first?.startTime == 0)
        #expect(result.segments.last?.endTime == 600)
        for (earlier, later) in zip(result.segments, result.segments.dropFirst()) {
            #expect(earlier.endTime == later.startTime)
        }
    }

    @Test("No segment is shorter than the minimum")
    func minimumSegmentLengthIsRespected() {
        var words: [WordTimestamp] = []
        // Vocabulary churning every 12 seconds: maximally noisy novelty.
        for block in 0..<50 {
            words += repeated("w\(block)", from: Double(block) * 12, to: Double(block + 1) * 12)
        }

        let result = StructuralSegmenter.segment(words: words, prosody: nil, duration: 600)

        for segment in result.segments {
            #expect(segment.endTime - segment.startTime >= StructuralSegmenter.minimumSegmentDuration)
        }
    }

    @Test("An empty transcript yields no segments rather than a crash")
    func emptyInputIsEmpty() {
        let result = StructuralSegmenter.segment(words: [], prosody: nil, duration: 0)
        #expect(result.segments.isEmpty)
    }

    @Test("A file shorter than one segment is not split")
    func veryShortFileIsOneSegment() {
        let words = repeated("brief calm words here", from: 0, to: 30)
        let result = StructuralSegmenter.segment(words: words, prosody: nil, duration: 30)

        #expect(result.segments.count == 1)
    }

    /// The novelty curve is retained so the offline harness can plot what the
    /// detector saw, rather than only what it concluded.
    @Test("The result carries the evidence it decided from")
    func evidenceIsRetained() {
        let words = repeated("calm still quiet", from: 0, to: 240)
        let result = StructuralSegmenter.segment(words: words, prosody: nil, duration: 240)

        #expect(result.novelty.isEmpty == false)
        #expect(result.novelty.count == result.frames.count)
    }
}
