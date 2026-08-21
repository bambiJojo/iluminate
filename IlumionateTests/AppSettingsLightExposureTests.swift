//
//  AppSettingsLightExposureTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct AppSettingsLightExposureTests {
    @Test
    func absentSettingUsesTwentyMinuteRecommendation() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AppSettingsManager.maximumLightTime(defaults: defaults) == .twentyMinutes)
    }

    @Test
    func supportedSettingIsLoaded() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(45, forKey: AppSettingsManager.Key.maximumLightTimeMinutes)

        #expect(AppSettingsManager.maximumLightTime(defaults: defaults) == .fortyFiveMinutes)
    }

    @Test
    func unsupportedSettingFallsBackToRecommendation() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(25, forKey: AppSettingsManager.Key.maximumLightTimeMinutes)

        #expect(AppSettingsManager.maximumLightTime(defaults: defaults) == .twentyMinutes)
    }

    @Test
    func resetRestoresTwentyMinuteRecommendation() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(60, forKey: AppSettingsManager.Key.maximumLightTimeMinutes)

        AppSettingsManager.resetPreferences(
            defaults: defaults,
            resetAnalysisPreferences: false
        )

        #expect(defaults.integer(forKey: AppSettingsManager.Key.maximumLightTimeMinutes) == 20)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AppSettingsLightExposureTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
