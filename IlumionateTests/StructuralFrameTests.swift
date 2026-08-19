//
//  StructuralFrameTests.swift
//  IlumionateTests
//
//  Frames are the input to every later stage, so their failure modes matter
//  more than their happy path: a file with no prosodic profile, a curve that
//  never varies, and a frame grid that does not divide the duration evenly are
//  all ordinary, not exceptional.
//

import Testing
import Foundation
@testable import Ilumionate

private func words(_ text: String, startingAt start: Double, spacing: Double = 0.5) -> [WordTimestamp] {
    text.split(separator: " ").enumerated().map { index, word in
        WordTimestamp(
            word: String(word),
            startTime: start + Double(index) * spacing,
            duration: spacing * 0.8
        )
    }
}

private func profile(
    windowDuration: TimeInterval = 3,
    speechRate: [Double],
    totalDuration: TimeInterval
) -> ProsodicProfile {
    ProsodicProfile(
        windowDuration: windowDuration,
        speechRateCurve: speechRate,
        volumeCurve: speechRate.map { _ in 0.5 },
        pitchCurve: speechRate.map { _ in 120 },
        speechSilenceRatio: speechRate.map { _ in 0.8 },
        pauses: [],
        totalDuration: totalDuration
    )
}

struct StructuralFrameTests {

    @Test("Frames tile the whole file at the requested resolution")
    func framesCoverTheDuration() {
        let frames = StructuralFrames.build(
            words: words("one two three four five six seven eight", startingAt: 0),
            prosody: nil,
            duration: 60,
            frameDuration: 10
        )

        #expect(frames.count == 6)
        #expect(frames.first?.startTime == 0)
        #expect(frames.last?.endTime == 60)
    }

    /// `prosodicProfile` is optional on `AnalysisResult`, so lexical-only is a
    /// supported mode rather than a degraded one.
    @Test("A file with no prosodic profile still produces lexical frames")
    func lexicalOnlyIsSupported() {
        let frames = StructuralFrames.build(
            words: words("deeper and deeper down you go", startingAt: 0),
            prosody: nil,
            duration: 20,
            frameDuration: 10
        )

        #expect(frames.count == 2)
        #expect(frames[0].terms.isEmpty == false)
        #expect(frames[0].prosody.isEmpty)
    }

    @Test("Terms are attributed to the frame containing the word")
    func termsLandInTheRightFrame() {
        let frames = StructuralFrames.build(
            words: words("alpha beta", startingAt: 0, spacing: 12),
            prosody: nil,
            duration: 24,
            frameDuration: 12
        )

        #expect(frames[0].terms.keys.contains("alpha"))
        #expect(frames[0].terms.keys.contains("beta") == false)
        #expect(frames[1].terms.keys.contains("beta"))
    }

    @Test("Prosodic dimensions are z-normalised across frames")
    func prosodyIsNormalised() {
        let frames = StructuralFrames.build(
            words: words("a b c d e f g h", startingAt: 0, spacing: 5),
            prosody: profile(speechRate: [100, 100, 100, 100, 20, 20, 20, 20], totalDuration: 24),
            duration: 24,
            frameDuration: 12
        )

        let rates = frames.map { $0.prosody[0] }
        // Opposite signs: the fast half above the mean, the slow half below.
        #expect(rates[0] > 0)
        #expect(rates[1] < 0)
    }

    /// A constant curve carries no boundary information. Dividing by a zero
    /// standard deviation would make it NaN and poison every later similarity.
    @Test("A curve that never varies normalises to zero rather than NaN")
    func constantCurveDoesNotProduceNaN() {
        let frames = StructuralFrames.build(
            words: words("a b c d", startingAt: 0, spacing: 5),
            prosody: profile(speechRate: [90, 90, 90, 90], totalDuration: 12),
            duration: 12,
            frameDuration: 6
        )

        #expect(frames.allSatisfy { $0.prosody.allSatisfy { $0.isNaN == false } })
        #expect(frames[0].prosody[0] == 0)
    }

    @Test("A file shorter than one frame still yields a single frame")
    func shortFileYieldsOneFrame() {
        let frames = StructuralFrames.build(
            words: words("brief", startingAt: 0),
            prosody: nil,
            duration: 4,
            frameDuration: 10
        )

        #expect(frames.count == 1)
        #expect(frames[0].endTime == 4)
    }

    @Test("No words and no prosody yields no frames rather than a crash")
    func emptyInputIsEmpty() {
        #expect(StructuralFrames.build(words: [], prosody: nil, duration: 0, frameDuration: 10).isEmpty)
    }
}
