//
//  PlayerModeAnalyticsTests.swift
//  IlumionateTests
//
//  Session telemetry recorded `source` (preset/generated/mindMachine) and
//  `category` (Focus/Trance/…) but never which player actually rendered. With 8
//  of 35 measured sessions abandoned under 25%, "which experience are people
//  walking out of" was unanswerable. These names are wire format — historical
//  comparisons break silently if they drift, so they are pinned.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("Player mode analytics naming")
struct PlayerModeAnalyticsTests {

    @Test("Every mode reports a stable name")
    func everyModeHasAName() {
        let cases: [(PlayerMode, String)] = [
            (.session(session: AnalysisFixtures.hypnosisSession, audioFile: nil), "session"),
            (.flashMode(
                frequency: 10, intensity: 0.8, colorTemperature: 3000,
                pattern: .sine, binauralEnabled: false,
                binauralCarrier: 200, binauralVolume: 0.5
            ), "flash"),
            (.colorPulse(frequency: 8, intensity: 0.6), "colorPulse"),
            (.visualField(
                settings: .standard, audioFile: nil, binaural: nil
            ), "visualField")
        ]

        for (mode, expected) in cases {
            #expect(mode.analyticsName == expected)
        }
    }

    @Test("Names are wire values, never display strings")
    func namesAreWireSafe() {
        let names = [
            PlayerMode.colorPulse(frequency: 8, intensity: 0.6).analyticsName,
            PlayerMode.visualField(
                settings: .standard, audioFile: nil, binaural: nil
            ).analyticsName
        ]

        for name in names {
            #expect(name.isEmpty == false)
            #expect(name.contains(" ") == false)
            #expect(name == name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
