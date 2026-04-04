//
//  TrancePhase.swift
//  Ilumionate
//
//  Standalone phase enum shared between the iOS analysis pipeline and the
//  LumeLabel macOS labeling utility.
//

import Foundation

nonisolated enum TrancePhase: String, Codable, Sendable, CaseIterable {
    case preTalk = "pre_talk"
    case induction
    case deepening
    case therapy
    case suggestions
    case conditioning = "post_hypnotic_conditioning"
    case emergence
    case transitional // Used when phases blend

    nonisolated var displayName: String {
        switch self {
        case .preTalk: return "Pre-Talk"
        case .induction: return "Induction"
        case .deepening: return "Deepening"
        case .therapy: return "Therapeutic Work"
        case .suggestions: return "Suggestions"
        case .conditioning: return "Post-Hypnotic Conditioning"
        case .emergence: return "Emergence"
        case .transitional: return "Transitional"
        }
    }
}
