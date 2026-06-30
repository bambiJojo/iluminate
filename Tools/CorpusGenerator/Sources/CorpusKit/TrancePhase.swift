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

    // Legacy/technique-specific labels. These decode and export as structural
    // phases so older corpora continue to load while new training data uses one
    // target taxonomy.
    case therapy = "therapeutic_work"
    case eroticSuggestions = "erotic_suggestions"
    case conditioning = "post_hypnotic_conditioning"

    case brainwashing = "brainwashing"
    case emergence = "emergence"

    case transitional // Used when phases blend

    public static let orderedHypnosisPhases: [TrancePhase] = [
        .induction, .deepening, .suggestions, .brainwashing, .emergence,
    ]

    public var isLabelingPhase: Bool {
        Self.orderedHypnosisPhases.contains(self)
    }

    public var labelingPhase: TrancePhase {
        switch self {
        case .preTalk:
            return .induction
        case .fractionation, .confusion:
            return .deepening
        case .therapy, .eroticSuggestions, .conditioning:
            return .suggestions
        case .transitional:
            return .deepening
        default:
            return self
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.preTalk.rawValue:
            self = .induction
        case Self.fractionation.rawValue, Self.confusion.rawValue:
            self = .deepening
        case Self.therapy.rawValue, Self.eroticSuggestions.rawValue, Self.conditioning.rawValue:
            self = .suggestions
        default:
            guard let phase = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown trance phase: \(rawValue)"
                )
            }
            self = phase
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let encodedPhase: TrancePhase = switch self {
        case .preTalk:
            .induction
        case .fractionation, .confusion:
            .deepening
        case .therapy, .eroticSuggestions, .conditioning:
            .suggestions
        default:
            self
        }
        try container.encode(encodedPhase.rawValue)
    }

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
        case .preTalk: return 0.22
        case .induction: return 0.22
        case .fractionation: return 0.42
        case .deepening, .confusion: return 0.62
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
