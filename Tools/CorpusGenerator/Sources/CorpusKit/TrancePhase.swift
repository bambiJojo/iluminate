//  TrancePhase.swift
//  CorpusKit
//
//  Standalone phase enum shared by the iOS analysis pipeline, the LumeLabel
//  macOS labeling utility, the evaluation harness, and the corpus generator.
//  Single source of truth — lives in CorpusKit, imported everywhere else.
//
import Foundation

public enum TrancePhase: String, Codable, Sendable, CaseIterable {
    case preTalk = "pre_talk"
    case induction = "induction"
    case fractionation = "fractionation"
    case deepening = "deepening"
    case confusion = "confusion"
    case suggestions = "suggestions"
    case therapy = "therapeutic_work"
    case eroticSuggestions = "erotic_suggestions"
    case brainwashing = "brainwashing"
    case conditioning = "post_hypnotic_conditioning"
    case emergence = "emergence"

    case transitional // Used when phases blend

    public static let orderedHypnosisPhases: [TrancePhase] = [
        .preTalk, .induction, .fractionation, .deepening, .confusion,
        .therapy, .suggestions, .eroticSuggestions, .brainwashing,
        .conditioning, .emergence,
    ]

    public var displayName: String {
        switch self {
        case .preTalk: return "Pre-Talk"
        case .induction: return "Induction"
        case .fractionation: return "Fractionation"
        case .deepening: return "Deepening"
        case .confusion: return "Confusion"
        case .therapy: return "Therapeutic Work"
        case .suggestions: return "Suggestions"
        case .eroticSuggestions: return "Erotic Suggestions"
        case .brainwashing: return "Brainwashing"
        case .conditioning: return "Post-Hypnotic Conditioning"
        case .emergence: return "Emergence"
        case .transitional: return "Transitional"
        }
    }

    public var tranceDepthEstimate: Double {
        switch self {
        case .preTalk: return 0.05
        case .induction: return 0.22
        case .fractionation: return 0.42
        case .deepening: return 0.62
        case .confusion: return 0.74
        case .therapy: return 0.84
        case .suggestions: return 0.72
        case .eroticSuggestions: return 0.78
        case .brainwashing: return 0.82
        case .conditioning: return 0.58
        case .emergence: return 0.24
        case .transitional: return 0.40
        }
    }
}
