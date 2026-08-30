//
//  CorpusPhaseKnowledgeSnapshot.swift
//  Ilumionate
//
//  Codable, aggregate-only representation of reviewed analyzer knowledge.
//

import Foundation

/// A production-safe projection of learned analyzer knowledge.
///
/// The snapshot contains aggregate weights and transitions, never source audio
/// or full transcripts. This lets an App Store build use the same reviewed
/// evidence as LumeLabel without requiring the private training corpus on the
/// user's device.
nonisolated struct CorpusPhaseKnowledgeSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1
    static let defaultResourceName = "AnalyzerKnowledge_default"

    let schemaVersion: Int
    let keywordWeights: [String: [String: Double]]
    let phaseTokens: [String: [String]]
    let phraseWeights: [String: [String: Double]]
    let phraseAssociations: [HypnosisPhraseAssociation]
    let sourcePackLabels: [String: String]
    let keywordSourcePacks: [String: [String: [String]]]
    let phraseSourcePacks: [String: [String: [String]]]
    let transitionPriors: [String: [String: Double]]
    let fewShotExamples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample]

    init(
        knowledge: CorpusPhaseKnowledge,
        fewShotExamples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        keywordWeights = Self.encodePhaseMap(knowledge.keywordWeights)
        phaseTokens = Dictionary(uniqueKeysWithValues: knowledge.phaseTokens.map { phase, tokens in
            (phase.rawValue, tokens.sorted())
        })
        phraseWeights = Self.encodePhaseMap(knowledge.phraseWeights)
        phraseAssociations = knowledge.phraseAssociations
            .values
            .flatMap { $0 }
            .sorted {
                if $0.phase.rawValue == $1.phase.rawValue { return $0.phrase < $1.phrase }
                return $0.phase.rawValue < $1.phase.rawValue
            }
        sourcePackLabels = knowledge.sourcePackLabels
        keywordSourcePacks = Self.encodeSourcePacks(knowledge.keywordSourcePacks)
        phraseSourcePacks = Self.encodeSourcePacks(knowledge.phraseSourcePacks)
        transitionPriors = Dictionary(uniqueKeysWithValues: knowledge.transitionPriors.map { phase, priors in
            (
                phase.rawValue,
                Dictionary(uniqueKeysWithValues: priors.map { ($0.key.rawValue, $0.value) })
            )
        })
        // Corpus few-shots contain long source excerpts. Keep them out of a
        // shipping snapshot unless a caller deliberately supplies a reviewed,
        // redistribution-safe set. The app's curated config examples remain
        // available to the chunk classifier.
        self.fewShotExamples = fewShotExamples
    }

    var knowledge: CorpusPhaseKnowledge {
        CorpusPhaseKnowledge(
            keywordWeights: Self.decodePhaseMap(keywordWeights),
            phaseTokens: Dictionary(uniqueKeysWithValues: phaseTokens.compactMap { phaseName, tokens in
                guard let phase = HypnosisMetadata.Phase(rawValue: phaseName) else { return nil }
                return (phase, Set(tokens))
            }),
            phraseWeights: Self.decodePhaseMap(phraseWeights),
            phraseAssociations: Dictionary(grouping: phraseAssociations, by: \.phase),
            sourcePackLabels: sourcePackLabels,
            keywordSourcePacks: Self.decodeSourcePacks(keywordSourcePacks),
            phraseSourcePacks: Self.decodeSourcePacks(phraseSourcePacks),
            transitionPriors: Dictionary(uniqueKeysWithValues: transitionPriors.compactMap {
                phaseName,
                priors -> (HypnosisMetadata.Phase, [HypnosisMetadata.Phase: Double])? in
                guard let phase = HypnosisMetadata.Phase(rawValue: phaseName) else { return nil }
                let decoded = Dictionary(uniqueKeysWithValues: priors.compactMap {
                    nextName,
                    value -> (HypnosisMetadata.Phase, Double)? in
                    guard let next = HypnosisMetadata.Phase(rawValue: nextName) else { return nil }
                    return (next, value)
                })
                return (phase, decoded)
            }),
            fewShotExamples: fewShotExamples
        )
    }

    static func loadDefault(bundle: Bundle = .main) -> CorpusPhaseKnowledge? {
        guard let url = bundle.url(forResource: defaultResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.schemaVersion == currentSchemaVersion else {
            return nil
        }
        return snapshot.knowledge
    }

    private static func encodePhaseMap(
        _ values: [HypnosisMetadata.Phase: [String: Double]]
    ) -> [String: [String: Double]] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }

    private static func decodePhaseMap(
        _ values: [String: [String: Double]]
    ) -> [HypnosisMetadata.Phase: [String: Double]] {
        Dictionary(uniqueKeysWithValues: values.compactMap { phaseName, weights in
            HypnosisMetadata.Phase(rawValue: phaseName).map { ($0, weights) }
        })
    }

    private static func encodeSourcePacks(
        _ values: [HypnosisMetadata.Phase: [String: Set<String>]]
    ) -> [String: [String: [String]]] {
        Dictionary(uniqueKeysWithValues: values.map { phase, termPacks in
            (
                phase.rawValue,
                Dictionary(uniqueKeysWithValues: termPacks.map { ($0.key, $0.value.sorted()) })
            )
        })
    }

    private static func decodeSourcePacks(
        _ values: [String: [String: [String]]]
    ) -> [HypnosisMetadata.Phase: [String: Set<String>]] {
        Dictionary(uniqueKeysWithValues: values.compactMap { phaseName, termPacks in
            guard let phase = HypnosisMetadata.Phase(rawValue: phaseName) else { return nil }
            return (
                phase,
                Dictionary(uniqueKeysWithValues: termPacks.map { ($0.key, Set($0.value)) })
            )
        })
    }
}
