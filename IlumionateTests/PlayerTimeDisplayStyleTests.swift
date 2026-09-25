//
//  PlayerTimeDisplayStyleTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct PlayerTimeDisplayStyleTests {

    private let locale = Locale(identifier: "en_US")

    @Test("Elapsed shows the position against the full length")
    func elapsedShowsTotal() {
        let text = PlayerTimeDisplayStyle.elapsed.text(currentTime: 754, duration: 2700, locale: locale)
        #expect(text == "12:34 / 45:00")
    }

    @Test("Remaining counts down with a leading minus sign")
    func remainingCountsDown() {
        let text = PlayerTimeDisplayStyle.remaining.text(currentTime: 754, duration: 2700, locale: locale)
        #expect(text == "\u{2212}32:26")
    }

    @Test("Percentage rounds down so 100% only appears at the very end")
    func percentageRoundsDown() {
        let style = PlayerTimeDisplayStyle.percentage
        #expect(style.text(currentTime: 754, duration: 2700, locale: locale) == "27%")
        #expect(style.text(currentTime: 2699, duration: 2700, locale: locale) == "99%")
        #expect(style.text(currentTime: 2700, duration: 2700, locale: locale) == "100%")
    }

    @Test("Hour-long files show hours rather than 75 minutes")
    func hourLongFilesShowHours() {
        let text = PlayerTimeDisplayStyle.elapsed.text(currentTime: 3725, duration: 4500, locale: locale)
        #expect(text == "1:02:05 / 1:15:00")
    }

    @Test("An unknown length falls back to plain elapsed time in every style",
          arguments: PlayerTimeDisplayStyle.allCases)
    func unknownLengthFallsBack(style: PlayerTimeDisplayStyle) {
        #expect(style.text(currentTime: 65, duration: 0, locale: locale) == "1:05")
    }

    @Test("Out-of-range positions are clamped rather than shown negative or past the end")
    func clampsPosition() {
        #expect(PlayerTimeDisplayStyle.remaining.text(currentTime: 3000, duration: 2700, locale: locale) == "\u{2212}0:00")
        #expect(PlayerTimeDisplayStyle.percentage.text(currentTime: -5, duration: 2700, locale: locale) == "0%")
        #expect(PlayerTimeDisplayStyle.elapsed.text(currentTime: .nan, duration: 2700, locale: locale) == "0:00 / 45:00")
    }

    @Test("Tapping cycles elapsed, remaining, percentage and back")
    func cycles() {
        #expect(PlayerTimeDisplayStyle.elapsed.next == .remaining)
        #expect(PlayerTimeDisplayStyle.remaining.next == .percentage)
        #expect(PlayerTimeDisplayStyle.percentage.next == .elapsed)
    }

    @Test("Defaults to elapsed and reads back an unknown stored value as elapsed")
    func storedValueFallsBack() throws {
        let suite = "PlayerTimeDisplayStyleTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(PlayerTimeDisplayStyle(storedValue: defaults.string(forKey: AppSettingsManager.Key.playerTimeDisplayStyle)) == .elapsed)
        #expect(PlayerTimeDisplayStyle(storedValue: "sideways") == .elapsed)
        #expect(PlayerTimeDisplayStyle(storedValue: "percentage") == .percentage)
    }
}
