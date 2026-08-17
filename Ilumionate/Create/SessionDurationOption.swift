//  SessionDurationOption.swift
//  Ilumionate
//
//  What the Duration tile taps through. Open-ended is first and is the default:
//  a Visual Field session is something you might leave running like a fireplace,
//  so a timer is the opt-in, not the assumption.

import Foundation

enum SessionDurationOption: String, CaseIterable, Identifiable, Sendable {
    case openEnded
    case tenMinutes
    case twentyMinutes
    case thirtyMinutes
    case sixtyMinutes

    var id: String { rawValue }

    var seconds: TimeInterval? {
        switch self {
        case .openEnded:     return nil
        case .tenMinutes:    return 600
        case .twentyMinutes: return 1_200
        case .thirtyMinutes: return 1_800
        case .sixtyMinutes:  return 3_600
        }
    }

    var label: String {
        guard let seconds else { return "∞" }
        return "\(Int(seconds / 60))m"
    }

    var accessibilityLabel: String {
        guard let seconds else { return "Open ended" }
        return "\(Int(seconds / 60)) minutes"
    }

    var next: SessionDurationOption {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return all[0] }
        return all[(index + 1) % all.count]
    }

    /// Resolves a stored duration to the nearest option. A value off the list
    /// picks the closest rather than falling back to open-ended, which would
    /// silently drop a user's timer.
    init(seconds: TimeInterval?) {
        guard let seconds else {
            self = .openEnded
            return
        }
        let timed = Self.allCases.filter { $0.seconds != nil }
        self = timed.min {
            abs(($0.seconds ?? 0) - seconds) < abs(($1.seconds ?? 0) - seconds)
        } ?? .openEnded
    }
}
