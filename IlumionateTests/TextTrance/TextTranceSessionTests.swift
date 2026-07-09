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

    @Test func handoffWithNoEnabledTailLayerDoesNotWaitAfterReading() async {
        let controller = PacingSleepController()
        let script = handoffScript()
        let session = TextTranceSession(
            script: script,
            settings: TextTranceSessionSettings(
                arc: .handoff, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 60),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: controller.sleepClosure)

        await session.begin()

        let readingWordCount = TextPacingEngine.schedule(
            for: script,
            settings: TextPacingSettings(arc: .handoff, speed: .natural)
        ).count
        #expect(controller.callCount == readingWordCount)
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

    @Test func togglingSubliminalKeepsIndexAndCurrentWord() async {
        let controller = PacingSleepController()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0,
                subliminalEnabled: false),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: controller.sleepClosure)

        controller.onSleep = { call in if call == 1 { session.pause() } }
        let task = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        let wordBefore = session.currentWord
        let indexBefore = session.currentWordIndex
        session.setSubliminal(enabled: true, speed: .deep)   // regenerates schedule
        #expect(session.currentWordIndex == indexBefore)
        #expect(session.currentWord == wordBefore)

        controller.onSleep = { _ in }
        session.resume()
        await task.value
        #expect(session.isComplete)
    }

    @Test func setBinauralEnabledWhilePausedAppliesOnResume() async {
        let audio = MockAudioLayer()
        let controller = PacingSleepController()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0),
            light: MockLightLayer(), audio: audio, sleep: controller.sleepClosure)

        controller.onSleep = { call in if call == 1 { session.pause() } }
        let task = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        session.setBinaural(enabled: true)
        #expect(session.binauralActive)
        #expect(audio.startCount == 0)           // not started while paused

        controller.onSleep = { _ in }
        session.resume()
        await task.value

        #expect(audio.startCount == 1)           // started on resume
        #expect(audio.lastBeatFrequency == 10)
        #expect(audio.stopCount == 1)            // stopped at completion
    }

    @Test func attentionGatePausesAndResumesWhenAttentionReturns() async {
        let controller = PacingSleepController()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0,
                attentionGateEnabled: true),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: controller.sleepClosure)

        controller.onSleep = { call in
            if call == 1 { session.setReaderAttention(isLookingAtScreen: false) }
        }
        let task = Task { await session.begin() }
        while !session.isAttentionPaused { await Task.yield() }

        #expect(session.isPaused)
        #expect(session.currentWordIndex == 0)

        controller.onSleep = { _ in }
        session.setReaderAttention(isLookingAtScreen: true)
        await task.value

        #expect(session.isComplete)
        #expect(session.currentWord == "two")
    }

    @Test func attentionReturnDoesNotResumeManualPause() async {
        let controller = PacingSleepController()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0,
                attentionGateEnabled: true),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: controller.sleepClosure)

        controller.onSleep = { call in
            if call == 1 { session.pause() }
        }
        let task = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        session.setReaderAttention(isLookingAtScreen: false)
        #expect(!session.isAttentionPaused)

        session.setReaderAttention(isLookingAtScreen: true)
        #expect(session.isPaused)

        controller.onSleep = { _ in }
        session.resume()
        await task.value

        #expect(session.isComplete)
    }

    @Test func disablingAttentionGateReleasesAttentionPause() async {
        let controller = PacingSleepController()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0,
                attentionGateEnabled: true),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: controller.sleepClosure)

        controller.onSleep = { call in
            if call == 1 { session.setReaderAttention(isLookingAtScreen: false) }
        }
        let task = Task { await session.begin() }
        while !session.isAttentionPaused { await Task.yield() }

        controller.onSleep = { _ in }
        session.setAttentionGate(enabled: false)
        await task.value

        #expect(session.isComplete)
        #expect(!session.isAttentionPaused)
    }

    @Test func savesSnapshotOnPauseAndClearsOnCompletion() async {
        let store = ReaderProgressStore(directory:
            URL.temporaryDirectory.appending(path: "rp-\(UUID().uuidString)"))
        let controller = PacingSleepController()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0),
            light: MockLightLayer(), audio: MockAudioLayer(),
            sleep: controller.sleepClosure, progressStore: store, scriptContentHash: "h")

        controller.onSleep = { call in if call == 1 { session.pause() } }
        let task = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        #expect(store.resumeState(forScriptId: handoffScript().id) != nil)

        controller.onSleep = { _ in }
        session.resume()
        await task.value
        #expect(store.resumeState(forScriptId: handoffScript().id) == nil)   // cleared on completion
    }

    @Test func setSpeedClampsToEngineBounds() async {
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: noSleep)
        session.setSpeed(multiplier: 99)
        #expect(session.speedMultiplier == TextPacingEngine.maxSpeedMultiplier)
        session.setSpeed(multiplier: 0.01)
        #expect(session.speedMultiplier == TextPacingEngine.minSpeedMultiplier)
    }

    @Test func cancellationDuringWordHoldCancelsSleepPromptly() async {
        let light = MockLightLayer()
        let sleep = CancellableSleepProbe()
        let session = TextTranceSession(
            script: handoffScript(),
            settings: TextTranceSessionSettings(
                arc: .handoff, speedMultiplier: 1.0,
                lightEnabled: true, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 60),
            light: light, audio: MockAudioLayer(), sleep: sleep.sleepClosure)

        let task = Task { await session.begin() }
        while !sleep.started { await Task.yield() }

        task.cancel()
        await task.value

        #expect(sleep.wasCancelled)
        #expect(light.startCount == 0)
        #expect(!session.isComplete)
    }

    // MARK: - Seek (scrubbing)

    /// Two segments, distinct phases, subliminals off so word indices are
    /// deterministic: 0-2 induction ("one two three"), 3-5 deepening ("four five six").
    private func seekScript() -> TranceScript {
        TranceScript(
            schemaVersion: 1, id: "s", title: "S", theme: .relaxation,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [
                TranceScriptSegment(phase: .induction, text: "one two three",
                    pacing: SegmentPacing(baseWPM: 600), arcs: nil, triggersHandoff: nil),
                TranceScriptSegment(phase: .deepening, text: "four five six",
                    pacing: SegmentPacing(baseWPM: 600), arcs: nil, triggersHandoff: nil)
            ])
    }

    private func makeSeekSession(
        sleep: @escaping @Sendable (Duration) async -> Void,
        progressStore: ReaderProgressStore? = nil,
        scriptContentHash: String = ""
    )
        -> TextTranceSession {
        TextTranceSession(
            script: seekScript(),
            settings: TextTranceSessionSettings(
                arc: .fullText, speedMultiplier: 1.0,
                lightEnabled: false, binauralEnabled: false,
                beatFrequency: 10, postHandoffDuration: 0,
                subliminalEnabled: false),
            light: MockLightLayer(), audio: MockAudioLayer(), sleep: sleep,
            progressStore: progressStore, scriptContentHash: scriptContentHash)
    }

    @Test func seekBeforeBeginIsNoOp() {
        let session = makeSeekSession(sleep: noSleep)
        session.seek(toWordIndex: 3)
        #expect(session.currentWordIndex == 0)
        #expect(session.currentWord.isEmpty)
        #expect(session.wordCount == 0)
    }

    @Test func seekClampsAndRendersWhilePausedAndStaysPaused() async {
        let controller = PacingSleepController()
        let session = makeSeekSession(sleep: controller.sleepClosure)
        controller.onSleep = { count in
            if count == 1 { session.pause() }
        }
        let run = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        #expect(session.wordCount == 6)
        #expect(session.phase(atWordIndex: 1) == .induction)
        #expect(session.phase(atWordIndex: 4) == .deepening)
        #expect(session.phase(atWordIndex: 99) == nil)

        session.seek(toWordIndex: 999)
        #expect(session.currentWordIndex == 5)
        #expect(session.currentWord == "six")
        #expect(session.isPaused)                 // seek never unpauses

        session.seek(toWordIndex: -3)
        #expect(session.currentWordIndex == 0)
        #expect(session.currentWord == "one")

        session.end()
        await run.value
    }

    @Test func resumeAfterPausedSeekContinuesFromNewIndex() async {
        let controller = PacingSleepController()
        let session = makeSeekSession(sleep: controller.sleepClosure)
        controller.onSleep = { count in
            if count == 1 { session.pause() }
        }
        let run = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        session.seek(toWordIndex: 4)              // "five"
        session.resume()
        await run.value

        #expect(session.isComplete)
        #expect(session.currentWord == "six")     // played 4, 5 then finished
        // Holds: word 0 (interrupted) + words 4 and 5 = 3 sleep calls total.
        #expect(controller.callCount == 3)
    }

    @Test func pausedSeekCanSaveUpdatedResumeIndex() async {
        let store = ReaderProgressStore(directory:
            URL.temporaryDirectory.appending(path: "rp-\(UUID().uuidString)"))
        let controller = PacingSleepController()
        let session = makeSeekSession(
            sleep: controller.sleepClosure,
            progressStore: store,
            scriptContentHash: "seek-hash")
        controller.onSleep = { count in
            if count == 1 { session.pause() }
        }
        let run = Task { await session.begin() }
        while !session.isPaused { await Task.yield() }

        #expect(store.resumeState(forScriptId: seekScript().id)?.wordIndex == 0)

        session.seek(toWordIndex: 4, savingProgress: true)
        let snapshot = store.resumeState(forScriptId: seekScript().id)
        #expect(snapshot?.wordIndex == 4)
        #expect(snapshot?.scriptContentHash == "seek-hash")

        session.end()
        await run.value
    }

    @Test func seekWhilePlayingJumpsWithoutReplayingSkippedWords() async {
        let controller = PacingSleepController()
        let session = makeSeekSession(sleep: controller.sleepClosure)
        controller.onSleep = { count in
            if count == 1 { session.seek(toWordIndex: 4) }
        }
        await session.begin()

        #expect(session.isComplete)
        #expect(session.currentWord == "six")
        #expect(controller.callCount == 3)        // word 0 + words 4, 5
    }

    @Test func seekAfterCompletionIsNoOp() async {
        let session = makeSeekSession(sleep: noSleep)
        await session.begin()
        let finalWord = session.currentWord
        session.seek(toWordIndex: 0)
        #expect(session.currentWord == finalWord)
    }
}

@MainActor
private final class CancellableSleepProbe {
    private(set) var started = false
    private(set) var wasCancelled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func sleep(_ duration: Duration) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.started = true
            }
        } onCancel: {
            Task { @MainActor in
                self.wasCancelled = true
                self.continuation?.resume()
                self.continuation = nil
            }
        }
    }

    var sleepClosure: @Sendable (Duration) async -> Void {
        { [self] duration in await self.sleep(duration) }
    }
}
