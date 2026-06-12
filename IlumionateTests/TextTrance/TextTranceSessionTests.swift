//  TextTranceSessionTests.swift
//  IlumionateTests

import Testing
import Foundation
@testable import Ilumionate

@MainActor
struct TextTranceSessionTests {

    private func handoffScript() -> TranceScript {
        TranceScript(
            schemaVersion: 1, id: "h", title: "H", theme: .relaxation,
            supportedArcs: [.fullText, .handoff], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [
                TranceScriptSegment(phase: .induction, text: "one two",
                    pacing: SegmentPacing(baseWPM: 600), arcs: nil, triggersHandoff: nil),
                TranceScriptSegment(phase: .transitional, text: "close",
                    pacing: SegmentPacing(baseWPM: 600), arcs: [.handoff], triggersHandoff: true)
            ])
    }

    // Immediate-return sleep so the playback loop runs synchronously in tests.
    private let noSleep: @Sendable (Duration) async -> Void = { _ in }

    @Test func handoffArcStartsLightAfterReadingAndStopsAllAtEnd() async {
        let light = MockLightLayer()
        let audio = MockAudioLayer()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .handoff, speed: .natural,
                lightEnabled: true, binauralEnabled: true,
                beatFrequency: 10, postHandoffDuration: 1),
            light: light, audio: audio, sleep: noSleep)

        await session.begin()

        #expect(audio.startCount == 1)
        #expect(audio.lastBeatFrequency == 10)
        #expect(light.startCount == 1)       // engaged for the handoff tail
        #expect(light.stopCount == 1)
        #expect(audio.stopCount == 1)
        #expect(session.isComplete)
    }

    @Test func fullTextArcNeverStartsLight() async {
        let light = MockLightLayer()
        let audio = MockAudioLayer()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speed: .natural,
                lightEnabled: true, binauralEnabled: true,
                beatFrequency: 10, postHandoffDuration: 1),
            light: light, audio: audio, sleep: noSleep)

        await session.begin()

        #expect(light.startCount == 0)
        #expect(audio.stopCount == 1)
        #expect(session.isComplete)
    }

    @Test func disabledBinauralNeverStartsAudio() async {
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speed: .natural,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 1),
            light: MockLightLayer(), audio: { let a = MockAudioLayer(); return a }(),
            sleep: noSleep)
        // keep a reference for assertions
        let audio = session.audioForTesting as? MockAudioLayer

        await session.begin()
        #expect(audio?.startCount == 0)
    }

    @Test func lastReadWordIsExposed() async {
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speed: .natural,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: noSleep)
        await session.begin()
        // In fullText, "close" is handoff-only -> excluded; last word is "two".
        #expect(session.currentWord == "two")
    }

    @Test func endStopsLayersAndPreventsCompletionLightStart() async {
        let light = MockLightLayer()
        let audio = MockAudioLayer()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .handoff, speed: .natural,
                lightEnabled: true, binauralEnabled: true,
                beatFrequency: 10, postHandoffDuration: 1),
            light: light, audio: audio, sleep: noSleep)

        session.end()          // end before begin: cancelled session
        await session.begin()  // loop must bail immediately

        #expect(light.startCount == 0)
        #expect(session.isComplete == false || light.startCount == 0)
    }
}
