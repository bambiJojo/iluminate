//
//  CorpusPhaseKnowledge.swift
//  Ilumionate
//
//  Extracted from HypnosisPhaseAnalyzer.swift (structural decomposition).
//

import Foundation

// MARK: - Corpus Knowledge

nonisolated struct CorpusPhaseKnowledge: Sendable {
    var keywordWeights: [HypnosisMetadata.Phase: [String: Double]] = [:]
    var phaseTokens: [HypnosisMetadata.Phase: Set<String>] = [:]
    var phraseWeights: [HypnosisMetadata.Phase: [String: Double]] = [:]
    var phraseAssociations: [HypnosisMetadata.Phase: [HypnosisPhraseAssociation]] = [:]
    var sourcePackLabels: [String: String] = [:]
    var keywordSourcePacks: [HypnosisMetadata.Phase: [String: Set<String>]] = [:]
    var phraseSourcePacks: [HypnosisMetadata.Phase: [String: Set<String>]] = [:]
    var transitionPriors: [HypnosisMetadata.Phase: [HypnosisMetadata.Phase: Double]] = [:]
    var fewShotExamples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample] = []

    static let empty = CorpusPhaseKnowledge()
}

nonisolated final class CorpusPhaseKnowledgeCache: @unchecked Sendable {
    static let shared = CorpusPhaseKnowledgeCache()

    private let condition = NSCondition()
    private let loader: @Sendable () -> CorpusPhaseKnowledge
    private var cachedKnowledge: CorpusPhaseKnowledge?
    private var isLoading = false
    private var generation = 0

    init(
        loader: @escaping @Sendable () -> CorpusPhaseKnowledge = CorpusPhaseKnowledgeCache.loadKnowledge
    ) {
        self.loader = loader
    }

    func knowledge() -> CorpusPhaseKnowledge {
        condition.lock()
        while isLoading {
            condition.wait()
        }
        if let cachedKnowledge {
            condition.unlock()
            return cachedKnowledge
        }

        isLoading = true
        let loadingGeneration = generation
        condition.unlock()

        let loadedKnowledge = loader()

        condition.lock()
        if generation == loadingGeneration {
            cachedKnowledge = loadedKnowledge
        }
        isLoading = false
        let result = cachedKnowledge ?? loadedKnowledge
        condition.broadcast()
        condition.unlock()
        return result
    }

    /// Clears the immutable snapshot after training data or script corpus files change.
    /// The next reader performs one reload; ordinary reads do no filesystem work.
    func invalidate() {
        condition.lock()
        cachedKnowledge = nil
        generation += 1
        condition.broadcast()
        condition.unlock()
    }

    private static func loadKnowledge() -> CorpusPhaseKnowledge {
        let dataset = try? AnalyzerOptimizationDataset.load()
        let scriptCorpus = ScriptPhaseCorpus.loadDefault()
        guard dataset != nil || !scriptCorpus.examples.isEmpty else {
            return .empty
        }
        return CorpusPhaseKnowledgeBuilder(dataset: dataset, scriptCorpus: scriptCorpus).build()
    }
}

nonisolated struct CorpusPhaseKnowledgeBuilder {
    private struct CachedTranscriptionPayload: Codable {
        let schemaVersion: Int
        let cachedAt: Date
        let exampleID: UUID
        let audioSHA256: String
        let transcription: AudioTranscriptionResult
    }

    private struct FewShotCandidate {
        let example: AnalyzerConfig.ChunkedAnalyzer.FewShotExample
        let score: Double
    }

    let dataset: AnalyzerOptimizationDataset?
    let scriptCorpus: ScriptPhaseCorpus

    init(
        dataset: AnalyzerOptimizationDataset?,
        scriptCorpus: ScriptPhaseCorpus = .empty
    ) {
        self.dataset = dataset
        self.scriptCorpus = scriptCorpus
    }

    /// Mutable evidence tally accumulated across the dataset, then reduced into
    /// final weighted knowledge by `assembleKnowledge(from:)`.
    private struct Accumulator {
        var keywordScores: [HypnosisMetadata.Phase: [String: Double]] = [:]
        var tokenSets: [HypnosisMetadata.Phase: Set<String>] = [:]
        var phraseScores: [HypnosisMetadata.Phase: [String: Double]] = [:]
        var phraseSectionCounts: [HypnosisMetadata.Phase: [String: Int]] = [:]
        var phraseExampleIDs: [HypnosisMetadata.Phase: [String: Set<UUID>]] = [:]
        var sourcePackLabels: [String: String] = [:]
        var keywordSourcePacks: [HypnosisMetadata.Phase: [String: Set<String>]] = [:]
        var phraseSourcePacks: [HypnosisMetadata.Phase: [String: Set<String>]] = [:]
        var transitionCounts: [HypnosisMetadata.Phase: [HypnosisMetadata.Phase: Int]] = [:]
        var fewShotCandidates: [HypnosisMetadata.Phase: [FewShotCandidate]] = [:]
    }

    func build() -> CorpusPhaseKnowledge {
        var accumulator = Accumulator()
        seedCuratedPhrasePriors(into: &accumulator.phraseScores)
        if let dataset {
            for example in dataset.examples {
                accumulate(example: example, into: &accumulator)
            }
        }
        for scriptExample in scriptCorpus.examples {
            accumulate(scriptExample: scriptExample, into: &accumulator)
        }
        return assembleKnowledge(from: accumulator)
    }

    /// Tallies one example's evidence: phase-transition counts plus per-section signals.
    private func accumulate(
        example: AnalyzerOptimizationDataset.Example,
        into accumulator: inout Accumulator
    ) {
        guard let transcription = loadCachedTranscription(for: example) else { return }

        let labeledSections = example.phaseSegments.map { segment in
            PhaseSegment(
                id: segment.id,
                phase: segment.phase,
                startTime: segment.startTime,
                endTime: segment.endTime,
                characteristics: segment.phase.displayName,
                tranceDepthEstimate: segment.phase.tranceDepthEstimate
            )
        }

        let transcriptAnalysis = TranscriptFeatureAnalyzer().analyze(
            transcription: transcription,
            phases: labeledSections
        )

        for (lhs, rhs) in zip(example.phaseSegments, example.phaseSegments.dropFirst()) {
            accumulator.transitionCounts[lhs.phase, default: [:]][rhs.phase, default: 0] += 1
        }

        for section in transcriptAnalysis.sections {
            guard let phase = section.phase else { continue }
            accumulate(
                section: section,
                phase: phase,
                exampleID: example.id,
                transcription: transcription,
                into: &accumulator
            )
        }
    }

    /// Tallies folder/file-type script libraries as language evidence. Script
    /// examples do not add transition priors because they are not timed sessions.
    private func accumulate(
        scriptExample: ScriptPhaseExample,
        into accumulator: inout Accumulator
    ) {
        let phase = scriptExample.phase.labelingPhase
        let evidence = ScriptPhaseTextAnalyzer.evidence(in: scriptExample.text)
        recordSourcePackLabel(from: scriptExample, into: &accumulator)

        for statistic in evidence.words.prefix(16) {
            guard statistic.count >= 2 || statistic.share >= 0.015 else { continue }
            let score = min(2.8, Double(statistic.count) * 0.18 + statistic.share * 10.0)
            guard score >= 0.45 else { continue }
            accumulator.keywordScores[phase, default: [:]][statistic.term, default: 0.0] += score
            accumulator.tokenSets[phase, default: []].insert(statistic.term)
            recordSourcePack(
                from: scriptExample,
                phase: phase,
                term: statistic.term,
                into: &accumulator.keywordSourcePacks
            )
        }

        for statistic in evidence.phrases.prefix(16) {
            guard statistic.count >= 2 || statistic.share >= 0.010 else { continue }
            let score = min(3.2, Double(statistic.count) * 0.35 + statistic.share * 8.0)
            guard score >= 0.55 else { continue }
            accumulator.phraseScores[phase, default: [:]][statistic.term, default: 0.0] += score
            accumulator.phraseSectionCounts[phase, default: [:]][statistic.term, default: 0] += 1
            accumulator.phraseExampleIDs[phase, default: [:]][statistic.term, default: []].insert(scriptExample.id)
            recordSourcePack(
                from: scriptExample,
                phase: phase,
                term: statistic.term,
                into: &accumulator.phraseSourcePacks
            )
        }

        for match in evidence.waymarkerMatches where match.phase.labelingPhase == phase {
            accumulator.phraseScores[phase, default: [:]][match.phrase, default: 0.0] += match.score * 0.8
            accumulator.phraseSectionCounts[phase, default: [:]][match.phrase, default: 0] += 1
            accumulator.phraseExampleIDs[phase, default: [:]][match.phrase, default: []].insert(scriptExample.id)
            recordSourcePack(
                from: scriptExample,
                phase: phase,
                term: match.phrase,
                into: &accumulator.phraseSourcePacks
            )
        }

        if let fewShot = makeFewShotExample(for: scriptExample) {
            let score = min(Double(scriptExample.wordCount) / 120.0, 1.0)
                + Double(evidence.waymarkerMatches.count) * 0.25
            accumulator.fewShotCandidates[phase, default: []].append(
                FewShotCandidate(example: fewShot, score: score)
            )
        }
    }

    /// Tallies keyword, phrase, waymarker, and few-shot evidence for a single labeled section.
    private func accumulate(
        section: TranscriptSectionMetrics,
        phase: HypnosisMetadata.Phase,
        exampleID: UUID,
        transcription: AudioTranscriptionResult,
        into accumulator: inout Accumulator
    ) {
        let candidateWords = Array(section.topDistinctiveWords.prefix(8)) + Array(section.topWords.prefix(8))
        for statistic in candidateWords {
            guard statistic.word.count >= 4 else { continue }
            let score = max(0.0, statistic.normalizedShareLift - 0.9) + statistic.share * 4.0
            guard score > 0.35 else { continue }
            accumulator.keywordScores[phase, default: [:]][statistic.word, default: 0.0] += score
            accumulator.tokenSets[phase, default: []].insert(statistic.word)
        }

        for (phrase, score) in phraseCandidates(for: section, transcription: transcription) {
            accumulator.phraseScores[phase, default: [:]][phrase, default: 0.0] += score
            accumulator.phraseSectionCounts[phase, default: [:]][phrase, default: 0] += 1
            accumulator.phraseExampleIDs[phase, default: [:]][phrase, default: []].insert(exampleID)
        }
        for statistic in Array(section.topDistinctivePhrases.prefix(6)) {
            let score = max(0.0, statistic.normalizedShareLift - 1.0) + statistic.share * 3.5
            guard score > 0.30 else { continue }
            accumulator.phraseScores[phase, default: [:]][statistic.phrase, default: 0.0] += score
            accumulator.phraseSectionCounts[phase, default: [:]][statistic.phrase, default: 0] += 1
            accumulator.phraseExampleIDs[phase, default: [:]][statistic.phrase, default: []].insert(exampleID)
        }
        for match in section.waymarkerMatches where match.phase.labelingPhase == phase {
            accumulator.phraseScores[phase, default: [:]][match.phrase, default: 0.0] += match.score * 1.2
            accumulator.phraseSectionCounts[phase, default: [:]][match.phrase, default: 0] += 1
            accumulator.phraseExampleIDs[phase, default: [:]][match.phrase, default: []].insert(exampleID)
        }

        if let fewShot = makeFewShotExample(for: section, transcription: transcription) {
            let exampleScore = scoreFewShotCandidate(section: section)
            accumulator.fewShotCandidates[phase, default: []].append(
                FewShotCandidate(example: fewShot, score: exampleScore)
            )
        }
    }

    /// Reduces accumulated evidence into final weighted knowledge: keyword/phrase
    /// weights, phrase associations, normalized transition priors, and top few-shot examples.
    private func assembleKnowledge(from accumulator: Accumulator) -> CorpusPhaseKnowledge {
        var keywordWeights: [HypnosisMetadata.Phase: [String: Double]] = [:]
        var learnedPhraseWeights: [HypnosisMetadata.Phase: [String: Double]] = [:]
        var phraseAssociations: [HypnosisMetadata.Phase: [HypnosisPhraseAssociation]] = [:]
        for phase in TrancePhase.orderedHypnosisPhases {
            let learnedWords = accumulator.keywordScores[phase] ?? [:]
            let strongestWords = learnedWords
                .sorted { lhs, rhs in
                    if abs(lhs.value - rhs.value) < 0.0001 { return lhs.key < rhs.key }
                    return lhs.value > rhs.value
                }
                .prefix(18)

            keywordWeights[phase] = Dictionary(uniqueKeysWithValues: strongestWords.map { word, score in
                let learnedWeight = min(max(1.1 + score * 0.55, 1.1), 4.2)
                return (word, learnedWeight)
            })

            let associations = buildPhraseAssociations(
                for: phase,
                phraseScores: accumulator.phraseScores[phase] ?? [:],
                phraseSectionCounts: accumulator.phraseSectionCounts[phase] ?? [:],
                phraseExampleIDs: accumulator.phraseExampleIDs[phase] ?? [:],
                phraseSourcePacks: accumulator.phraseSourcePacks[phase] ?? [:],
                sourcePackLabels: accumulator.sourcePackLabels
            )
            phraseAssociations[phase] = associations
            learnedPhraseWeights[phase] = Dictionary(
                uniqueKeysWithValues: associations.prefix(18).map { ($0.phrase, $0.weight) }
            )
        }

        let transitionPriors = accumulator.transitionCounts.reduce(into: [HypnosisMetadata.Phase: [HypnosisMetadata.Phase: Double]]()) {
            partial, entry in
            let total = max(1, entry.value.values.reduce(0, +))
            partial[entry.key] = entry.value.mapValues { Double($0) / Double(total) }
        }

        let fewShotExamples = accumulator.fewShotCandidates
            .flatMap { phase, candidates in
                candidates
                    .sorted { lhs, rhs in
                        if abs(lhs.score - rhs.score) < 0.0001 {
                            return lhs.example.text.count < rhs.example.text.count
                        }
                        return lhs.score > rhs.score
                    }
                    .prefix(2)
                    .map(\.example)
            }
            .sorted { lhs, rhs in
                if abs(lhs.position - rhs.position) < 0.0001 {
                    return lhs.correctPhase < rhs.correctPhase
                }
                return lhs.position < rhs.position
            }
            .prefix(12)

        return CorpusPhaseKnowledge(
            keywordWeights: keywordWeights,
            phaseTokens: accumulator.tokenSets,
            phraseWeights: learnedPhraseWeights,
            phraseAssociations: phraseAssociations,
            sourcePackLabels: accumulator.sourcePackLabels,
            keywordSourcePacks: accumulator.keywordSourcePacks,
            phraseSourcePacks: accumulator.phraseSourcePacks,
            transitionPriors: transitionPriors,
            fewShotExamples: Array(fewShotExamples)
        )
    }

    private func seedCuratedPhrasePriors(
        into phraseScores: inout [HypnosisMetadata.Phase: [String: Double]]
    ) {
        for prior in CuratedHypnosisPhraseLibrary.priors {
            phraseScores[prior.phase.labelingPhase, default: [:]][prior.phrase, default: 0.0] += prior.weight
        }
    }

    private func recordSourcePackLabel(
        from scriptExample: ScriptPhaseExample,
        into accumulator: inout Accumulator
    ) {
        guard let sourcePackID = scriptExample.sourcePackID else { return }
        accumulator.sourcePackLabels[sourcePackID] = scriptExample.sourcePackLabel
            ?? defaultSourcePackLabel(for: sourcePackID)
    }

    private func recordSourcePack(
        from scriptExample: ScriptPhaseExample,
        phase: HypnosisMetadata.Phase,
        term: String,
        into sourcePacks: inout [HypnosisMetadata.Phase: [String: Set<String>]]
    ) {
        guard let sourcePackID = scriptExample.sourcePackID else { return }
        sourcePacks[phase, default: [:]][term, default: []].insert(sourcePackID)
    }

    private func defaultSourcePackLabel(for sourcePackID: String) -> String {
        let words = sourcePackID
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return "\(words.joined(separator: " ")) corpus"
    }

    private func buildPhraseAssociations(
        for phase: HypnosisMetadata.Phase,
        phraseScores: [String: Double],
        phraseSectionCounts: [String: Int],
        phraseExampleIDs: [String: Set<UUID>],
        phraseSourcePacks: [String: Set<String>],
        sourcePackLabels: [String: String]
    ) -> [HypnosisPhraseAssociation] {
        let curatedPhrases = CuratedHypnosisPhraseLibrary.normalizedPriorMap(for: phase)
        let allPhrases = Set(phraseScores.keys).union(curatedPhrases.keys)

        return allPhrases.compactMap { phrase in
            let corpusScore = max(0.0, (phraseScores[phrase] ?? 0.0) - (curatedPhrases[phrase]?.weight ?? 0.0))
            let learnedWeight = corpusScore > 0
                ? min(max(1.4 + corpusScore * 0.40, 1.4), 4.8)
                : 0.0
            let curatedWeight = curatedPhrases[phrase]?.weight ?? 0.0

            let finalWeight: Double
            let origin: HypnosisPhraseEvidenceOrigin
            switch (curatedWeight > 0, learnedWeight > 0) {
            case (true, true):
                finalWeight = min(max(curatedWeight, learnedWeight) + min(corpusScore * 0.15, 0.8), 5.0)
                origin = .blended
            case (true, false):
                finalWeight = curatedWeight
                origin = .curated
            case (false, true):
                finalWeight = learnedWeight
                origin = .corpus
            default:
                return nil
            }

            let sourcePackIDs = (phraseSourcePacks[phrase] ?? []).sorted()
            let sourcePackLabel = sourcePackIDs
                .compactMap { sourcePackLabels[$0] }
                .joined(separator: ", ")
            let displaySourceLabel: String?
            switch (curatedPhrases[phrase]?.sourceLabel, sourcePackLabel.isEmpty ? nil : sourcePackLabel) {
            case let (curated?, corpus?):
                displaySourceLabel = "\(curated) + \(corpus)"
            case let (curated?, nil):
                displaySourceLabel = curated
            case let (nil, corpus?):
                displaySourceLabel = corpus
            case (nil, nil):
                displaySourceLabel = nil
            }

            return HypnosisPhraseAssociation(
                phrase: phrase,
                phase: phase,
                weight: finalWeight,
                origin: origin,
                sourceLabel: displaySourceLabel,
                sourceURL: curatedPhrases[phrase]?.sourceURL,
                sourcePackIDs: sourcePackIDs,
                corpusSupport: corpusScore,
                sectionCount: phraseSectionCounts[phrase] ?? 0,
                exampleCount: phraseExampleIDs[phrase]?.count ?? 0
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.weight - rhs.weight) < 0.0001 { return lhs.phrase < rhs.phrase }
            return lhs.weight > rhs.weight
        }
        .prefix(18)
        .map { $0 }
    }

    private func loadCachedTranscription(
        for example: AnalyzerOptimizationDataset.Example
    ) -> AudioTranscriptionResult? {
        guard let dataset else { return nil }
        let cacheURL = dataset.transcriptCacheDirectory.appending(path: "\(example.example.audio.sha256).json")
        guard FileManager.default.fileExists(atPath: cacheURL.path()) else { return nil }
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let cached = try? decoder.decode(CachedTranscriptionPayload.self, from: data) else {
            return nil
        }

        guard cached.audioSHA256 == example.example.audio.sha256 else { return nil }
        return cached.transcription
    }

    private func makeFewShotExample(
        for section: TranscriptSectionMetrics,
        transcription: AudioTranscriptionResult
    ) -> AnalyzerConfig.ChunkedAnalyzer.FewShotExample? {
        guard let phase = section.phase else { return nil }

        let excerpt = transcription.segments
            .filter { segment in
                let segmentStart = segment.timestamp
                let segmentEnd = segment.timestamp + segment.duration
                return segmentEnd > section.startTime && segmentStart < section.endTime
            }
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard excerpt.count >= 60 else { return nil }

        let truncatedText: String
        if excerpt.count > 280 {
            let endIndex = excerpt.index(excerpt.startIndex, offsetBy: 280)
            truncatedText = String(excerpt[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            truncatedText = excerpt
        }

        let midpoint = (section.startTime + section.endTime) / 2.0
        let position = transcription.duration > 0 ? midpoint / transcription.duration : 0.5
        return AnalyzerConfig.ChunkedAnalyzer.FewShotExample(
            text: truncatedText,
            position: min(max(position, 0.0), 1.0),
            correctPhase: phase.rawValue
        )
    }

    private func makeFewShotExample(
        for scriptExample: ScriptPhaseExample
    ) -> AnalyzerConfig.ChunkedAnalyzer.FewShotExample? {
        let text = scriptExample.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 60 else { return nil }

        let truncatedText: String
        if text.count > 280 {
            let endIndex = text.index(text.startIndex, offsetBy: 280)
            truncatedText = String(text[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            truncatedText = text
        }

        return AnalyzerConfig.ChunkedAnalyzer.FewShotExample(
            text: truncatedText,
            position: defaultPosition(for: scriptExample.phase),
            correctPhase: scriptExample.phase.labelingPhase.rawValue,
            sourcePackID: scriptExample.sourcePackID
        )
    }

    private func defaultPosition(for phase: TrancePhase) -> Double {
        switch phase.labelingPhase {
        case .preTalk, .induction: return 0.18
        case .fractionation: return 0.34
        case .deepening: return 0.45
        case .confusion: return 0.56
        case .suggestions: return 0.68
        case .brainwashing: return 0.74
        case .emergence: return 0.92
        default: return 0.50
        }
    }

    private func scoreFewShotCandidate(section: TranscriptSectionMetrics) -> Double {
        let distinctiveBonus = section.topDistinctiveWords.prefix(4).reduce(0.0) { partial, statistic in
            partial + max(0.0, statistic.normalizedShareLift - 1.0)
        }
        let phraseBonus = section.topDistinctivePhrases.prefix(3).reduce(0.0) { partial, statistic in
            partial + max(0.0, statistic.normalizedShareLift - 1.0)
        }
        let durationBonus = min(section.duration / 90.0, 1.0)
        let repetitionBonus = min(section.normalizedRepetitionDensity, 2.0) * 0.25
        let waymarkerBonus = min(section.waymarkerMatches.reduce(0.0) { $0 + $1.score }, 2.0) * 0.35
        return distinctiveBonus + phraseBonus + durationBonus + repetitionBonus + waymarkerBonus
    }

    private func phraseCandidates(
        for section: TranscriptSectionMetrics,
        transcription: AudioTranscriptionResult
    ) -> [(String, Double)] {
        let excerpt = sectionExcerpt(for: section, transcription: transcription)
        let tokens = phraseTokens(in: excerpt)
        guard tokens.count >= 4 else { return [] }

        let distinctiveWords = Set(section.topDistinctiveWords.map(\.word))
        var phraseCounts: [String: Int] = [:]

        for phraseLength in 2...4 {
            guard tokens.count >= phraseLength else { continue }
            for startIndex in 0...(tokens.count - phraseLength) {
                let words = Array(tokens[startIndex..<(startIndex + phraseLength)])
                guard shouldLearnPhrase(words) else { continue }
                phraseCounts[words.joined(separator: " "), default: 0] += 1
            }
        }

        return phraseCounts.compactMap { phrase, count in
            let phraseWords = Set(phrase.split(separator: " ").map(String.init))
            let overlap = phraseWords.intersection(distinctiveWords).count
            guard count >= 2 || overlap >= 1 else { return nil }

            let score = Double(count) + (Double(overlap) * 0.75) + min(section.duration / 120.0, 1.0)
            guard score >= 1.6 else { return nil }
            return (phrase, score)
        }
        .sorted { lhs, rhs in
            if abs(lhs.1 - rhs.1) < 0.0001 { return lhs.0 < rhs.0 }
            return lhs.1 > rhs.1
        }
        .prefix(8)
        .map { $0 }
    }

    private func sectionExcerpt(
        for section: TranscriptSectionMetrics,
        transcription: AudioTranscriptionResult
    ) -> String {
        transcription.segments
            .filter { segment in
                let segmentStart = segment.timestamp
                let segmentEnd = segment.timestamp + segment.duration
                return segmentEnd > section.startTime && segmentStart < section.endTime
            }
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func phraseTokens(in text: String) -> [String] {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        let normalized = String(
            text
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .unicodeScalars
                .map { allowedCharacters.contains($0) ? Character($0) : " " }
        )

        return normalized
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: "'")).lowercased()
            }
            .filter { !$0.isEmpty }
    }

    private func shouldLearnPhrase(_ words: [String]) -> Bool {
        let stopWords: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "but", "by", "for", "from",
            "i", "if", "in", "into", "is", "it", "of", "on", "or", "so", "the",
            "to", "we", "with", "you", "your"
        ]

        let meaningfulWordCount = words.filter { !stopWords.contains($0) && $0.count >= 3 }.count
        guard meaningfulWordCount >= 1 else { return false }

        let ignoredPhrases = Set([
            "and you can",
            "and as you",
            "as you can",
            "you can feel"
        ])
        return !ignoredPhrases.contains(words.joined(separator: " "))
    }
}
