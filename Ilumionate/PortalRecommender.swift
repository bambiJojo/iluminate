//
//  PortalRecommender.swift
//  Ilumionate
//
//  Chooses the best-fit session for the Portal orb based on time of day,
//  reusing the existing BrainwaveCategory frequency ranges.
//

import Foundation

enum PortalRecommender {

    /// Maps an hour (0–23) to the brainwave category the Portal should offer.
    static func category(forHour hour: Int) -> BrainwaveCategory {
        switch hour {
        case 22...23, 0...4:  return .sleep    // night → wind down to sleep
        case 5...10:          return .energy   // morning → wake up
        case 11...15:         return .focus    // midday → focus
        default:              return .relax    // late afternoon/evening
        }
    }

    /// Picks the best session for the given hour: the first whose opening
    /// frequency lands in the time-appropriate category, else the first session.
    static func recommend(from sessions: [LightSession], forHour hour: Int) -> LightSession? {
        guard !sessions.isEmpty else { return nil }
        let cat = category(forHour: hour)
        let range = cat.frequencyRange
        let match = sessions.first { session in
            guard let first = session.light_score.sorted(by: { $0.time < $1.time }).first else { return false }
            return range.contains(first.frequency)
        }
        return match ?? sessions.first
    }

    /// Convenience using the current hour.
    static func recommend(from sessions: [LightSession], now: Date = .now) -> LightSession? {
        recommend(from: sessions, forHour: Calendar.current.component(.hour, from: now))
    }
}
