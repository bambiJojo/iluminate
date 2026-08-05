//  ReaderModeGatingTests.swift
//  IlumionateTests
//
//  The mode has to gate the session, not just the settings list. Hiding a
//  control while its layer keeps running leaves the user with no way to reach it.

import Foundation
import Testing
@testable import Ilumionate

@Suite("Reader mode gating")
struct ReaderModeGatingTests {

    /// Everything on, so anything still enabled after normalising was let
    /// through deliberately rather than by never having been set.
    private var allLayersOn: TextTranceSessionSettings {
        TextTranceSessionSettings(
            arc: .handoff,
            speedMultiplier: 1,
            lightEnabled: true,
            binauralEnabled: true,
            beatFrequency: 10,
            postHandoffDuration: 600,
            subliminalEnabled: true,
            subliminalSpeed: .medium,
            attentionGateEnabled: true
        )
    }

    @Test("Plain reading strips every trance layer")
    func readingStripsLayers() {
        let s = allLayersOn.normalized(for: .reading, supportedArcs: [.fullText, .handoff])
        #expect(s.lightEnabled == false)
        #expect(s.binauralEnabled == false)
        #expect(s.subliminalEnabled == false)
    }

    /// TextPacingEngine stops scheduling at the handoff trigger, so leaving a
    /// handoff arc in place would silently truncate the text.
    @Test("Plain reading reads the whole text")
    func readingUsesFullText() {
        let s = allLayersOn.normalized(for: .reading, supportedArcs: [.fullText, .handoff])
        #expect(s.arc == .fullText)
    }

    @Test("A script that cannot do full text keeps its arc")
    func handoffOnlyScriptKeepsArc() {
        let s = allLayersOn.normalized(for: .reading, supportedArcs: [.handoff])
        #expect(s.arc == .handoff)
    }

    @Test("Trance leaves every layer alone")
    func tranceIsUntouched() {
        let s = allLayersOn.normalized(for: .trance, supportedArcs: [.fullText, .handoff])
        #expect(s.lightEnabled == true)
        #expect(s.binauralEnabled == true)
        #expect(s.subliminalEnabled == true)
        #expect(s.arc == .handoff)
    }

    @Test("Normalising never enables something that was off")
    func neverEnables() {
        let allOff = TextTranceSessionSettings(
            arc: .fullText,
            speedMultiplier: 1,
            lightEnabled: false,
            binauralEnabled: false,
            beatFrequency: 10,
            postHandoffDuration: 600,
            subliminalEnabled: false
        )
        for mode in ReaderMode.allCases {
            let s = allOff.normalized(for: mode, supportedArcs: [.fullText, .handoff])
            #expect(s.lightEnabled == false)
            #expect(s.binauralEnabled == false)
            #expect(s.subliminalEnabled == false)
        }
    }

    @Test("Settings the mode does not gate survive untouched")
    func ungatedSettingsSurvive() {
        for mode in ReaderMode.allCases {
            let s = allLayersOn.normalized(for: mode, supportedArcs: [.fullText, .handoff])
            #expect(s.attentionGateEnabled == true)
            #expect(s.speedMultiplier == 1)
            #expect(s.beatFrequency == 10)
            #expect(s.subliminalSpeed == .medium)
        }
    }

    /// The invariant that keeps this honest: a layer is enabled only if the
    /// catalog says the mode offers a control for it.
    @Test("No layer runs without a control to reach it")
    func noUnreachableLayers() {
        for mode in ReaderMode.allCases {
            let s = allLayersOn.normalized(for: mode, supportedArcs: [.fullText, .handoff])
            if s.binauralEnabled { #expect(ReaderSettingsGroup.binaural.tier(in: mode) != nil) }
            if s.lightEnabled { #expect(ReaderSettingsGroup.lightHandoff.tier(in: mode) != nil) }
            if s.subliminalEnabled { #expect(ReaderSettingsGroup.subliminal.tier(in: mode) != nil) }
        }
    }

    @Test("Normalising is idempotent")
    func idempotent() {
        for mode in ReaderMode.allCases {
            let once = allLayersOn.normalized(for: mode, supportedArcs: [.fullText, .handoff])
            let twice = once.normalized(for: mode, supportedArcs: [.fullText, .handoff])
            #expect(once.arc == twice.arc)
            #expect(once.lightEnabled == twice.lightEnabled)
            #expect(once.binauralEnabled == twice.binauralEnabled)
            #expect(once.subliminalEnabled == twice.subliminalEnabled)
        }
    }
}
