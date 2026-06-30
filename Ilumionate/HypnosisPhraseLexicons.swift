//
//  HypnosisPhraseLexicons.swift
//  Ilumionate
//
//  Extracted from HypnosisPhaseAnalyzer.swift (structural decomposition).
//

import Foundation

nonisolated struct CuratedHypnosisPhrasePrior: Sendable {
    let phrase: String
    let phase: HypnosisMetadata.Phase
    let weight: Double
    let sourceLabel: String
    let sourceURL: String
}

nonisolated enum CuratedHypnosisPhraseLibrary {
    static let priors: [CuratedHypnosisPhrasePrior] = [
        CuratedHypnosisPhrasePrior(
            phrase: "close your eyes",
            phase: .induction,
            weight: 3.8,
            sourceLabel: "Learn Hypnosis - Breathing With The Eyes",
            sourceURL: "https://learn.nimja.com/inductions/breathing_with_the_eyes"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "take a deep comfortable breath",
            phase: .induction,
            weight: 3.3,
            sourceLabel: "Learn Hypnosis - Breathing With The Eyes",
            sourceURL: "https://learn.nimja.com/inductions/breathing_with_the_eyes"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "feel your body relax",
            phase: .induction,
            weight: 3.2,
            sourceLabel: "Learn Hypnosis - Breathing With The Eyes",
            sourceURL: "https://learn.nimja.com/inductions/breathing_with_the_eyes"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "relax more with every breath",
            phase: .deepening,
            weight: 3.9,
            sourceLabel: "Learn Hypnosis - Breathing With The Eyes",
            sourceURL: "https://learn.nimja.com/inductions/breathing_with_the_eyes"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "deeper and deeper",
            phase: .deepening,
            weight: 4.1,
            sourceLabel: "Sleep (2014) hypnotic deepening study",
            sourceURL: "https://pubmed.ncbi.nlm.nih.gov/24882909/"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "sleep deeper",
            phase: .deepening,
            weight: 3.6,
            sourceLabel: "Sleep (2014) hypnotic deepening study",
            sourceURL: "https://pubmed.ncbi.nlm.nih.gov/24882909/"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "open your eyes",
            phase: .deepening,
            weight: 3.9,
            sourceLabel: "Learn Hypnosis - Breathing With The Eyes",
            sourceURL: "https://learn.nimja.com/inductions/breathing_with_the_eyes"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "open your eyes close your eyes",
            phase: .deepening,
            weight: 4.2,
            sourceLabel: "Learn Hypnosis - Fractionation",
            sourceURL: "https://learn.nimja.com/techniques/fractionation"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "you are aware and yet you are not aware",
            phase: .deepening,
            weight: 4.0,
            sourceLabel: "Learn Hypnosis - Confusion Induction",
            sourceURL: "https://learn.nimja.com/inductions/confusion"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "conscious mind",
            phase: .deepening,
            weight: 2.4,
            sourceLabel: "Learn Hypnosis - Confusion Induction",
            sourceURL: "https://learn.nimja.com/inductions/confusion"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "unconscious mind",
            phase: .deepening,
            weight: 2.8,
            sourceLabel: "Learn Hypnosis - Confusion Induction",
            sourceURL: "https://learn.nimja.com/inductions/confusion"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "from now on",
            phase: .suggestions,
            weight: 3.5,
            sourceLabel: "Existing analyzer prior",
            sourceURL: "app://local/analyzer"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "every time you",
            phase: .conditioning,
            weight: 3.8,
            sourceLabel: "Learn Hypnosis - Triggers",
            sourceURL: "https://learn.nimja.com/techniques/triggers"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "whenever i say",
            phase: .conditioning,
            weight: 4.0,
            sourceLabel: "Learn Hypnosis - Triggers",
            sourceURL: "https://learn.nimja.com/techniques/triggers"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "when i snap my fingers",
            phase: .conditioning,
            weight: 4.2,
            sourceLabel: "Existing analyzer prior",
            sourceURL: "app://local/analyzer"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "wide awake",
            phase: .emergence,
            weight: 3.9,
            sourceLabel: "Existing analyzer prior",
            sourceURL: "app://local/analyzer"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "back in the room",
            phase: .emergence,
            weight: 3.8,
            sourceLabel: "Existing analyzer prior",
            sourceURL: "app://local/analyzer"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "fully alert",
            phase: .emergence,
            weight: 3.8,
            sourceLabel: "Existing analyzer prior",
            sourceURL: "app://local/analyzer"
        ),
        CuratedHypnosisPhrasePrior(
            phrase: "count to five",
            phase: .emergence,
            weight: 4.0,
            sourceLabel: "Existing analyzer prior",
            sourceURL: "app://local/analyzer"
        )
    ]

    static func priors(for phase: HypnosisMetadata.Phase) -> [CuratedHypnosisPhrasePrior] {
        priors.filter { $0.phase.labelingPhase == phase.labelingPhase }
    }

    static func normalizedPriorMap(
        for phase: HypnosisMetadata.Phase
    ) -> [String: CuratedHypnosisPhrasePrior] {
        Dictionary(uniqueKeysWithValues: priors(for: phase).map { prior in
            (normalize(prior.phrase), prior)
        })
    }

    private static func normalize(_ phrase: String) -> String {
        phrase
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { String($0).lowercased() }
            .joined(separator: " ")
    }
}

nonisolated enum HypnosisWaymarkerLexicon {
    struct Pattern: Sendable {
        let phrase: String
        let phase: HypnosisMetadata.Phase
        let weight: Double
    }

    static let allPatterns: [Pattern] = [
        Pattern(phrase: "begin to relax", phase: .induction, weight: 1.0),
        Pattern(phrase: "starting to relax", phase: .induction, weight: 0.9),
        Pattern(phrase: "close your eyes", phase: .induction, weight: 1.0),
        Pattern(phrase: "take a deep breath", phase: .induction, weight: 0.85),
        Pattern(phrase: "open your eyes", phase: .deepening, weight: 1.0),
        Pattern(phrase: "eyes open", phase: .deepening, weight: 0.85),
        Pattern(phrase: "drop back down", phase: .deepening, weight: 1.0),
        Pattern(phrase: "go deeper", phase: .deepening, weight: 1.0),
        Pattern(phrase: "deeper and deeper", phase: .deepening, weight: 1.0),
        Pattern(phrase: "drift deeper", phase: .deepening, weight: 0.9),
        Pattern(phrase: "sink deeper", phase: .deepening, weight: 0.9),
        Pattern(phrase: "the more you try", phase: .deepening, weight: 1.0),
        Pattern(phrase: "the more you listen", phase: .deepening, weight: 0.85),
        Pattern(phrase: "from now on", phase: .suggestions, weight: 1.0),
        Pattern(phrase: "you will find", phase: .suggestions, weight: 0.9),
        Pattern(phrase: "every time you", phase: .conditioning, weight: 1.0),
        Pattern(phrase: "when i snap my fingers", phase: .conditioning, weight: 1.0),
        Pattern(phrase: "snap my fingers", phase: .conditioning, weight: 0.9),
        Pattern(phrase: "obey now", phase: .brainwashing, weight: 1.0),
        Pattern(phrase: "repeat after me", phase: .brainwashing, weight: 0.9),
        Pattern(phrase: "come back now", phase: .emergence, weight: 1.0),
        Pattern(phrase: "wide awake", phase: .emergence, weight: 1.0),
        Pattern(phrase: "open your eyes now", phase: .emergence, weight: 0.85),
        Pattern(phrase: "bringing awareness back", phase: .emergence, weight: 0.9)
    ]

    static func phrases(for phase: HypnosisMetadata.Phase) -> Set<String> {
        Set(allPatterns.filter { $0.phase.labelingPhase == phase.labelingPhase }.map(\.phrase))
    }
}
