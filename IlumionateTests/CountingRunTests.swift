//
//  CountingRunTests.swift
//  IlumionateTests
//
//  Counting is the one structural signal in a hypnosis file that is close to
//  deterministic: deepeners count down, awakenings count up. The risk is not
//  missing a run, it is firing on ordinary speech — "one of my files" opens one
//  of the user's own transcripts — so the false-positive cases carry more
//  weight here than the happy path.
//

import Testing
import Foundation
@testable import Ilumionate

private func spoken(_ text: String, from start: Double = 0, spacing: Double = 1) -> [WordTimestamp] {
    text.split(separator: " ").enumerated().map { index, word in
        WordTimestamp(
            word: String(word),
            startTime: start + Double(index) * spacing,
            duration: spacing * 0.7
        )
    }
}

struct CountingRunTests {

    @Test("A descending count is a deepener anchor")
    func descendingCountIsDetected() {
        let runs = CountingRunDetector.runs(in: spoken("ten nine eight seven six five"))

        #expect(runs.count == 1)
        #expect(runs.first?.direction == .descending)
        #expect(runs.first?.length == 6)
    }

    @Test("An ascending count is an awakening anchor")
    func ascendingCountIsDetected() {
        let runs = CountingRunDetector.runs(in: spoken("one two three four five wide awake"))

        #expect(runs.count == 1)
        #expect(runs.first?.direction == .ascending)
    }

    /// The false positive that matters: this phrase opens a real transcript in
    /// the user's library.
    @Test("An isolated number in ordinary speech is not a count")
    func incidentalNumberDoesNotFire() {
        #expect(CountingRunDetector.runs(in: spoken("welcome back to one of my files")).isEmpty)
    }

    @Test("Two numbers are not enough to call it counting")
    func shortRunIsRejected() {
        #expect(CountingRunDetector.runs(in: spoken("one two and then we begin")).isEmpty)
    }

    @Test("Digits count the same as words")
    func digitsAreRecognised() {
        let runs = CountingRunDetector.runs(in: spoken("10 9 8 7"))
        #expect(runs.first?.direction == .descending)
    }

    /// Hypnosis counting repeats for emphasis — "ten... ten... nine" — and a
    /// repeat must not end the run.
    @Test("A repeated number does not break a run")
    func repeatsAreTolerated() {
        let runs = CountingRunDetector.runs(in: spoken("ten ten nine eight seven"))

        #expect(runs.count == 1)
        #expect(runs.first?.direction == .descending)
    }

    @Test("Speech between numbers keeps the run intact")
    func interveningWordsAreIgnored() {
        let runs = CountingRunDetector.runs(
            in: spoken("ten drifting down nine deeper still eight so heavy seven")
        )

        #expect(runs.count == 1)
        #expect(runs.first?.length == 4)
    }

    /// Without a gap limit, "chapter one" and a "two" minutes later would chain
    /// into a phantom count spanning the file.
    @Test("A long silence between numbers splits the run")
    func longGapSplitsTheRun() {
        let early = spoken("ten nine eight", from: 0, spacing: 1)
        let late = spoken("seven six five", from: 600, spacing: 1)

        let runs = CountingRunDetector.runs(in: early + late)
        #expect(runs.count == 2)
    }

    @Test("A file can carry both a deepener and an awakening")
    func bothDirectionsCoexist() {
        let down = spoken("ten nine eight seven", from: 0, spacing: 1)
        let up = spoken("one two three four five", from: 100, spacing: 1)

        let runs = CountingRunDetector.runs(in: down + up)
        #expect(runs.map(\.direction) == [.descending, .ascending])
    }

    @Test("The run spans from its first number to its last")
    func runCarriesItsTimeSpan() {
        let runs = CountingRunDetector.runs(in: spoken("five four three two", from: 30, spacing: 2))

        #expect(runs.first?.startTime == 30)
        #expect(runs.first?.endTime == 36)
    }

    @Test("No words means no runs")
    func emptyInputIsEmpty() {
        #expect(CountingRunDetector.runs(in: []).isEmpty)
    }
}
