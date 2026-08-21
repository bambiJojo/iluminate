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

    /// The phases the analyzer is trained to emit, in the order a session moves
    /// through them.
    ///
    /// Chosen to match what the light engine actually distinguishes. A phase
    /// changes light through exactly two things — which `intensityContour`
    /// branch it takes and its `tranceDepthEstimate` — and by that measure most
    /// of the vocabulary is not redundant:
    ///
    ///     induction      decay     0.22
    ///     fractionation  fast-osc  0.42
    ///     deepening      decay     0.62
    ///     suggestions    osc       0.72
    ///     brainwashing   osc       0.82
    ///     conditioning   osc       0.58
    ///     emergence      rise      0.24
    ///
    /// `fractionation` and `conditioning` were added because collapsing them
    /// was the most expensive part of the old five-phase target: fractionation
    /// lost a unique contour *and* moved depth 0.42 → 0.62, and conditioning is
    /// *shallower* than suggestions, so folding it in made the light deeper than
    /// the hypnotist intended across long closing sections.
    ///
    /// `pre_talk` and `confusion` are still folded away because they are exactly
    /// identical in light to `induction` and `deepening` — nothing is lost.
    /// `therapeutic_work` and `erotic_suggestions` fold into `suggestions` at a
    /// cost of 0.12 and 0.06 depth, the smallest losses available, to keep the
    /// class count down where classification is already the dominant error.
    public static let orderedHypnosisPhases: [TrancePhase] = [
        .induction, .fractionation, .deepening, .suggestions,
        .brainwashing, .conditioning, .emergence,
    ]

    public var isLabelingPhase: Bool {
        Self.orderedHypnosisPhases.contains(self)
    }

    /// Projects a labelled phase onto the vocabulary the analyzer is trained to
    /// emit. Applied where training data is exported and where light is chosen —
    /// never in storage, which keeps the phase the labeller actually chose.
    public var labelingPhase: TrancePhase {
        switch self {
        // Identical light to their targets; folding them costs nothing.
        case .preTalk:
            return .induction
        case .confusion:
            return .deepening
        // Nearest target by trance depth: 0.84 and 0.78 against suggestions'
        // 0.72, the smallest losses in the vocabulary.
        case .therapy, .eroticSuggestions:
            return .suggestions
        case .transitional:
            return .deepening
        default:
            return self
        }
    }

    /// Decodes the phase that was actually labelled.
    ///
    /// This used to remap `pre_talk` to `.induction`, `fractionation`/`confusion`
    /// to `.deepening` and the suggestion variants to `.suggestions`. That made
    /// the five-bucket projection a property of storage rather than of use, with
    /// two measured consequences: loading a label file and saving it rewrote the
    /// labels on disk, and `SessionGenerator.intensityContour`'s distinct
    /// `.fractionation` contour became unreachable for any persisted analysis.
    ///
    /// The projection is still wanted — it is what chooses light — and lives in
    /// `labelingPhase`, applied at the point of use as the rest of the codebase
    /// already does.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let phase = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown trance phase: \(rawValue)"
            )
        }
        self = phase
    }

    /// Writes back the phase that was labelled, so a load/save round trip is
    /// lossless. See `init(from:)` for why this previously collapsed.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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
