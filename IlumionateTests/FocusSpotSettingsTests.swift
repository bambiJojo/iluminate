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

    @Test("NaN falls back to the default, infinity clamps to the bound")
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

    @Test("Values within the detent tolerance snap; values past it do not")
    func detentToleranceIsRespected() {
        // `1.0/3.0 + detentTolerance`, subtracted back from 1.0/3.0 inside
        // `snappingVerticalPosition`, rounds to a hair OVER the tolerance
        // (0.020000000000000018) and so would not snap. `.nextDown` steps one
        // ULP below that, to 0.019999999999999962, which does.
        //
        // This case pins the tolerance MAGNITUDE — it fails if detentTolerance
        // moves to 0.019 or 0.021. It does not pin the `<=` in
        // `snappingVerticalPosition`: the ULP near 0.353 is ~16x coarser than
        // the ULP of 0.02, so no Double distance equals the tolerance exactly
        // and `<=` versus `<` is unobservable for every possible input.
        let withinTolerance = (1.0 / 3.0 + FocusSpotSettings.detentTolerance).nextDown
        let justPastTolerance = 1.0 / 3.0 + 0.021

        #expect(FocusSpotSettings.snappingVerticalPosition(withinTolerance) == 1.0 / 3.0)
        #expect(FocusSpotSettings.snappingVerticalPosition(justPastTolerance) == justPastTolerance)
    }

    // MARK: - Persistence

    @Test("Unset preference returns the defaults")
    func unsetReturnsDefaults() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        #expect(FocusSpotPreference.current(defaults: fixture.defaults) == .default)
        #expect(FocusSpotPreference.isEnabled(defaults: fixture.defaults) == false)
    }

    @Test("Geometry round-trips through UserDefaults")
    func geometryRoundTrips() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let settings = FocusSpotSettings(
            verticalPosition: 0.5,
            horizontalSpacing: 220,
            diameter: 64
        )

        FocusSpotPreference.set(settings, defaults: fixture.defaults)

        #expect(FocusSpotPreference.current(defaults: fixture.defaults) == settings)
    }

    @Test("Geometry is clamped on write, not just on read")
    func writeClampsBeforeStoring() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        FocusSpotPreference.set(
            FocusSpotSettings(verticalPosition: 5, horizontalSpacing: -100, diameter: 9_000),
            defaults: fixture.defaults
        )

        let data = try #require(fixture.defaults.data(forKey: AppSettingsManager.Key.focusSpots))
        let stored = try JSONDecoder().decode(FocusSpotSettings.self, from: data)
        #expect(stored.diameter == FocusSpotSettings.diameterRange.upperBound)
    }

    @Test("Enablement round-trips through UserDefaults")
    func enablementRoundTrips() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }

        FocusSpotPreference.setEnabled(true, defaults: fixture.defaults)
        #expect(FocusSpotPreference.isEnabled(defaults: fixture.defaults))

        FocusSpotPreference.setEnabled(false, defaults: fixture.defaults)
        #expect(FocusSpotPreference.isEnabled(defaults: fixture.defaults) == false)
    }

    @Test("Corrupt stored data falls back instead of crashing")
    func corruptDataFallsBack() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set(Data("not json".utf8), forKey: AppSettingsManager.Key.focusSpots)

        #expect(FocusSpotPreference.current(defaults: fixture.defaults) == .default)
    }

    @Test("Stored out-of-range geometry is clamped on read")
    func storedValuesAreClampedOnRead() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let json = #"{"verticalPosition":42,"horizontalSpacing":5,"diameter":900}"#
        fixture.defaults.set(Data(json.utf8), forKey: AppSettingsManager.Key.focusSpots)

        let read = FocusSpotPreference.current(defaults: fixture.defaults)

        #expect(read.verticalPosition == FocusSpotSettings.verticalPositionRange.upperBound)
        #expect(read.horizontalSpacing == FocusSpotSettings.horizontalSpacingRange.lowerBound)
        #expect(read.diameter == FocusSpotSettings.diameterRange.upperBound)
    }

    @Test("Preference reset turns the feature off and drops the geometry")
    @MainActor
    func resetClearsBothKeys() throws {
        let fixture = try makeDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        FocusSpotPreference.setEnabled(true, defaults: fixture.defaults)
        FocusSpotPreference.set(
            FocusSpotSettings(verticalPosition: 0.5, horizontalSpacing: 300, diameter: 100),
            defaults: fixture.defaults
        )

        AppSettingsManager.resetPreferences(
            defaults: fixture.defaults,
            resetAnalysisPreferences: false
        )

        #expect(FocusSpotPreference.isEnabled(defaults: fixture.defaults) == false)
        #expect(FocusSpotPreference.current(defaults: fixture.defaults) == .default)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "FocusSpotSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
