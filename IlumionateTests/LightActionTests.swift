//
//  LightActionTests.swift
//  IlumionateTests
//
//  Tests for Step 4.2: Structured LightAction enum replacing action: String.
//  Verifies:
//  1. All LightAction cases have the expected raw string values.
//  2. KeyMoment stores LightAction, not a String.
//  3. adjustmentForKeyMoment maps every case to distinct, valid parameters.
//  4. Codable round-trip preserves the enum case.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Raw Value Tests

struct LightActionRawValueTests {

    @Test func deepenRawValue() {
        #expect(LightAction.deepen.rawValue == "deepen")
    }

    @Test func energizeRawValue() {
        #expect(LightAction.energize.rawValue == "energize")
    }

    @Test func warmRawValue() {
        #expect(LightAction.warm.rawValue == "warm")
    }

    @Test func coolRawValue() {
        #expect(LightAction.cool.rawValue == "cool")
    }

    @Test func increaseIntensityRawValue() {
        #expect(LightAction.increaseIntensity.rawValue == "increase_intensity")
    }

    @Test func reduceIntensityRawValue() {
        #expect(LightAction.reduceIntensity.rawValue == "reduce_intensity")
    }

    @Test func allCasesRoundTripThroughRawValue() {
        let cases: [LightAction] = [.deepen, .energize, .warm, .cool, .increaseIntensity, .reduceIntensity]
        for action in cases {
            let recreated = LightAction(rawValue: action.rawValue)
            #expect(recreated == action,
                "Round-trip failed for '\(action.rawValue)': got \(String(describing: recreated))")
        }
    }
}

// MARK: - Codable Round-Trip

struct LightActionCodableTests {

    @Test func encodesAndDecodesAllCases() throws {
        let cases: [LightAction] = [.deepen, .energize, .warm, .cool, .increaseIntensity, .reduceIntensity]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for action in cases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(LightAction.self, from: data)
            #expect(decoded == action,
                "Codable round-trip failed for case '\(action.rawValue)'")
        }
    }

    @Test func keyMomentCodableRoundTrip() throws {
        let moment = KeyMoment(time: 120.0, description: "Phase shift", action: .deepen)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(moment)
        let decoded = try decoder.decode(KeyMoment.self, from: data)
        #expect(decoded.action == .deepen)
        #expect(decoded.time == 120.0)
        #expect(decoded.description == "Phase shift")
    }
}

// MARK: - KeyMoment Action Type

struct KeyMomentActionTypeTests {

    @Test func keyMomentStoresLightAction() {
        let moment = KeyMoment(time: 0, description: "test", action: .energize)
        #expect(moment.action == .energize)
    }

    @Test func allActionsCanBeStoredInKeyMoment() {
        let actions: [LightAction] = [.deepen, .energize, .warm, .cool, .increaseIntensity, .reduceIntensity]
        for action in actions {
            let moment = KeyMoment(time: 0, description: "x", action: action)
            #expect(moment.action == action)
        }
    }
}

// MARK: - adjustmentForKeyMoment dispatch

@MainActor
struct AdjustmentForKeyMomentTests {

    private let gen = SessionGenerator()

    @Test func energizeGivesHighFrequency() {
        let moment = KeyMoment(time: 0, description: "x", action: .energize)
        let adj = gen.adjustmentForKeyMoment(moment)
        #expect(adj.frequency >= 12.0,
            "energize must produce high frequency (≥12 Hz), got \(adj.frequency)")
    }

    @Test func deepenGivesLowFrequency() {
        let moment = KeyMoment(time: 0, description: "x", action: .deepen)
        let adj = gen.adjustmentForKeyMoment(moment)
        #expect(adj.frequency <= 8.0,
            "deepen must produce low frequency (≤8 Hz), got \(adj.frequency)")
    }

    @Test func warmGivesLowColorTemperature() {
        let moment = KeyMoment(time: 0, description: "x", action: .warm)
        let adj = gen.adjustmentForKeyMoment(moment)
        #expect(adj.colorTemperature <= 3500,
            "warm must produce low color temperature (≤3500 K), got \(adj.colorTemperature)")
    }

    @Test func coolGivesHighColorTemperature() {
        let moment = KeyMoment(time: 0, description: "x", action: .cool)
        let adj = gen.adjustmentForKeyMoment(moment)
        #expect(adj.colorTemperature >= 4000,
            "cool must produce high color temperature (≥4000 K), got \(adj.colorTemperature)")
    }

    @Test func allCasesProduceValidParameters() {
        let cases: [LightAction] = [.deepen, .energize, .warm, .cool, .increaseIntensity, .reduceIntensity]
        for action in cases {
            let moment = KeyMoment(time: 0, description: "x", action: action)
            let adj = gen.adjustmentForKeyMoment(moment)
            #expect(adj.frequency >= 0.5 && adj.frequency <= 40.0,
                "\(action.rawValue) frequency \(adj.frequency) Hz out of valid range")
            #expect(adj.intensity >= 0.0 && adj.intensity <= 1.0,
                "\(action.rawValue) intensity \(adj.intensity) out of [0, 1]")
            #expect(adj.colorTemperature >= 2000 && adj.colorTemperature <= 7000,
                "\(action.rawValue) colorTemperature \(adj.colorTemperature) K out of range")
        }
    }

    @Test func deepenAndEnergizeHaveDistinctFrequencies() {
        let deepenMoment = KeyMoment(time: 0, description: "x", action: .deepen)
        let energizeMoment = KeyMoment(time: 0, description: "x", action: .energize)
        let deepenAdj = gen.adjustmentForKeyMoment(deepenMoment)
        let energizeAdj = gen.adjustmentForKeyMoment(energizeMoment)
        #expect(energizeAdj.frequency > deepenAdj.frequency,
            "energize (\(energizeAdj.frequency) Hz) must be higher than deepen (\(deepenAdj.frequency) Hz)")
    }
}
