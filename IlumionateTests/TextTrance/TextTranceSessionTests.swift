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
        let light = MockLightLayer()
        let audio = MockAudioLayer()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speed: .natural,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 1),
            light: light, audio: audio, sleep: noSleep)

        await session.begin()
        #expect(audio.startCount == 0)
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
        #expect(session.isComplete == false)
    }

    @Test func lexiconWordFlashesFastInSchedule() async {
        // "go" and "deeper" are lexicon words → both flash fast (0.09s at .medium),
        // far shorter than the 600-wpm base of 0.1s, proving settings are threaded.
        let script = TranceScript(
            schemaVersion: 1, id: "x", title: "X", theme: .relaxation,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [TranceScriptSegment(phase: .induction, text: "go deeper",
                pacing: SegmentPacing(baseWPM: 600), arcs: nil, triggersHandoff: nil)])
        let words = TextPacingEngine.schedule(
            for: script,
            settings: TextPacingSettings(arc: .fullText, speed: .natural))
        let allFlash = words.allSatisfy(\.isSubliminal)
        #expect(allFlash)
    }

    @Test func owningTaskCancellationPreventsSpinThroughAndLightStart() async {
        let light = MockLightLayer()
        let audio = MockAudioLayer()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .handoff, speed: .natural,
                lightEnabled: true, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 60),
            light: light, audio: audio)

        let task = Task { await session.begin() }
        task.cancel()
        await task.value

        #expect(light.startCount == 0)
        #expect(session.isComplete == false)
    }

    @Test func beginFromStartsAtGivenIndex() async {
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: noSleep)
        // fullText schedule for "one two" => indices 0:"one", 1:"two".
        await session.begin(from: 1)
        #expect(session.currentWord == "two")
        #expect(session.isComplete)
    }

    @Test func pauseHoldsIndexThenResumeCompletes() async {
        let audio = MockAudioLayer()
        let controller = PacingSleepController()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: true,
                beatFrequency: 10, postHandoffDuration: 0),
            light: MockLightLayer(), audio: audio, sleep: controller.sleepClosure)

        // Pause when the first word's hold begins (callCount == 1).
        controller.onSleep = { call in if call == 1 { session.pause() } }

        let task = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        #expect(session.currentWordIndex == 0)   // did not advance past word 0
        #expect(audio.stopCount == 1)            // binaural paused
        #expect(!session.isComplete)

        controller.onSleep = { _ in }            // stop re-pausing
        session.resume()
        await task.value

        #expect(session.isComplete)
        #expect(audio.startCount == 2)           // started, then restarted on resume
        #expect(session.currentWord == "two")
    }

    @Test func endWhilePausedTearsDownAndDoesNotComplete() async {
        let audio = MockAudioLayer()
        let controller = PacingSleepController()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .handoff, speedMultiplier: 1.0,
                lightEnabled: true, binauralEnabled: true,
                beatFrequency: 10, postHandoffDuration: 60),
            light: MockLightLayer(), audio: audio, sleep: controller.sleepClosure)

        controller.onSleep = { call in if call == 1 { session.pause() } }
        let task = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        session.end()
        await task.value

        #expect(!session.isComplete)
        #expect(audio.stopCount >= 1)
    }
}
