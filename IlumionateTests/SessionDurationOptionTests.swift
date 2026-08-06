//
//  SessionDurationOptionTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct SessionDurationOptionTests {

    @Test("Open-ended is first, so it is what a default session lands on")
    func openEndedIsFirst() {
        #expect(SessionDurationOption.allCases.first == .openEnded)
        #expect(SessionDurationOption.openEnded.seconds == nil)
    }

    @Test("Timed options are in ascending order")
    func ascendingOrder() {
        let seconds = SessionDurationOption.allCases.compactMap(\.seconds)
        #expect(seconds == seconds.sorted())
    }

    @Test("Every option has a non-empty label and accessibility label")
    func labels() {
        for option in SessionDurationOption.allCases {
            #expect(option.label.isEmpty == false)
            #expect(option.accessibilityLabel.isEmpty == false)
        }
    }

    @Test("Advancing cycles through every option and wraps")
    func advanceWraps() {
        var option = SessionDurationOption.allCases[0]
        var seen: [SessionDurationOption] = [option]
        for _ in 1..<SessionDurationOption.allCases.count {
            option = option.next
            seen.append(option)
        }
        #expect(Set(seen).count == SessionDurationOption.allCases.count)
        #expect(option.next == SessionDurationOption.allCases[0])
    }

    @Test("An exact stored duration resolves to its option")
    func resolvesExactDuration() {
        #expect(SessionDurationOption(seconds: nil) == .openEnded)
        #expect(SessionDurationOption(seconds: 600) == .tenMinutes)
        #expect(SessionDurationOption(seconds: 1_200) == .twentyMinutes)
        #expect(SessionDurationOption(seconds: 3_600) == .sixtyMinutes)
    }

    @Test("An off-list duration resolves to the nearest option, not to open-ended")
    func resolvesNearestDuration() {
        // Falling back to open-ended would silently drop a user's timer.
        #expect(SessionDurationOption(seconds: 605) == .tenMinutes)
        #expect(SessionDurationOption(seconds: 1) == .tenMinutes)
        #expect(SessionDurationOption(seconds: 99_999) == .sixtyMinutes)
    }

    @Test("Round-tripping an option through its seconds returns the same option")
    func roundTrip() {
        for option in SessionDurationOption.allCases {
            #expect(SessionDurationOption(seconds: option.seconds) == option)
        }
    }

    @Test("Only open-ended has no seconds")
    func onlyOpenEndedIsUntimed() {
        for option in SessionDurationOption.allCases {
            #expect((option.seconds == nil) == (option == .openEnded))
        }
    }
}
