//
//  AudioContentType.swift
//  Ilumionate
//
//  Standalone content-type enum shared between the iOS analysis pipeline and the
//  LumeLabel macOS labeling utility.
//

import Foundation

nonisolated enum AudioContentType: String, Codable, Sendable, CaseIterable {
    case hypnosis
    case meditation
    case music
    case guidedImagery
    case affirmations
    case eroticHypnosis
    case brainwave
    case asmr
    case sleepHypnosis
    case unknown

    var displayName: String {
        switch self {
        case .hypnosis: return "Hypnosis"
        case .meditation: return "Meditation"
        case .music: return "Music"
        case .guidedImagery: return "Guided Imagery"
        case .affirmations: return "Affirmations"
        case .eroticHypnosis: return "Erotic Hypnosis"
        case .brainwave: return "Brainwave"
        case .asmr: return "ASMR"
        case .sleepHypnosis: return "Sleep Hypnosis"
        case .unknown: return "Unknown"
        }
    }

    var isHypnosisLike: Bool {
        switch self {
        case .hypnosis, .eroticHypnosis, .sleepHypnosis:
            return true
        case .meditation, .music, .guidedImagery, .affirmations, .brainwave, .asmr, .unknown:
            return false
        }
    }

    static func parse(_ raw: String) -> Self {
        let normalized = raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\s_-]+", with: "", options: .regularExpression)

        switch normalized {
        case "hypnosis":
            return .hypnosis
        case "meditation":
            return .meditation
        case "music":
            return .music
        case "guidedimagery":
            return .guidedImagery
        case "affirmations":
            return .affirmations
        case "erotichypnosis", "sensualhypnosis":
            return .eroticHypnosis
        case "brainwave", "brainwaveentrainment", "binaural", "isochronic", "isochronal":
            return .brainwave
        case "asmr":
            return .asmr
        case "sleephypnosis", "sleepaid", "sleep":
            return .sleepHypnosis
        default:
            return .unknown
        }
    }
}
