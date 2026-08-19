//
//  StructuralNoveltyTests.swift
//  IlumionateTests
//
//  The novelty curve is the piece that has to earn its keep: if a synthetic
//  file with an obvious seam does not peak at the seam, nothing downstream can
//  recover. These tests use hand-built frames so the expected answer is known
//  rather than eyeballed.
//

import Testing
import Foundation
@testable import Ilumionate

private func lexicalFrame(_ term: String, index: Int, width: TimeInterval = 12) -> StructuralFrame {
    StructuralFrame(
        startTime: Double(index) * width,
        endTime: Double(index + 1) * width,
        prosody: [],
        terms: [term: 1.0]
    )
}

private func prosodicFrame(_ values: [Double], index: Int, width: TimeInterval = 12) -> StructuralFrame {
    StructuralFrame(
        startTime: Double(index) * width,
        endTime: Double(index + 1) * width,
        prosody: values,
        terms: [:]
    )
}

struct StructuralNoveltyTests {

    /// The load-bearing test. Two homogeneous halves with a seam at frame 5.
    @Test("Novelty peaks at the seam between two contrasting halves")
    func peaksAtTheSeam() {
        let frames = (0..<10).map { index in
            lexicalFrame(index < 5 ? "induction" : "awakening", index: index)
        }

        let curve = StructuralNovelty.curve(frames: frames, kernelSize: 4)
        let peak = curve.enumerated().max { $0.element < $1.element }?.offset

        #expect(peak == 5)
    }

    @Test("The curve has one value per frame")
    func curveIsFrameAligned() {
        let frames = (0..<12).map { lexicalFrame("same", index: $0) }
        #expect(StructuralNovelty.curve(frames: frames, kernelSize: 4).count == 12)
    }

    /// This is what makes a zero-boundary answer possible: a file with no
    /// internal contrast must not manufacture a peak for the detector to find.
    @Test("A homogeneous file produces far less novelty than a seamed one")
    func homogeneousFileStaysFlat() {
        let flat = (0..<10).map { lexicalFrame("deeper", index: $0) }
        let seamed = (0..<10).map { index in
            lexicalFrame(index < 5 ? "deeper" : "awake", index: index)
        }

        let flatPeak = StructuralNovelty.curve(frames: flat, kernelSize: 4).max() ?? 0
        let seamedPeak = StructuralNovelty.curve(frames: seamed, kernelSize: 4).max() ?? 0

        #expect(flatPeak < seamedPeak * 0.2)
    }

    @Test("Prosodic contrast alone is enough to produce a peak")
    func prosodyOnlyDetectsTheSeam() {
        let frames = (0..<10).map { index in
            prosodicFrame(index < 5 ? [1.0, 1.0] : [-1.0, -1.0], index: index)
        }

        let curve = StructuralNovelty.curve(frames: frames, kernelSize: 4)
        #expect(curve.enumerated().max { $0.element < $1.element }?.offset == 5)
    }

    @Test("Fewer frames than the kernel returns zeros rather than crashing")
    func tinyInputIsSafe() {
        let curve = StructuralNovelty.curve(frames: [lexicalFrame("a", index: 0)], kernelSize: 8)
        #expect(curve == [0])
    }

    @Test("No frames yields no curve")
    func emptyInputIsEmpty() {
        #expect(StructuralNovelty.curve(frames: [], kernelSize: 4).isEmpty)
    }

    @Test("Novelty is never negative, so peak picking has a usable floor")
    func noveltyIsNonNegative() {
        let frames = (0..<10).map { index in
            lexicalFrame(["a", "b", "c"][index % 3], index: index)
        }
        #expect(StructuralNovelty.curve(frames: frames, kernelSize: 4).allSatisfy { $0 >= 0 })
    }
}
