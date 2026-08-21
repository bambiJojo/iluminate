//
//  LightExposureLimitTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct LightExposureLimitTests {
    @Test(arguments: LightExposureLimit.allCases)
    func storedValuesRoundTrip(_ limit: LightExposureLimit) {
        #expect(LightExposureLimit(storedMinutes: limit.rawValue) == limit)
        #expect(limit.duration == Double(limit.rawValue * 60))
    }

    @Test
    func unsupportedStoredValueUsesRecommendedLimit() {
        #expect(LightExposureLimit(storedMinutes: 25) == .twentyMinutes)
    }

    @Test
    func displayNamesKeepTheSettingCompact() {
        #expect(LightExposureLimit.twentyMinutes.displayName == "20 min")
        #expect(LightExposureLimit.sixtyMinutes.displayName == "1 hr")
    }
}
