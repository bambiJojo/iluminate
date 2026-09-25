//
//  SwipeRevealHintTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct SwipeRevealHintTests {

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "SwipeRevealHintTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test("A new user sees the swipe hint")
    func newUserSeesHint() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(SwipeRevealHint(defaults: defaults).isVisible)
    }

    /// The reported bug: the hint never went away, so it read as a tutorial
    /// that could not be dismissed.
    @Test("The hint retires once the user has revealed the controls enough times")
    func hintRetiresAfterReveals() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hint = SwipeRevealHint(defaults: defaults)

        for _ in 0..<(SwipeRevealHint.retireAfterReveals - 1) {
            hint.recordReveal()
        }
        #expect(hint.isVisible)

        hint.recordReveal()
        #expect(hint.isVisible == false)
        #expect(SwipeRevealHint(defaults: defaults).isVisible == false)
    }

    @Test("Counting stops once the hint has retired")
    func countingStops() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let hint = SwipeRevealHint(defaults: defaults)

        for _ in 0..<(SwipeRevealHint.retireAfterReveals + 5) {
            hint.recordReveal()
        }
        #expect(defaults.integer(forKey: AppSettingsManager.Key.swipeRevealCount) == SwipeRevealHint.retireAfterReveals)
    }
}
