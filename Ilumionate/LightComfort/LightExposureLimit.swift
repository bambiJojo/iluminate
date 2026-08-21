//
//  LightExposureLimit.swift
//  Ilumionate
//
//  User-selectable comfort limit for one continuous light-playback attempt.
//

import Foundation

nonisolated enum LightExposureLimit: Int, CaseIterable, Identifiable, Sendable {
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case twentyMinutes = 20
    case thirtyMinutes = 30
    case fortyFiveMinutes = 45
    case sixtyMinutes = 60

    static let recommended = LightExposureLimit.twentyMinutes

    var id: Int { rawValue }

    var duration: TimeInterval {
        TimeInterval(rawValue * 60)
    }

    var displayName: String {
        rawValue == 60 ? "1 hr" : "\(rawValue) min"
    }

    init(storedMinutes: Int) {
        self = Self(rawValue: storedMinutes) ?? .recommended
    }
}
