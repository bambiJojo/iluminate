//
//  StructuralReportTests.swift
//  IlumionateTests
//

import Testing
import Foundation
@testable import Ilumionate

struct StructuralReportTests {

    private func segmentation(
        segments: [StructuralSegment],
        runs: [CountingRun] = []
    ) -> StructuralSegmentation {
        StructuralSegmentation(segments: segments, frames: [], novelty: [], countingRuns: runs)
    }

    @Test("Clock formatting pads seconds")
    func clockPadsSeconds() {
        #expect(StructuralReport.clock(65) == "1:05")
        #expect(StructuralReport.clock(600) == "10:00")
        #expect(StructuralReport.clock(0) == "0:00")
    }

    @Test("Every segment gets a line")
    func eachSegmentIsListed() {
        let text = StructuralReport.text(
            for: segmentation(segments: [
                StructuralSegment(startTime: 0, endTime: 300, confidence: 0),
                StructuralSegment(startTime: 300, endTime: 600, confidence: 0.42)
            ]),
            filename: "Track.mp3"
        )

        #expect(text.contains("Track.mp3"))
        #expect(text.contains("2 segment(s)"))
        #expect(text.contains("0:00–5:00"))
        #expect(text.contains("5:00–10:00"))
    }

    @Test("A counting run is named beside the boundary it justified")
    func countingRunIsAttributed() {
        let text = StructuralReport.text(
            for: segmentation(
                segments: [
                    StructuralSegment(startTime: 0, endTime: 300, confidence: 0),
                    StructuralSegment(startTime: 300, endTime: 600, confidence: 0.1)
                ],
                runs: [
                    CountingRun(direction: .ascending, startTime: 300, endTime: 310, length: 5)
                ]
            ),
            filename: "Track.mp3"
        )

        #expect(text.contains("count up"))
    }

    @Test("An empty segmentation reports rather than renders nothing")
    func emptySegmentationIsExplained() {
        let text = StructuralReport.text(for: segmentation(segments: []), filename: "Track.mp3")
        #expect(text.contains("no segments"))
    }
}
