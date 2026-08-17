//
//  PlayerCompletionOverlayTests.swift
//  IlumionateTests
//
//  ERR-017: the duration line shipped a string literal that looked like an
//  interpolation. It compiled, so only a test that asserts the rendered text
//  could have caught it.
//

import Testing
import Foundation
@testable import Ilumionate

struct PlayerCompletionOverlayTests {

    @Test func durationSummaryIsInterpolatedNotLiteral() {
        let summary = PlayerCompletionOverlay.durationSummary(for: 750)
        #expect(summary == "You completed 12:30.")
        // The specific failure mode: the expression surviving as literal text.
        #expect(summary.contains("Duration.seconds") == false)
    }

    @Test func durationSummaryPadsSecondsToTwoDigits() {
        #expect(PlayerCompletionOverlay.durationSummary(for: 65) == "You completed 1:05.")
    }

    @Test func durationSummaryHandlesSubMinuteSessions() {
        #expect(PlayerCompletionOverlay.durationSummary(for: 9) == "You completed 0:09.")
    }

    @Test func durationSummaryHandlesLongSessions() {
        // 1h 5m 3s — the minuteSecond pattern keeps counting in minutes.
        #expect(PlayerCompletionOverlay.durationSummary(for: 3_903) == "You completed 65:03.")
    }
}
