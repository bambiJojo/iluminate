//
//  StructuralMergerTests.swift
//  IlumionateTests
//
//  The detector over-segments by design: against the labelled corpus it finds
//  50% of boundaries but proposes two to three times too many. Under-prediction
//  would be unrecoverable; over-prediction can be merged back.
//
//  Merging cannot improve recall — it only removes boundaries — so its entire
//  value is removing false positives while keeping the true ones. That needs
//  evidence the novelty curve does not have: novelty is measured in a fixed
//  window around a point, while a merge compares two whole segments. Two
//  stretches either side of a locally-novel seam can be globally identical.
//

import Testing
import Foundation
@testable import Ilumionate

private func frames(
    _ pattern: [(term: String, count: Int)],
    width: TimeInterval = 12
) -> [StructuralFrame] {
    var result: [StructuralFrame] = []
    var index = 0
    for entry in pattern {
        for _ in 0..<entry.count {
            result.append(
                StructuralFrame(
                    startTime: Double(index) * width,
                    endTime: Double(index + 1) * width,
                    prosody: [],
                    terms: [entry.term: 1.0]
                )
            )
            index += 1
        }
    }
    return result
}

private func segmentation(
    frames: [StructuralFrame],
    boundaries: [Int],
    countingRuns: [CountingRun] = []
) -> StructuralSegmentation {
    let starts = [0] + boundaries
    let segments = starts.enumerated().map { position, start -> StructuralSegment in
        let end = position + 1 < starts.count ? starts[position + 1] : frames.count
        return StructuralSegment(
            startTime: frames[start].startTime,
            endTime: frames[end - 1].endTime,
            confidence: start == 0 ? 0 : 0.3
        )
    }
    return StructuralSegmentation(
        segments: segments,
        frames: frames,
        novelty: Array(repeating: 0.3, count: frames.count),
        countingRuns: countingRuns
    )
}

struct StructuralMergerTests {

    /// The core case: a boundary cutting one homogeneous stretch in half.
    @Test("Adjacent segments describing the same material are merged")
    func identicalNeighboursMerge() {
        let input = segmentation(
            frames: frames([("deeper", 20)]),
            boundaries: [10]
        )

        let merged = StructuralMerger.merge(input)

        #expect(merged.segments.count == 1)
        #expect(merged.segments.first?.startTime == 0)
        #expect(merged.segments.first?.endTime == input.segments.last?.endTime)
    }

    @Test("A genuine change between segments is kept")
    func contrastingNeighboursSurvive() {
        let input = segmentation(
            frames: frames([("sinking", 10), ("awake", 10)]),
            boundaries: [10]
        )

        #expect(StructuralMerger.merge(input).segments.count == 2)
    }

    /// A count is deterministic evidence; a similarity score must not overrule it.
    @Test("A counting-anchored boundary is never merged away")
    func countingAnchorSurvivesMerging() {
        let width = StructuralFrames.defaultFrameDuration
        let input = segmentation(
            frames: frames([("deeper", 20)]),
            boundaries: [10],
            countingRuns: [
                CountingRun(
                    direction: .ascending,
                    startTime: 10 * width,
                    endTime: 10 * width + 8,
                    length: 5
                )
            ]
        )

        #expect(StructuralMerger.merge(input).segments.count == 2)
    }

    /// The property the whole design exists for, preserved through merging.
    @Test("A uniform file collapses to a single segment")
    func uniformFileCollapses() {
        let input = segmentation(
            frames: frames([("deeper", 40)]),
            boundaries: [8, 16, 24, 32]
        )

        #expect(StructuralMerger.merge(input).segments.count == 1)
    }

    @Test("Real structure is not merged into one segment")
    func realStructureIsNotFlattened() {
        let input = segmentation(
            frames: frames([("welcome", 10), ("sinking", 10), ("suggest", 10), ("awake", 10)]),
            boundaries: [10, 20, 30]
        )

        #expect(StructuralMerger.merge(input).segments.count == 4)
    }

    @Test("Merged segments still tile the file with no gaps")
    func mergedSegmentsTile() {
        let input = segmentation(
            frames: frames([("a", 6), ("a", 6), ("b", 8)]),
            boundaries: [6, 12]
        )

        let merged = StructuralMerger.merge(input)
        #expect(merged.segments.first?.startTime == 0)
        #expect(merged.segments.last?.endTime == input.segments.last?.endTime)
        for (earlier, later) in zip(merged.segments, merged.segments.dropFirst()) {
            #expect(earlier.endTime == later.startTime)
        }
    }

    @Test("The evidence survives merging")
    func evidenceIsCarriedThrough() {
        let input = segmentation(frames: frames([("deeper", 20)]), boundaries: [10])
        let merged = StructuralMerger.merge(input)

        #expect(merged.frames.count == input.frames.count)
        #expect(merged.novelty.count == input.novelty.count)
    }

    @Test("A single segment is returned unchanged")
    func singleSegmentIsUnchanged() {
        let input = segmentation(frames: frames([("deeper", 10)]), boundaries: [])
        #expect(StructuralMerger.merge(input).segments.count == 1)
    }

    @Test("An empty segmentation stays empty")
    func emptyStaysEmpty() {
        let empty = StructuralSegmentation(segments: [], frames: [], novelty: [], countingRuns: [])
        #expect(StructuralMerger.merge(empty).segments.isEmpty)
    }
}
