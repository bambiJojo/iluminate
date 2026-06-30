//
//  TranscriptModels.swift
//  Ilumionate
//
//  Extracted from HypnosisPhaseAnalyzer.swift (structural decomposition).
//

import Foundation

// MARK: - Transcript Feature Analysis

/// File-relative transcript analytics used for normalized section scoring.
nonisolated struct TranscriptAnalysis: Codable, Sendable {
    let overall: TranscriptSectionMetrics
    let sections: [TranscriptSectionMetrics]
    let timelineWindows: [TranscriptSectionMetrics]

    private enum CodingKeys: String, CodingKey {
        case overall
        case sections
        case timelineWindows
    }

    init(
        overall: TranscriptSectionMetrics,
        sections: [TranscriptSectionMetrics],
        timelineWindows: [TranscriptSectionMetrics]
    ) {
        self.overall = overall
        self.sections = sections
        self.timelineWindows = timelineWindows
    }

    init(
        overall: TranscriptSectionMetrics,
        sections: [TranscriptSectionMetrics]
    ) {
        self.init(overall: overall, sections: sections, timelineWindows: sections)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overall = try container.decode(TranscriptSectionMetrics.self, forKey: .overall)
        sections = try container.decode([TranscriptSectionMetrics].self, forKey: .sections)
        timelineWindows = try container.decodeIfPresent([TranscriptSectionMetrics].self, forKey: .timelineWindows) ?? sections
    }

    func section(at time: TimeInterval) -> TranscriptSectionMetrics? {
        if let containing = sections.first(where: { time >= $0.startTime && time <= $0.endTime }) {
            return containing
        }
        return sections.min { $0.distance(to: time) < $1.distance(to: time) }
    }

    func timelineWindow(at time: TimeInterval) -> TranscriptSectionMetrics? {
        if let containing = timelineWindows.first(where: { time >= $0.startTime && time <= $0.endTime }) {
            return containing
        }
        return timelineWindows.min { $0.distance(to: time) < $1.distance(to: time) }
    }
}

nonisolated struct TranscriptSectionMetrics: Codable, Identifiable, Sendable {
    let id: UUID
    let phase: HypnosisMetadata.Phase?
    let startTime: TimeInterval
    let endTime: TimeInterval
    let duration: TimeInterval
    let wordCount: Int
    let uniqueWordCount: Int
    let wordsPerMinute: Double
    let normalizedWordsPerMinute: Double
    let speechCoverage: Double
    let normalizedSpeechCoverage: Double
    let lexicalDiversity: Double
    let normalizedLexicalDiversity: Double
    let repetitionDensity: Double
    let normalizedRepetitionDensity: Double
    let topWords: [TranscriptWordStatistic]
    let topDistinctiveWords: [TranscriptWordStatistic]
    let topPhrases: [TranscriptPhraseStatistic]
    let topDistinctivePhrases: [TranscriptPhraseStatistic]
    let waymarkerMatches: [HypnosisWaymarkerMatch]

    private enum CodingKeys: String, CodingKey {
        case id
        case phase
        case startTime
        case endTime
        case duration
        case wordCount
        case uniqueWordCount
        case wordsPerMinute
        case normalizedWordsPerMinute
        case speechCoverage
        case normalizedSpeechCoverage
        case lexicalDiversity
        case normalizedLexicalDiversity
        case repetitionDensity
        case normalizedRepetitionDensity
        case topWords
        case topDistinctiveWords
        case topPhrases
        case topDistinctivePhrases
        case waymarkerMatches
    }

    init(
        id: UUID,
        phase: HypnosisMetadata.Phase?,
        startTime: TimeInterval,
        endTime: TimeInterval,
        duration: TimeInterval,
        wordCount: Int,
        uniqueWordCount: Int,
        wordsPerMinute: Double,
        normalizedWordsPerMinute: Double,
        speechCoverage: Double,
        normalizedSpeechCoverage: Double,
        lexicalDiversity: Double,
        normalizedLexicalDiversity: Double,
        repetitionDensity: Double,
        normalizedRepetitionDensity: Double,
        topWords: [TranscriptWordStatistic],
        topDistinctiveWords: [TranscriptWordStatistic],
        topPhrases: [TranscriptPhraseStatistic] = [],
        topDistinctivePhrases: [TranscriptPhraseStatistic] = [],
        waymarkerMatches: [HypnosisWaymarkerMatch] = []
    ) {
        self.id = id
        self.phase = phase
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.wordCount = wordCount
        self.uniqueWordCount = uniqueWordCount
        self.wordsPerMinute = wordsPerMinute
        self.normalizedWordsPerMinute = normalizedWordsPerMinute
        self.speechCoverage = speechCoverage
        self.normalizedSpeechCoverage = normalizedSpeechCoverage
        self.lexicalDiversity = lexicalDiversity
        self.normalizedLexicalDiversity = normalizedLexicalDiversity
        self.repetitionDensity = repetitionDensity
        self.normalizedRepetitionDensity = normalizedRepetitionDensity
        self.topWords = topWords
        self.topDistinctiveWords = topDistinctiveWords
        self.topPhrases = topPhrases
        self.topDistinctivePhrases = topDistinctivePhrases
        self.waymarkerMatches = waymarkerMatches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        phase = try container.decodeIfPresent(HypnosisMetadata.Phase.self, forKey: .phase)
        startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        uniqueWordCount = try container.decode(Int.self, forKey: .uniqueWordCount)
        wordsPerMinute = try container.decode(Double.self, forKey: .wordsPerMinute)
        normalizedWordsPerMinute = try container.decode(Double.self, forKey: .normalizedWordsPerMinute)
        speechCoverage = try container.decode(Double.self, forKey: .speechCoverage)
        normalizedSpeechCoverage = try container.decode(Double.self, forKey: .normalizedSpeechCoverage)
        lexicalDiversity = try container.decode(Double.self, forKey: .lexicalDiversity)
        normalizedLexicalDiversity = try container.decode(Double.self, forKey: .normalizedLexicalDiversity)
        repetitionDensity = try container.decode(Double.self, forKey: .repetitionDensity)
        normalizedRepetitionDensity = try container.decode(Double.self, forKey: .normalizedRepetitionDensity)
        topWords = try container.decode([TranscriptWordStatistic].self, forKey: .topWords)
        topDistinctiveWords = try container.decode([TranscriptWordStatistic].self, forKey: .topDistinctiveWords)
        topPhrases = try container.decodeIfPresent([TranscriptPhraseStatistic].self, forKey: .topPhrases) ?? []
        topDistinctivePhrases = try container.decodeIfPresent([TranscriptPhraseStatistic].self, forKey: .topDistinctivePhrases) ?? []
        waymarkerMatches = try container.decodeIfPresent([HypnosisWaymarkerMatch].self, forKey: .waymarkerMatches) ?? []
    }

    var normalizedLexicalTightness: Double {
        guard normalizedLexicalDiversity > 0 else { return 1.0 }
        return 1.0 / normalizedLexicalDiversity
    }

    func distance(to time: TimeInterval) -> TimeInterval {
        if time < startTime { return startTime - time }
        if time > endTime { return time - endTime }
        return 0
    }
}

nonisolated struct TranscriptWordStatistic: Codable, Sendable {
    let word: String
    let count: Int
    let share: Double
    let normalizedShareLift: Double
}

nonisolated struct TranscriptPhraseStatistic: Codable, Sendable {
    let phrase: String
    let count: Int
    let share: Double
    let normalizedShareLift: Double
}

nonisolated struct HypnosisWaymarkerMatch: Codable, Identifiable, Sendable {
    let id: UUID
    let phrase: String
    let phase: HypnosisMetadata.Phase
    let count: Int
    let score: Double

    init(
        id: UUID = UUID(),
        phrase: String,
        phase: HypnosisMetadata.Phase,
        count: Int,
        score: Double
    ) {
        self.id = id
        self.phrase = phrase
        self.phase = phase
        self.count = count
        self.score = score
    }
}

nonisolated enum HypnosisPhraseEvidenceOrigin: String, Codable, Sendable {
    case curated
    case corpus
    case blended
}

nonisolated struct HypnosisPhraseAssociation: Identifiable, Codable, Sendable {
    var id: String { "\(phase.rawValue)|\(phrase)" }

    let phrase: String
    let phase: HypnosisMetadata.Phase
    let weight: Double
    let origin: HypnosisPhraseEvidenceOrigin
    let sourceLabel: String?
    let sourceURL: String?
    let sourcePackIDs: [String]
    let corpusSupport: Double
    let sectionCount: Int
    let exampleCount: Int

    init(
        phrase: String,
        phase: HypnosisMetadata.Phase,
        weight: Double,
        origin: HypnosisPhraseEvidenceOrigin,
        sourceLabel: String?,
        sourceURL: String?,
        sourcePackIDs: [String] = [],
        corpusSupport: Double,
        sectionCount: Int,
        exampleCount: Int
    ) {
        self.phrase = phrase
        self.phase = phase
        self.weight = weight
        self.origin = origin
        self.sourceLabel = sourceLabel
        self.sourceURL = sourceURL
        self.sourcePackIDs = sourcePackIDs
        self.corpusSupport = corpusSupport
        self.sectionCount = sectionCount
        self.exampleCount = exampleCount
    }

    private enum CodingKeys: String, CodingKey {
        case phrase
        case phase
        case weight
        case origin
        case sourceLabel
        case sourceURL
        case sourcePackIDs
        case corpusSupport
        case sectionCount
        case exampleCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phrase = try container.decode(String.self, forKey: .phrase)
        phase = try container.decode(HypnosisMetadata.Phase.self, forKey: .phase)
        weight = try container.decode(Double.self, forKey: .weight)
        origin = try container.decode(HypnosisPhraseEvidenceOrigin.self, forKey: .origin)
        sourceLabel = try container.decodeIfPresent(String.self, forKey: .sourceLabel)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        sourcePackIDs = try container.decodeIfPresent([String].self, forKey: .sourcePackIDs) ?? []
        corpusSupport = try container.decode(Double.self, forKey: .corpusSupport)
        sectionCount = try container.decode(Int.self, forKey: .sectionCount)
        exampleCount = try container.decode(Int.self, forKey: .exampleCount)
    }
}
