//
//  LightExposureBudgetTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct LightExposureBudgetTests {
    @Test
    func timeDoesNotAdvanceWhileLightIsOff() {
        var budget = LightExposureBudget(limit: .fiveMinutes)

        let reachedLimit = budget.advance(by: 120, whileEmitting: false)

        #expect(reachedLimit == false)
        #expect(budget.elapsed == 0)
        #expect(budget.remaining == 300)
    }

    @Test
    func reachingLimitIsReportedOnlyOnce() {
        var budget = LightExposureBudget(limit: .fiveMinutes)

        let beforeLimit = budget.advance(by: 299, whileEmitting: true)
        let atLimit = budget.advance(by: 1, whileEmitting: true)
        let afterLimit = budget.advance(by: 1, whileEmitting: true)

        #expect(beforeLimit == false)
        #expect(atLimit)
        #expect(afterLimit == false)
        #expect(budget.elapsed == 300)
        #expect(budget.isExpired)
    }

    @Test
    func invalidIntervalsDoNotConsumeTheBudget() {
        var budget = LightExposureBudget(limit: .fiveMinutes)

        let zeroInterval = budget.advance(by: 0, whileEmitting: true)
        let negativeInterval = budget.advance(by: -1, whileEmitting: true)

        #expect(zeroInterval == false)
        #expect(negativeInterval == false)
        #expect(budget.elapsed == 0)
    }

    @Test
    func outputFadesSmoothlyDuringFinalMinute() {
        var budget = LightExposureBudget(limit: .fiveMinutes)

        _ = budget.advance(by: 240, whileEmitting: true)
        #expect(budget.outputMultiplier == 1)

        _ = budget.advance(by: 30, whileEmitting: true)
        #expect(budget.outputMultiplier == 0.5)

        _ = budget.advance(by: 30, whileEmitting: true)
        #expect(budget.outputMultiplier == 0)
    }
}
