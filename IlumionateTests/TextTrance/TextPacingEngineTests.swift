//  TextPacingEngineTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

struct TextPacingEngineTests {

    private func script(arcs: [ScriptArc],
                        segments: [TranceScriptSegment]) -> TranceScript {
        TranceScript(
            schemaVersion: 1, id: "t", title: "T", theme: .relaxation,
            supportedArcs: arcs, language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: segments
        )
    }

    @Test func explicitWPMSetsWordDuration() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "rest now",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural))
        #expect(schedule.count == 2)
        #expect(abs(schedule[0].duration - 0.5) < 0.0001)
        #expect(schedule[0].startTime == 0)
        #expect(abs(schedule[1].startTime - 0.5) < 0.0001)
        #expect(schedule[0].pivotIndex == ORPCalculator.pivotIndex(for: "rest"))
        #expect(schedule[0].phase == .induction)
    }

    @Test func sentenceEndAddsHold() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "rest.",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural))
        #expect(abs(schedule[0].duration - 1.25) < 0.0001)
    }

    @Test func speedMultiplierScalesDuration() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "rest now",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil)
        ])
        let brisk = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .brisk))
        #expect(abs(brisk[0].duration - (0.5 / 1.35)) < 0.0001)
    }

    @Test func missingWPMUsesDepthDerivedPace() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "one",
                                pacing: nil, arcs: nil, triggersHandoff: nil),
            TranceScriptSegment(phase: .deepening, text: "two",
                                pacing: nil, arcs: nil, triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural))
        #expect(schedule[1].duration > schedule[0].duration)
    }

    @Test func fullTextArcExcludesHandoffOnlySegments() {
        let s = script(arcs: [.fullText, .handoff], segments: [
            TranceScriptSegment(phase: .induction, text: "read me",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil),
            TranceScriptSegment(phase: .emergence, text: "eyes close",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: [.handoff], triggersHandoff: true)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural))
        #expect(schedule.map(\.text) == ["read", "me"])
    }

    @Test func handoffArcStopsAfterTriggerSegment() {
        let s = script(arcs: [.fullText, .handoff], segments: [
            TranceScriptSegment(phase: .induction, text: "read me",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil),
            TranceScriptSegment(phase: .emergence, text: "eyes close",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: [.handoff], triggersHandoff: true),
            TranceScriptSegment(phase: .emergence, text: "should not appear",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: [.handoff], triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .handoff, speed: .natural))
        #expect(schedule.map(\.text) == ["read", "me", "eyes", "close"])
    }
}
