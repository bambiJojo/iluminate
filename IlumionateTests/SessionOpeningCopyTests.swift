//
//  SessionOpeningCopyTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

/// The copy shown while a session opens.
///
/// These pin the neutral opening copy because it must stand alone and must not
/// imply that closing the eyes prevents exposure to flashing light.
struct SessionOpeningCopyTests {

    private var field: PlayerMode {
        .visualField(settings: .standard, audioFile: nil, binaural: nil)
    }

    private var flash: PlayerMode {
        .flashMode(
            frequency: 10,
            intensity: 0.8,
            colorTemperature: 5_000,
            pattern: .sine,
            binauralEnabled: false,
            binauralCarrier: 200,
            binauralVolume: 0.5
        )
    }

    private var pulse: PlayerMode {
        .colorPulse(frequency: 10, intensity: 0.8)
    }

    private var allModes: [PlayerMode] { [field, flash, pulse] }

    @Test("No opening line dangles into a numeral that is no longer there")
    func introCopyStandsAlone() {
        for mode in allModes {
            let intro = mode.countdownIntroMessage
            #expect(intro.hasSuffix("\u{2026}") == false, "\(intro) still trails an ellipsis")
            #expect(intro.hasSuffix("in") == false, "\(intro) still leads into a count")
            #expect(intro.hasSuffix(" ") == false)
        }
    }

    @Test("Every mode still says something while the session opens")
    func introCopyIsNeverEmpty() {
        for mode in allModes {
            #expect(mode.countdownIntroMessage.isEmpty == false)
        }
    }

    @Test("The watched session never tells its watcher to shut their eyes")
    func visualFieldNeverSaysCloseYourEyes() {
        #expect(field.countdownIntroMessage.localizedStandardContains("close your eyes") == false)
        #expect(field.countdownHoldMessage == nil)
    }

    @Test("Flashing modes use a neutral hold after the arc")
    func lightModesUseNeutralHold() {
        #expect(flash.countdownHoldMessage == "Ready")
        #expect(pulse.countdownHoldMessage == "Ready")
        #expect(flash.countdownIntroMessage.localizedStandardContains("close your eyes") == false)
        #expect(pulse.countdownIntroMessage.localizedStandardContains("close your eyes") == false)
    }
}
