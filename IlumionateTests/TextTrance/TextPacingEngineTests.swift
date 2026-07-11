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
            settings: .init(arc: .fullText, speed: .natural, subliminalEnabled: false))
        #expect(schedule.count == 2)
        #expect(abs(schedule[0].duration - 0.5) < 0.0001)
        #expect(schedule[0].startTime == 0)
        #expect(abs(schedule[1].startTime - 0.5) < 0.0001)
        #expect(schedule[0].pivotIndex == ORPCalculator.pivotIndex(for: "rest"))
        #expect(schedule[0].phase == .induction)
    }

    @Test func sentenceEndAddsHoldAndFades() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "rest.",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural, subliminalEnabled: false))
        // base 0.5s * breathHoldMultiplier 3.0
        #expect(abs(schedule[0].duration - 1.5) < 0.0001)
        #expect(schedule[0].fade == .breath)
    }

    @Test func speedMultiplierScalesDuration() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "rest now",
                                pacing: SegmentPacing(baseWPM: 120),
                                arcs: nil, triggersHandoff: nil)
        ])
        let brisk = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .brisk, subliminalEnabled: false))
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

    @Test func nonPositiveWPMHintFallsBackToDepthDerivedPace() {
        let s = script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: "rest",
                                pacing: SegmentPacing(baseWPM: 0),
                                arcs: nil, triggersHandoff: nil)
        ])
        let schedule = TextPacingEngine.schedule(for: s,
            settings: .init(arc: .fullText, speed: .natural, subliminalEnabled: false))
        #expect(schedule.count == 1)
        #expect(schedule[0].duration.isFinite)
        #expect(schedule[0].duration > 0)
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

    // MARK: - Punctuation pauses + subliminal layer

    private func script(_ text: String, wpm: Double = 600) -> TranceScript {
        script(arcs: [.fullText], segments: [
            TranceScriptSegment(phase: .induction, text: text,
                                pacing: SegmentPacing(baseWPM: wpm),
                                arcs: nil, triggersHandoff: nil)
        ])
    }

    private func subSettings(subliminalEnabled: Bool = true,
                             subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium)
    -> TextPacingSettings {
        TextPacingSettings(arc: .fullText, speed: .natural,
                           subliminalEnabled: subliminalEnabled,
                           subliminalSpeed: subliminalSpeed)
    }

    @Test func breathWordHoldsLongerThanPlainWordAndFades() {
        let words = TextPacingEngine.schedule(for: script("table now."), settings: subSettings(subliminalEnabled: false))
        // base = 60/600 = 0.1s
        #expect(abs(words[0].duration - 0.1) < 1e-9)             // "table" plain
        #expect(abs(words[1].duration - 0.1 * 3.0) < 1e-9)       // "now" breath
        #expect(words[1].fade == .breath)
        #expect(words[0].fade == .none)
    }

    @Test func driftWordUsesDriftMultiplierAndFade() {
        let words = TextPacingEngine.schedule(for: script("slowly…"), settings: subSettings(subliminalEnabled: false))
        #expect(abs(words[0].duration - 0.1 * 4.5) < 1e-9)
        #expect(words[0].fade == .drift)
    }

    @Test func authoredMarkFlashesOnlyThatWord() {
        let words = TextPacingEngine.schedule(for: script("you [[relax]] table"), settings: subSettings())
        // "you" and "table" are lexicon non-matches; "relax" is authored.
        #expect(words.map(\.isSubliminal) == [false, true, false])
        #expect(abs(words[1].duration - 0.09) < 1e-9)           // medium flash
    }

    @Test func lexiconAppliesOnlyWhenNoAuthoredMarks() {
        // No authored marks → lexicon flags "relax" and "deeper".
        let words = TextPacingEngine.schedule(for: script("you relax deeper table"), settings: subSettings())
        #expect(words.map(\.isSubliminal) == [false, true, true, false])
    }

    @Test func lexiconIgnoredWhenAuthoredMarksPresent() {
        // Authored mark exists → lexicon word "deeper" is NOT auto-flashed.
        let words = TextPacingEngine.schedule(for: script("[[relax]] deeper"), settings: subSettings())
        #expect(words.map(\.isSubliminal) == [true, false])
    }

    @Test func subliminalDisabledFlagsNothing() {
        let words = TextPacingEngine.schedule(for: script("you [[relax]] deeper"), settings: subSettings(subliminalEnabled: false))
        let noneFlash = words.allSatisfy { !$0.isSubliminal }
        #expect(noneFlash)
    }

    @Test func subliminalSpeedControlsFlashDuration() {
        let deep = TextPacingEngine.schedule(for: script("relax"), settings: subSettings(subliminalSpeed: .deep))
        let gentle = TextPacingEngine.schedule(for: script("relax"), settings: subSettings(subliminalSpeed: .gentle))
        #expect(abs(deep[0].duration - 0.065) < 1e-9)
        #expect(abs(gentle[0].duration - 0.12) < 1e-9)
    }

    @Test func startTimeIsCumulativeSumOfDurations() {
        let words = TextPacingEngine.schedule(for: script("table now. slowly"), settings: subSettings(subliminalEnabled: false))
        var cursor = 0.0
        for word in words {
            #expect(abs(word.startTime - cursor) < 1e-9)
            cursor += word.duration
        }
    }

    @Test func speedMultiplierScalesReadableDurationsInversely() {
        let s = TranceScript(
            schemaVersion: 1, id: "s", title: "S", theme: .relaxation,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [TranceScriptSegment(phase: .induction, text: "alpha bravo charlie",
                pacing: SegmentPacing(baseWPM: 120), arcs: nil, triggersHandoff: nil)])
        let slow = TextPacingEngine.schedule(
            for: s, settings: TextPacingSettings(arc: .fullText, speedMultiplier: 1.0,
                                                 subliminalEnabled: false))
        let fast = TextPacingEngine.schedule(
            for: s, settings: TextPacingSettings(arc: .fullText, speedMultiplier: 2.0,
                                                 subliminalEnabled: false))
        // 2x multiplier => 2x WPM => half the duration per word.
        #expect(abs(slow[0].duration - fast[0].duration * 2) < 0.0001)
    }

    @Test func wordSequenceIsInvariantAcrossSpeedAndSubliminal() {
        let s = TranceScript(
            schemaVersion: 1, id: "i", title: "I", theme: .relaxation,
            supportedArcs: [.fullText], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [TranceScriptSegment(phase: .induction, text: "go deeper now and rest",
                pacing: SegmentPacing(baseWPM: 120), arcs: nil, triggersHandoff: nil)])
        let a = TextPacingEngine.schedule(for: s,
            settings: TextPacingSettings(arc: .fullText, speedMultiplier: 0.5, subliminalEnabled: true))
        let b = TextPacingEngine.schedule(for: s,
            settings: TextPacingSettings(arc: .fullText, speedMultiplier: 1.7, subliminalEnabled: false))
        #expect(a.map(\.text) == b.map(\.text))
        #expect(a.count == b.count)
    }

    @Test func schedulePreservesSmartApostrophesInWords() {
        let words = TextPacingEngine.schedule(
            for: script("it’s okay I’m here for parents’ rhythm", wpm: 120),
            settings: subSettings(subliminalEnabled: false)
        )
        #expect(words.map(\.text) == ["it’s", "okay", "I’m", "here", "for", "parents’", "rhythm"])
    }

    @Test func scheduleExpandsStandaloneAmpersandsForReaderLegibility() {
        let words = TextPacingEngine.schedule(
            for: script("rhythm & breath", wpm: 120),
            settings: subSettings(subliminalEnabled: false)
        )
        #expect(words.map(\.text) == ["rhythm", "and", "breath"])
    }

    @Test func nominalWPMMapsFromMultiplier() {
        #expect(TextPacingEngine.nominalWPM(forMultiplier: 1.0) == 150)
        #expect(TextPacingEngine.nominalWPM(forMultiplier: 2.0) == 300)
    }

    @Test func chunkSizeGroupsReadableWordsWithoutCrossingPunctuation() {
        var training = ReaderSpeedTrainingSettings.standard
        training.chunkSize = 3
        training.punctuationPause = .normal

        let words = TextPacingEngine.schedule(
            for: script("one two three. four five six", wpm: 600),
            settings: TextPacingSettings(
                arc: .fullText,
                speedMultiplier: 1.0,
                subliminalEnabled: false,
                speedTraining: training
            )
        )

        #expect(words.map(\.text) == ["one two three", "four five six"])
        #expect(words[0].fade == .breath)
        #expect(abs(words[0].duration - 0.5) < 1e-9)
        #expect(abs(words[1].duration - 0.3) < 1e-9)
    }

    @Test func punctuationPauseOffRemovesSentenceExtraHold() {
        var training = ReaderSpeedTrainingSettings.standard
        training.punctuationPause = .off

        let words = TextPacingEngine.schedule(
            for: script("now.", wpm: 600),
            settings: TextPacingSettings(
                arc: .fullText,
                speedMultiplier: 1.0,
                subliminalEnabled: false,
                speedTraining: training
            )
        )

        #expect(abs(words[0].duration - 0.1) < 1e-9)
        #expect(words[0].fade == .breath)
    }

    @Test func rampModeAcceleratesTowardTargetWPM() {
        var training = ReaderSpeedTrainingSettings(
            mode: .ramp,
            targetWPM: 300,
            warmUpWPM: 100,
            rampStartWPM: 100,
            chunkSize: 1,
            punctuationPause: .off
        )
        training.chunkSize = 1

        let words = TextPacingEngine.schedule(
            for: script(String(repeating: "word ", count: 160), wpm: 150),
            settings: TextPacingSettings(
                arc: .fullText,
                speedMultiplier: 1.0,
                subliminalEnabled: false,
                speedTraining: training
            )
        )

        #expect(words.count == 160)
        #expect(words[0].duration > words[80].duration)
        #expect(words[80].duration > words[159].duration)
    }

    @Test func warmUpModeStartsBelowTargetThenReachesTarget() {
        let training = ReaderSpeedTrainingSettings(
            mode: .warmUp,
            targetWPM: 300,
            warmUpWPM: 150,
            rampStartWPM: 100,
            chunkSize: 1,
            punctuationPause: .off
        )

        let words = TextPacingEngine.schedule(
            for: script(String(repeating: "word ", count: 220), wpm: 150),
            settings: TextPacingSettings(
                arc: .fullText,
                speedMultiplier: 1.0,
                subliminalEnabled: false,
                speedTraining: training
            )
        )

        #expect(abs(words[0].duration - (60.0 / 150.0)) < 1e-9)
        #expect(abs(words[219].duration - (60.0 / 300.0)) < 1e-9)
    }
}
