//
//  SessionOpeningCopyTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

/// The copy shown while a session opens.
///
/// It used to lead into a numeral — "Close your eyes and relax in… 3" — and
/// the threshold removed the numeral. These pin the reword, because a line
/// that dangles into nothing is the kind of thing that reads fine in a diff
/// and looks broken on a screen.
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
        // The arc is wordless; the screen is not. Whether the user's eyes are
        // closed changes what a photoentrainment session does, so this copy
        // is functional, not decorative — it must not be dropped for a purer
        // aesthetic.
        for mode in allModes {
            #expect(mode.countdownIntroMessage.isEmpty == false)
        }
    }

    @Test("The watched session never tells its watcher to shut their eyes")
    func visualFieldNeverSaysCloseYourEyes() {
        #expect(field.countdownIntroMessage.localizedStandardContains("close your eyes") == false)
        #expect(field.countdownHoldMessage == nil)
    }

    @Test("Eyes-closed modes still hold the instruction after the arc")
    func lightModesHoldTheInstruction() {
        #expect(flash.countdownHoldMessage == "Close your eyes")
        #expect(pulse.countdownHoldMessage == "Close your eyes")
    }
}
