//
//  AnalysisReassuranceTests.swift
//  IlumionateTests
//
//  Tests for the "still working, hang in there" reassurance shown during
//  long analyses, and for the analysis task-priority policy.
//

import Testing
import Foundation
import Observation
@testable import Ilumionate

struct AnalysisReassuranceTests {

    // MARK: - Activation threshold

    @Test func noMessageBeforeActivationDelay() {
        #expect(AnalysisReassurance.message(elapsed: 0) == nil)
        #expect(AnalysisReassurance.message(elapsed: 10) == nil)
        #expect(AnalysisReassurance.message(elapsed: AnalysisReassurance.activationDelay - 0.1) == nil)
    }

    @Test func messageAppearsAtActivationDelay() {
        let message = AnalysisReassurance.message(elapsed: AnalysisReassurance.activationDelay)
        #expect(message == AnalysisReassurance.messages.first)
    }

    // MARK: - Rotation

    @Test func messageRotatesAfterEachInterval() {
        let start = AnalysisReassurance.activationDelay
        let interval = AnalysisReassurance.rotationInterval

        for (index, expected) in AnalysisReassurance.messages.enumerated() {
            let elapsed = start + interval * Double(index)
            #expect(AnalysisReassurance.message(elapsed: elapsed) == expected)
        }
    }

    @Test func rotationWrapsAroundToFirstMessage() {
        let fullCycle = AnalysisReassurance.rotationInterval * Double(AnalysisReassurance.messages.count)
        let elapsed = AnalysisReassurance.activationDelay + fullCycle
        #expect(AnalysisReassurance.message(elapsed: elapsed) == AnalysisReassurance.messages.first)
    }

    @Test func messagesExplainOneTimeCostAndReward() {
        // The copy must communicate the core promise: one-time analysis,
        // permanent reward. Guard against future edits dropping that framing.
        let combined = AnalysisReassurance.messages.joined(separator: " ").lowercased()
        #expect(combined.contains("one-time") || combined.contains("once"))
        #expect(combined.contains("instantly") || combined.contains("every time"))
    }

    // MARK: - ActiveAnalysis start tracking

    @Test func activeAnalysisRecordsStartTimeByDefault() {
        let analysis = ActiveAnalysis(
            audioFile: AudioFile(filename: "test.m4a", duration: 300, fileSize: 1024),
            stage: .starting,
            progress: 0.0
        )
        #expect(abs(analysis.startedAt.timeIntervalSinceNow) < 5)
    }

    @Test func startedAtDoesNotAffectEquality() {
        let file = AudioFile(filename: "test.m4a", duration: 300, fileSize: 1024)
        let first = ActiveAnalysis(
            audioFile: file, stage: .analyzing, progress: 0.5,
            errorMessage: nil, startedAt: Date(timeIntervalSince1970: 0)
        )
        let second = ActiveAnalysis(
            audioFile: file, stage: .analyzing, progress: 0.5,
            errorMessage: nil, startedAt: Date(timeIntervalSince1970: 1_000)
        )
        #expect(first == second)
    }

    @Test func progressDoesNotInvalidateStageObservers() {
        let analysis = ActiveAnalysis(
            audioFile: AudioFile(filename: "test.m4a", duration: 300, fileSize: 1024),
            stage: .analyzing,
            progress: 0.25
        )
        var stageInvalidated = false

        withObservationTracking {
            _ = analysis.stage
        } onChange: {
            stageInvalidated = true
        }

        analysis.progress = 0.5

        #expect(stageInvalidated == false)
    }
}

// MARK: - Task Priority Policy

struct AnalysisTaskPriorityTests {

    /// Background QoS is confined to efficiency cores and throttled by iOS.
    /// Queue analysis the user is actively waiting on must never run there.
    @Test func nonUserInitiatedAnalysisRunsAtUtilityNotBackground() async {
        let priority = await MemoryMonitor().getOptimalTaskPriority(isUserInitiated: false)
        #expect(priority == .utility)
    }

    @Test func userInitiatedAnalysisKeepsUserInitiatedPriority() async {
        let priority = await MemoryMonitor().getOptimalTaskPriority(isUserInitiated: true)
        #expect(priority == .userInitiated)
    }
}
