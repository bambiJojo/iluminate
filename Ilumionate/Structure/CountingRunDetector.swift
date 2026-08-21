//
//  CountingRunDetector.swift
//  Ilumionate
//
//  Finds counted sequences in a transcript.
//
//  Almost every structural signal in a hypnosis file is ambiguous — "your eyes
//  are getting heavier" belongs to an induction and a deepening equally. Counting
//  is the exception, and it is nearly deterministic: deepeners count *down*,
//  awakenings count *up* and finish awake. Where a count exists it fixes a
//  boundary to the second, for free, with no model involved.
//
//  The risk is the opposite of missing one. Numbers appear constantly in
//  ordinary speech, so a run must be long enough and tight enough in time that
//  "one of my files" — which opens a real transcript in the library — cannot be
//  mistaken for the start of an induction.
//

import Foundation

nonisolated struct CountingRun: Sendable, Equatable {
    enum Direction: Sendable, Equatable {
        /// Counting down. Characteristic of inductions and deepeners.
        case descending
        /// Counting up. Characteristic of awakenings.
        case ascending
    }

    let direction: Direction
    /// Onset of the first number in the run.
    let startTime: TimeInterval
    /// Onset of the final number. Deliberately the onset rather than the end of
    /// the spoken word: a boundary anchor does not need sub-second precision,
    /// and onset-to-onset keeps the span exactly comparable to word timings.
    let endTime: TimeInterval
    /// How many numbers the run contains, repeats excluded.
    let length: Int
}

nonisolated enum CountingRunDetector {

    /// Two numbers in sequence happen by accident constantly ("one or two
    /// things"). Three in strict order, close together, essentially do not.
    static let minimumRunLength = 3

    /// Counting in a deepener is slow, and a suggestion can sit between two
    /// numbers. This is generous enough to survive that, and short enough that
    /// numbers minutes apart cannot chain into a count spanning the file.
    static let maximumGapBetweenNumbers: TimeInterval = 45

    static func runs(in words: [WordTimestamp]) -> [CountingRun] {
        let numbers = words.compactMap { word -> (value: Int, time: TimeInterval)? in
            guard let value = numericValue(word.word) else { return nil }
            return (value, word.startTime)
        }
        guard numbers.count >= minimumRunLength else { return [] }

        var found: [CountingRun] = []
        var current: [(value: Int, time: TimeInterval)] = []
        var direction: CountingRun.Direction?

        func flush() {
            if let direction, let first = current.first, let last = current.last,
               current.count >= minimumRunLength {
                found.append(
                    CountingRun(
                        direction: direction,
                        startTime: first.time,
                        endTime: last.time,
                        length: current.count
                    )
                )
            }
            current = []
            direction = nil
        }

        for entry in numbers {
            guard let previous = current.last else {
                current = [entry]
                continue
            }

            if entry.time - previous.time > maximumGapBetweenNumbers {
                flush()
                current = [entry]
                continue
            }

            let step = entry.value - previous.value
            // "Ten... ten... nine" is emphasis, not the end of the count.
            if step == 0 { continue }

            let stepDirection: CountingRun.Direction = step < 0 ? .descending : .ascending
            if abs(step) == 1, direction == nil || direction == stepDirection {
                direction = stepDirection
                current.append(entry)
            } else {
                flush()
                current = [entry]
            }
        }
        flush()

        return found
    }

    // MARK: - Fractionation

    /// How close two opposite-direction counts must be to read as one bout.
    ///
    /// Fractionation cycles are minutes, not seconds — the subject is taken down,
    /// brought up and taken down again — but a deepener at the start of a session
    /// and the closing awakener half an hour later are not a cycle. This is the
    /// line between the two, and it is a judgement rather than a measurement:
    /// the corpus has no file with fractionation labelled *within* it.
    static let maximumFractionationGap: TimeInterval = 420

    /// Stretches where counting alternates direction in quick succession.
    ///
    /// Fractionation is induction applied repeatedly — down, up, down, each pass
    /// landing deeper — so it is identifiable from the *shape* of the counting
    /// rather than from where it sits in the file. That matters: nothing in the
    /// corpus shows where fractionation occurs within a file, so a positional
    /// prior could not be checked, while this follows from what the technique is.
    static func fractionationWindows(
        in runs: [CountingRun]
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        let ordered = runs.sorted { $0.startTime < $1.startTime }
        guard ordered.count > 1 else { return [] }

        var windows: [(start: TimeInterval, end: TimeInterval)] = []
        var current: [CountingRun] = []

        func flush() {
            if current.count > 1, let first = current.first, let last = current.last {
                windows.append((first.startTime, last.endTime))
            }
            current = []
        }

        for run in ordered {
            guard let previous = current.last else {
                current = [run]
                continue
            }
            let alternates = previous.direction != run.direction
            let close = run.startTime - previous.endTime <= maximumFractionationGap
            if alternates, close {
                current.append(run)
            } else {
                flush()
                current = [run]
            }
        }
        flush()

        return windows
    }

    // MARK: - Numerals

    /// Counts in this material stay inside one to twenty; a "thirty" is far more
    /// likely to be a duration than a step in a count.
    private static let spelled: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20
    ]

    static func numericValue(_ word: String) -> Int? {
        let token = word.lowercased().filter { $0.isLetter || $0.isNumber }
        guard token.isEmpty == false else { return nil }
        if let spelledValue = spelled[token] { return spelledValue }
        guard let digits = Int(token), (0...20).contains(digits) else { return nil }
        return digits
    }
}
