//
//  AIAttemptSummaryTests.swift
//  IlumionateTests
//
//  Game Mode refuses Foundation Models requests for the foreground app. The
//  open question is whether analysis running while LumeSync is backgrounded is
//  refused too. These cover the arithmetic that answers it, so the device run
//  produces a verdict rather than a log to squint at.
//

import Testing
import Foundation
@testable import Ilumionate

private func attempt(
    _ state: AIRunActivationState,
    diagnosis: AIGenerationDiagnosis.Kind? = nil,
    filename: String = "Session.mp3"
) -> AIAttemptRecord {
    AIAttemptRecord(
        filename: filename,
        activationState: state,
        diagnosis: diagnosis,
        at: Date(timeIntervalSince1970: 0)
    )
}

struct AIAttemptSummaryTests {

    @Test func noAttemptsIsInconclusive() {
        let summary = AIAttemptSummary(records: [])
        #expect(summary.verdict == .noData)
    }

    @Test func attemptsInOnlyOneStateCannotCompare() {
        let summary = AIAttemptSummary(records: [
            attempt(.foreground, diagnosis: .systemBusy),
            attempt(.foreground, diagnosis: .systemBusy)
        ])
        #expect(summary.verdict == .needsBackgroundSamples)
    }

    /// The result that would justify keeping Game Mode and moving analysis into
    /// the background rather than opting out of Game Mode entirely.
    @Test func backgroundSucceedingWhileForegroundIsBlockedIsDecisive() {
        let summary = AIAttemptSummary(records: [
            attempt(.foreground, diagnosis: .systemBusy),
            attempt(.foreground, diagnosis: .systemBusy),
            attempt(.background),
            attempt(.background)
        ])
        #expect(summary.verdict == .backgroundAvoidsTheBlock)
    }

    /// If backgrounding is refused too, scheduling cannot help and the only
    /// lever left is declining Game Mode.
    @Test func bothStatesBlockedMeansSchedulingCannotHelp() {
        let summary = AIAttemptSummary(records: [
            attempt(.foreground, diagnosis: .systemBusy),
            attempt(.background, diagnosis: .systemBusy)
        ])
        #expect(summary.verdict == .blockedInBothStates)
    }

    @Test func successInBothStatesMeansGameModeIsNotTheConstraint() {
        let summary = AIAttemptSummary(records: [
            attempt(.foreground),
            attempt(.background)
        ])
        #expect(summary.verdict == .notBlocked)
    }

    /// Only systemBusy indicates the Game Mode refusal. A context overflow in
    /// the background says nothing about Game Mode and must not be counted as
    /// evidence either way.
    @Test func unrelatedFailuresDoNotCountAsBlocked() {
        let summary = AIAttemptSummary(records: [
            attempt(.foreground, diagnosis: .systemBusy),
            attempt(.background, diagnosis: .contextWindow)
        ])
        #expect(summary.verdict == .needsBackgroundSamples)
    }

    @Test func summaryCountsPerState() {
        let summary = AIAttemptSummary(records: [
            attempt(.foreground, diagnosis: .systemBusy),
            attempt(.foreground),
            attempt(.background),
            attempt(.background),
            attempt(.background, diagnosis: .systemBusy)
        ])
        #expect(summary.total(in: .foreground) == 2)
        #expect(summary.usedAI(in: .foreground) == 1)
        #expect(summary.total(in: .background) == 3)
        #expect(summary.usedAI(in: .background) == 2)
        #expect(summary.blocked(in: .background) == 1)
    }

    @Test func descriptionReportsBothStatesAndTheVerdict() {
        let summary = AIAttemptSummary(records: [
            attempt(.foreground, diagnosis: .systemBusy),
            attempt(.background)
        ])
        let text = summary.description

        #expect(text.contains("foreground 0/1"))
        #expect(text.contains("background 1/1"))
        #expect(text.contains("backgrounding avoids the block"))
    }
}
