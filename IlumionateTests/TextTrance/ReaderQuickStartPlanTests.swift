//
//  ReaderQuickStartPlanTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct ReaderQuickStartPlanTests {
    @Test
    func prefersMostRecentValidResume() {
        let older = makeScript(id: "older")
        let recent = makeScript(id: "recent")
        let recentState = makeResume(for: recent, wordIndex: 2)
        let olderState = makeResume(for: older, wordIndex: 1)

        let plan = ReaderQuickStartPlan.select(
            scripts: [older, recent],
            historyItems: [
                ReaderHistoryItem(script: recent, state: recentState),
                ReaderHistoryItem(script: older, state: olderState),
            ],
            preset: { _ in .standard }
        )

        #expect(plan?.script.id == "recent")
        #expect(plan?.startIndex == 2)
        #expect(plan?.startType == .resumed)
        #expect(plan?.settings.arc == .fullText)
    }

    @Test
    func fallsBackToFirstScriptWithSafeDefaults() {
        let first = makeScript(id: "first")
        let second = makeScript(id: "second")
        let preset = ReaderPreset(
            speedTraining: ReaderSpeedTrainingSettings(targetWPM: 360),
            displayPreferences: .standard
        )

        let plan = ReaderQuickStartPlan.select(
            scripts: [first, second],
            historyItems: [],
            preset: { _ in preset }
        )

        #expect(plan?.script.id == "first")
        #expect(plan?.startIndex == 0)
        #expect(plan?.startType == .fresh)
        #expect(plan?.settings.speedMultiplier == preset.speedTraining.targetSpeedMultiplier)
        #expect(plan?.settings.lightEnabled == false)
        #expect(plan?.settings.binauralEnabled == false)
        #expect(plan?.settings.attentionGateEnabled == false)
    }

    private func makeScript(id: String) -> TranceScript {
        TranceScript(
            schemaVersion: 1,
            id: id,
            title: id.capitalized,
            theme: .relaxation,
            supportedArcs: [.fullText],
            language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [
                TranceScriptSegment(
                    phase: .induction,
                    text: "one two three four five",
                    pacing: SegmentPacing(baseWPM: 120),
                    arcs: nil,
                    triggersHandoff: nil
                ),
            ]
        )
    }

    private func makeResume(for script: TranceScript, wordIndex: Int) -> ReaderResumeState {
        ReaderResumeState(
            scriptId: script.id,
            wordIndex: wordIndex,
            settings: PersistedReaderSettings(
                arc: .fullText,
                speedMultiplier: 1,
                subliminalEnabled: true,
                subliminalSpeed: .medium,
                binauralEnabled: false,
                lightEnabled: false,
                beatFrequency: 10
            ),
            phase: .reading,
            scriptContentHash: ReaderResumeState.contentHash(
                for: script.segments.map(\.text).joined(separator: " ")
            ),
            savedAt: .now
        )
    }
}
