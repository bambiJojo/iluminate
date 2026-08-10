//
//  FocusSpotSettingsTests.swift
//  IlumionateTests
//
//  Focus spot geometry is a stored display preference. A corrupt or
//  hand-edited value must degrade to something renderable rather than
//  producing spots the size of the screen or off the edge of it.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("Focus spot settings")
struct FocusSpotSettingsTests {

    // MARK: - Defaults and clamping

    @Test("Defaults sit in the upper third")
    func defaultsToUpperThird() {
        #expect(FocusSpotSettings.default.verticalPosition == 1.0 / 3.0)
        #expect(FocusSpotSettings.default.horizontalSpacing == 180)
        #expect(FocusSpotSettings.default.diameter == 48)
    }

    @Test("Out-of-range values clamp into their ranges")
    func outOfRangeValuesClamp() {
        let wild = FocusSpotSettings(
            verticalPosition: 5,
            horizontalSpacing: -100,
            diameter: 9_000
        ).clamped

        #expect(wild.verticalPosition == FocusSpotSettings.verticalPositionRange.upperBound)
        #expect(wild.horizontalSpacing == FocusSpotSettings.horizontalSpacingRange.lowerBound)
        #expect(wild.diameter == FocusSpotSettings.diameterRange.upperBound)
    }

    @Test("Non-finite values fall back to the defaults")
    func nonFiniteValuesFallBack() {
        let broken = FocusSpotSettings(
            verticalPosition: .nan,
            horizontalSpacing: .infinity,
            diameter: .nan
        ).clamped

        #expect(broken.verticalPosition == FocusSpotSettings.default.verticalPosition)
        #expect(broken.diameter == FocusSpotSettings.default.diameter)
        #expect(broken.horizontalSpacing == FocusSpotSettings.horizontalSpacingRange.upperBound)
    }

    // MARK: - Detent snapping

    @Test("A value within tolerance snaps to its detent")
    func nearValuesSnap() {
        #expect(FocusSpotSettings.snappingVerticalPosition(0.34) == 1.0 / 3.0)
        #expect(FocusSpotSettings.snappingVerticalPosition(0.505) == 0.5)
        #expect(FocusSpotSettings.snappingVerticalPosition(0.655) == 2.0 / 3.0)
    }

    @Test("A value outside tolerance is left alone")
    func farValuesDoNotSnap() {
        #expect(FocusSpotSettings.snappingVerticalPosition(0.42) == 0.42)
        #expect(FocusSpotSettings.snappingVerticalPosition(0.6) == 0.6)
    }

    @Test("Snapping is idempotent on an exact detent")
    func snappingIsIdempotent() {
        for detent in FocusSpotSettings.verticalDetents {
            #expect(FocusSpotSettings.snappingVerticalPosition(detent) == detent)
        }
    }

    @Test("Snapping clamps before it snaps")
    func snappingClamps() {
        #expect(
            FocusSpotSettings.snappingVerticalPosition(-3)
                == FocusSpotSettings.verticalPositionRange.lowerBound
        )
    }

    // MARK: - Persistence

    @Test("Unset preference returns the defaults")
    func unsetReturnsDefaults() throws {
        let defaults = try makeDefaults()

        #expect(FocusSpotPreference.current(defaults: defaults) == .default)
        #expect(FocusSpotPreference.isEnabled(defaults: defaults) == false)
    }

    @Test("Geometry round-trips through UserDefaults")
    func geometryRoundTrips() throws {
        let defaults = try makeDefaults()
        let settings = FocusSpotSettings(
            verticalPosition: 0.5,
            horizontalSpacing: 220,
            diameter: 64
        )

        FocusSpotPreference.set(settings, defaults: defaults)

        #expect(FocusSpotPreference.current(defaults: defaults) == settings)
    }

    @Test("Enablement round-trips through UserDefaults")
    func enablementRoundTrips() throws {
        let defaults = try makeDefaults()

        FocusSpotPreference.setEnabled(true, defaults: defaults)
        #expect(FocusSpotPreference.isEnabled(defaults: defaults))

        FocusSpotPreference.setEnabled(false, defaults: defaults)
        #expect(FocusSpotPreference.isEnabled(defaults: defaults) == false)
    }

    @Test("Corrupt stored data falls back instead of crashing")
    func corruptDataFallsBack() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: AppSettingsManager.Key.focusSpots)

        #expect(FocusSpotPreference.current(defaults: defaults) == .default)
    }

    @Test("Stored out-of-range geometry is clamped on read")
    func storedValuesAreClampedOnRead() throws {
        let defaults = try makeDefaults()
        let json = #"{"verticalPosition":42,"horizontalSpacing":5,"diameter":900}"#
        defaults.set(Data(json.utf8), forKey: AppSettingsManager.Key.focusSpots)

        let read = FocusSpotPreference.current(defaults: defaults)

        #expect(read.verticalPosition == FocusSpotSettings.verticalPositionRange.upperBound)
        #expect(read.horizontalSpacing == FocusSpotSettings.horizontalSpacingRange.lowerBound)
        #expect(read.diameter == FocusSpotSettings.diameterRange.upperBound)
    }

    @Test("Preference reset turns the feature off and drops the geometry")
    @MainActor
    func resetClearsBothKeys() throws {
        let defaults = try makeDefaults()
        FocusSpotPreference.setEnabled(true, defaults: defaults)
        FocusSpotPreference.set(
            FocusSpotSettings(verticalPosition: 0.5, horizontalSpacing: 300, diameter: 100),
            defaults: defaults
        )

        AppSettingsManager.resetPreferences(
            defaults: defaults,
            resetAnalysisPreferences: false
        )

        #expect(FocusSpotPreference.isEnabled(defaults: defaults) == false)
        #expect(FocusSpotPreference.current(defaults: defaults) == .default)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> UserDefaults {
        let name = "FocusSpotSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
