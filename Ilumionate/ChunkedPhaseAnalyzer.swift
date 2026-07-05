//
//  ChunkedPhaseAnalyzer.swift
//  Ilumionate
//
//  On-device AI-powered hypnosis phase detector using Apple's FoundationModels.
//  Processes transcripts in 15-second chunks with 5-second overlap, sending
//  position-aware prompts so the model can distinguish passive trance from
//  active suggestion delivery. Falls back gracefully — returns nil when Apple
//  Intelligence is unavailable, signalling the caller to use HypnosisPhaseAnalyzer
//  (keyword-based pipeline) instead.
//

import Foundation
import os
import FoundationModels

// MARK: - Structured Chunk Classification

@Generable(description: "Structured hypnosis phase classification for one transcript chunk.")
struct ChunkPhaseClassification {

    @Guide(description: """
        Best structural hypnosis phase for this transcript chunk.
        Fractionation and confusion are techniques, not phase labels; classify them as deepening.
        Therapeutic work, erotic suggestions, and post-hypnotic conditioning are suggestion-work labels.
        """)
    var phase: ChunkPhaseLabel

    @Guide(description: "Confidence in the selected phase.")
    var confidence: ChunkPhaseConfidence

    @Guide(description: "Brief evidence from the transcript supporting the selected phase.")
    var rationale: String

    var normalizedPhase: HypnosisMetadata.Phase {
        phase.normalizedPhase
    }
}

@Generable
enum ChunkPhaseLabel: String, Codable, Sendable {
    case preTalk = "pre_talk"
    case induction = "induction"
    case deepening = "deepening"
    case therapy = "therapy"
    case suggestions = "suggestions"
    case eroticSuggestions = "erotic_suggestions"
    case brainwashing = "brainwashing"
    case postHypnoticConditioning = "post_hypnotic_conditioning"
    case emergence = "emergence"

    var normalizedPhase: HypnosisMetadata.Phase {
        switch self {
        case .preTalk:
            return .preTalk.labelingPhase
        case .induction:
            return .induction
        case .deepening:
            return .deepening
        case .therapy:
            return .therapy.labelingPhase
        case .suggestions:
            return .suggestions
        case .eroticSuggestions:
            return .eroticSuggestions.labelingPhase
        case .brainwashing:
            return .brainwashing
        case .postHypnoticConditioning:
            return .conditioning.labelingPhase
        case .emergence:
            return .emergence
        }
    }
}

@Generable
enum ChunkPhaseConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

// MARK: - Analyzer

/// Foundation Models-backed hypnosis phase classifier.
nonisolated struct ChunkedPhaseAnalyzer {

    let config: AnalyzerConfig.ChunkedAnalyzer
    let corpusLearning: AnalyzerConfig.CorpusLearning

    init(
        config: AnalyzerConfig.ChunkedAnalyzer? = nil,
        corpusLearning: AnalyzerConfig.CorpusLearning? = nil
    ) {
        if let config {
            self.config = config
            self.corpusLearning = corpusLearning ?? .init()
        } else {
            let analyzerConfig = AnalyzerConfigLoader.load()
            self.config = analyzerConfig.chunkedAnalyzer
            self.corpusLearning = corpusLearning ?? analyzerConfig.corpusLearning
        }
    }

    // MARK: - Availability

    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Computes the target chunk count for a given recording duration.
    func chunkCount(for duration: Double) -> Int {
        let computed = Int(duration / 90.0)
        return max(config.minChunks, min(config.maxChunks, computed))
    }

    /// Static convenience — loads config from defaults. Used by legacy callers.
    static func chunkCount(for duration: Double) -> Int {
        ChunkedPhaseAnalyzer().chunkCount(for: duration)
    }

    // MARK: - Public Entry Point

    /// Analyzes word timestamps using the on-device language model.
    /// Returns `nil` when Apple Intelligence is unavailable or produces
    /// fewer than two distinct phases (triggering keyword-based fallback).
    func analyze(
        wordTimestamps: [WordTimestamp],
        duration: Double,
        onProgress: (@Sendable (Double) async -> Void)? = nil
    ) async -> [PhaseSegment]? {
        guard Self.isAvailable else { return nil }
        guard !wordTimestamps.isEmpty else { return nil }

        do {
            var timeline = try await classifyChunks(
                wordTimestamps: wordTimestamps,
                duration: duration,
                onProgress: onProgress
            )
            timeline = Self.collapseShortRuns(timeline, minRun: max(20, Int(duration * 0.035)))
            timeline = Self.enforcePhaseOrdering(timeline: timeline)
            let segments = Self.consolidatePhaseSegments(timeline: timeline, duration: duration)
            let distinctCount = Set(segments.map(\.phase)).count
            guard distinctCount >= 2 else {
                Log.analysis.info("⚠️ ChunkedPhaseAnalyzer: \(distinctCount) phase(s) detected — keyword fallback")
                return nil
            }
            return segments
        } catch {
            return nil
        }
    }

    /// Static convenience that creates a default-config instance.
    static func analyze(
        wordTimestamps: [WordTimestamp],
        duration: Double,
        onProgress: (@Sendable (Double) async -> Void)? = nil
    ) async -> [PhaseSegment]? {
        await ChunkedPhaseAnalyzer().analyze(
            wordTimestamps: wordTimestamps,
            duration: duration,
            onProgress: onProgress
        )
    }

    // MARK: - Internal Helpers (visible for unit tests)

    static func evenOddIndices(count: Int) -> (even: [Int], odd: [Int]) {
        let even = (0..<count).filter { $0.isMultiple(of: 2) }
        let odd  = (0..<count).filter { !$0.isMultiple(of: 2) }
        return (even, odd)
    }

    // MARK: - Supporting Types

    struct ChunkJob: Sendable {
        let index: Int
        let start: Double
        let end: Double
        let text: String
        let positionPct: Int
    }

    struct TimedClassification: Sendable, Equatable {
        let start: Double
        let end: Double
        let phase: HypnosisMetadata.Phase
    }

    struct ChunkRequest: Sendable {
        let text: String
        let startTime: Double
        let endTime: Double
        let sessionPositionPct: Int
        let totalDuration: Double
        let systemInstructions: String
        let corpusHints: String
        let fewShotExamples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample]
    }

    typealias ChunkClassifier = @Sendable (
        ChunkRequest,
        HypnosisMetadata.Phase?,
        SystemLanguageModel
    ) async throws -> [TimedClassification]
}

// MARK: - Classification Pipeline

extension ChunkedPhaseAnalyzer {

    func classifyChunks(
        wordTimestamps: [WordTimestamp],
        duration: Double,
        onProgress: (@Sendable (Double) async -> Void)?
    ) async throws -> [HypnosisMetadata.Phase?] {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let jobs = buildJobs(from: wordTimestamps, duration: duration)
        let (evenIdxs, oddIdxs) = Self.evenOddIndices(count: jobs.count)
        var results = [HypnosisMetadata.Phase?](repeating: nil, count: jobs.count)
        var classificationsByJob = [[TimedClassification]](repeating: [], count: jobs.count)
        var completedJobCount = 0
        let totalJobCount = max(1, jobs.count)

        func reportCompletedJob() async {
            completedJobCount += 1
            await onProgress?(Double(completedJobCount) / Double(totalJobCount))
        }

        try Task.checkCancellation()
        let knowledge = CorpusPhaseKnowledgeCache.shared.knowledge()
        let instructions = effectiveSystemInstructions(knowledge: knowledge)
        let fewShotSeedExamples = deduplicatedFewShotExamples(from: config.fewShotExamples + knowledge.fewShotExamples)
        let evenPairs = try await Self.runPass(
            jobs: evenIdxs.map { jobs[$0] }, previousResults: nil,
            totalDuration: duration, model: model, systemInstructions: instructions,
            knowledge: knowledge, corpusLearning: corpusLearning,
            fewShotSeedExamples: fewShotSeedExamples,
            maxConcurrentRequests: config.maxConcurrentRequests,
            onCompletedJob: reportCompletedJob
        )
        for (idx, classifications) in evenPairs {
            classificationsByJob[idx] = classifications
            results[idx] = classifications.last?.phase
        }
        try Task.checkCancellation()

        let oddPairs = try await Self.runPass(
            jobs: oddIdxs.map { jobs[$0] }, previousResults: results,
            totalDuration: duration, model: model, systemInstructions: instructions,
            knowledge: knowledge, corpusLearning: corpusLearning,
            fewShotSeedExamples: fewShotSeedExamples,
            maxConcurrentRequests: config.maxConcurrentRequests,
            onCompletedJob: reportCompletedJob
        )
        for (idx, classifications) in oddPairs {
            classificationsByJob[idx] = classifications
            results[idx] = classifications.last?.phase
        }
        if jobs.isEmpty {
            await onProgress?(1.0)
        }
        try Task.checkCancellation()

        return Self.assembleTimeline(
            bucketCount: max(1, Int(ceil(duration))),
            classifications: classificationsByJob.flatMap { $0 }
        )
    }

    func buildJobs(from wordTimestamps: [WordTimestamp], duration: Double) -> [ChunkJob] {
        let cap = chunkCount(for: duration)
        let chunkDur = config.chunkDurationSeconds
        let chunkOvlp = config.chunkOverlapSeconds
        let allStarts = stride(from: 0.0, to: duration, by: chunkDur).map { $0 }
        let selectedStarts: [Double] = allStarts.count <= cap
            ? allStarts
            : (0..<cap).map { allStarts[Int(Double($0) * Double(allStarts.count) / Double(cap))] }

        return selectedStarts.enumerated().map { chunkIdx, chunkStart in
            let chunkEnd = min(chunkStart + chunkDur, duration)
            let overlapStart = max(0, chunkStart - chunkOvlp)
            let words = wordTimestamps.filter { $0.startTime >= overlapStart && $0.startTime < chunkEnd }
            let positionPct = Int(((chunkStart + chunkEnd) / 2.0 / duration) * 100.0)
            return ChunkJob(index: chunkIdx, start: chunkStart, end: chunkEnd,
                            text: words.map(\.word).joined(separator: " "), positionPct: positionPct)
        }
    }

    func effectiveSystemInstructions(
        knowledge: CorpusPhaseKnowledge = CorpusPhaseKnowledgeCache.shared.knowledge()
    ) -> String {
        let corpusCalibrationGuide = buildCorpusCalibrationGuide(from: knowledge)
        guard !corpusCalibrationGuide.isEmpty else { return config.systemInstructions }

        return """
            \(config.systemInstructions)

            Use the learned corpus calibration below to prefer functional hypnosis structure over generic language similarity.

            \(corpusCalibrationGuide)
            """
    }

    func deduplicatedFewShotExamples(
        from examples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample]
    ) -> [AnalyzerConfig.ChunkedAnalyzer.FewShotExample] {
        var seenKeys = Set<String>()
        var deduplicated: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample] = []

        for example in examples {
            let compactText = example.text
                .lowercased()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = compactText.prefix(80)
            let key = "\(example.correctPhase)|\(preview)"
            guard seenKeys.insert(key).inserted else { continue }
            deduplicated.append(example)
        }

        return deduplicated.sorted { lhs, rhs in
            if abs(lhs.position - rhs.position) < 0.0001 {
                return lhs.correctPhase < rhs.correctPhase
            }
            return lhs.position < rhs.position
        }
    }

    func buildCorpusCalibrationGuide(from knowledge: CorpusPhaseKnowledge) -> String {
        let phaseLines = HypnosisMetadata.Phase.orderedHypnosisPhases.compactMap { phase -> String? in
            let wordCues = Self.topLearnedWords(
                for: phase,
                knowledge: knowledge,
                corpusLearning: corpusLearning,
                limit: 3
            )
            let phraseCues = Self.topLearnedPhrases(
                for: phase,
                knowledge: knowledge,
                corpusLearning: corpusLearning,
                limit: 2
            )
            guard !wordCues.isEmpty || !phraseCues.isEmpty else { return nil }

            let wordText = wordCues.isEmpty ? nil : "words: \(wordCues.joined(separator: ", "))"
            let phraseText = phraseCues.isEmpty ? nil : "phrases: \(phraseCues.joined(separator: " | "))"
            let cueText = [wordText, phraseText].compactMap { $0 }.joined(separator: "; ")
            return "- \(phase.rawValue): \(cueText)"
        }

        guard !phaseLines.isEmpty else { return "" }
        return """
            Corpus calibration cues:
            \(phaseLines.joined(separator: "\n"))
            """
    }

    nonisolated static func contextualPromptHints(
        positionPct: Int,
        previousPhase: HypnosisMetadata.Phase?,
        knowledge: CorpusPhaseKnowledge,
        corpusLearning: AnalyzerConfig.CorpusLearning = .init()
    ) -> String {
        let candidatePhases = likelyCandidatePhases(
            positionPct: positionPct,
            previousPhase: previousPhase,
            knowledge: knowledge
        )

        guard !candidatePhases.isEmpty else { return "" }

        let lines = candidatePhases.prefix(4).map { phase in
            let words = topLearnedWords(
                for: phase,
                knowledge: knowledge,
                corpusLearning: corpusLearning,
                limit: 3
            )
            let phrases = topLearnedPhrases(
                for: phase,
                knowledge: knowledge,
                corpusLearning: corpusLearning,
                limit: 2
            )
            let cueParts = [
                words.isEmpty ? nil : "words: \(words.joined(separator: ", "))",
                phrases.isEmpty ? nil : "phrases: \(phrases.joined(separator: " | "))"
            ].compactMap { $0 }

            if cueParts.isEmpty {
                return "- \(phase.rawValue)"
            }
            return "- \(phase.rawValue): \(cueParts.joined(separator: "; "))"
        }

        let transitionNote: String
        if let previousPhase {
            transitionNote = "Previous phase context: \(previousPhase.rawValue). Favor plausible forward movement unless the text clearly contradicts it."
        } else {
            transitionNote = "No previous phase is known. Use session position and transcript function to choose the best phase."
        }

        return """
            Candidate phases for this chunk:
            \(lines.joined(separator: "\n"))
            \(transitionNote)
            """
    }

    nonisolated static func contextualFewShotExamples(
        positionPct: Int,
        previousPhase: HypnosisMetadata.Phase?,
        knowledge: CorpusPhaseKnowledge,
        corpusLearning: AnalyzerConfig.CorpusLearning = .init(),
        baseExamples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample]
    ) -> [AnalyzerConfig.ChunkedAnalyzer.FewShotExample] {
        guard !baseExamples.isEmpty else { return [] }

        let targetPosition = Double(positionPct) / 100.0
        let likelyPhases = Set(likelyCandidatePhases(
            positionPct: positionPct,
            previousPhase: previousPhase,
            knowledge: knowledge
        ))

        return baseExamples
            .filter { example in
                sourceMultiplier(
                    for: example,
                    corpusLearning: corpusLearning
                ) > 0
            }
            .sorted { lhs, rhs in
                contextualFewShotScore(
                    example: lhs,
                    targetPosition: targetPosition,
                    previousPhase: previousPhase,
                    likelyPhases: likelyPhases,
                    knowledge: knowledge,
                    corpusLearning: corpusLearning
                ) > contextualFewShotScore(
                    example: rhs,
                    targetPosition: targetPosition,
                    previousPhase: previousPhase,
                    likelyPhases: likelyPhases,
                    knowledge: knowledge,
                    corpusLearning: corpusLearning
                )
            }
            .prefix(4)
            .map { $0 }
    }

    nonisolated static func renderFewShotExamples(
        _ examples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample]
    ) -> String {
        guard !examples.isEmpty else { return "" }

        let rendered = examples.enumerated().map { index, example in
            let positionPercent = Int((min(max(example.position, 0.0), 1.0) * 100.0).rounded())
            let normalizedText = example.text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return """
                Example \(index + 1) (\(positionPercent)%):
                Transcript: "\(normalizedText)"
                Correct phase: \(example.correctPhase)
                """
        }.joined(separator: "\n\n")

        return """
            Calibration examples for nearby chunks:

            \(rendered)
            """
    }

    nonisolated static func likelyCandidatePhases(
        positionPct: Int,
        previousPhase: HypnosisMetadata.Phase?,
        knowledge: CorpusPhaseKnowledge
    ) -> [HypnosisMetadata.Phase] {
        var ranked: [HypnosisMetadata.Phase: Double] = [:]

        for phase in positionAnchoredPhases(for: positionPct) {
            ranked[phase, default: 0.0] += 1.0
        }

        if let previousPhase {
            ranked[previousPhase, default: 0.0] += 0.25
            if let nextPhase = nextOrderedPhase(after: previousPhase) {
                ranked[nextPhase, default: 0.0] += 0.35
            }

            for (candidate, prior) in (knowledge.transitionPriors[previousPhase] ?? [:]) where prior > 0 {
                ranked[candidate, default: 0.0] += prior * 1.4
            }
        }

        return ranked
            .sorted(by: { lhs, rhs in
                if abs(lhs.value - rhs.value) < 0.0001 {
                    return phaseOrderIndex(lhs.key) < phaseOrderIndex(rhs.key)
                }
                return lhs.value > rhs.value
            })
            .map(\.key)
    }

    nonisolated static func positionAnchoredPhases(for positionPct: Int) -> [HypnosisMetadata.Phase] {
        switch positionPct {
        case 0..<8:
            return [.induction]
        case 8..<35:
            return [.induction, .deepening]
        case 35..<65:
            return [.deepening, .suggestions]
        case 65..<82:
            return [.suggestions, .brainwashing]
        case 82..<90:
            return [.brainwashing, .emergence]
        default:
            return [.emergence]
        }
    }

    nonisolated static func topLearnedWords(
        for phase: HypnosisMetadata.Phase,
        knowledge: CorpusPhaseKnowledge,
        corpusLearning: AnalyzerConfig.CorpusLearning = .init(),
        limit: Int
    ) -> [String] {
        func weightedValue(_ entry: (key: String, value: Double)) -> Double {
            entry.value * corpusLearning.sourceMultiplier(
                for: knowledge.keywordSourcePacks[phase]?[entry.key] ?? Set<String>(),
                phase: phase
            )
        }

        return Array((knowledge.keywordWeights[phase] ?? [:])
            .filter { word, _ in
                corpusLearning.sourceMultiplier(
                    for: knowledge.keywordSourcePacks[phase]?[word] ?? Set<String>(),
                    phase: phase
                ) > 0
            }
            .sorted { lhs, rhs in
                let lhsValue = weightedValue(lhs)
                let rhsValue = weightedValue(rhs)
                if abs(lhsValue - rhsValue) < 0.0001 { return lhs.key < rhs.key }
                return lhsValue > rhsValue
            }
            .prefix(limit)
            .map(\.key))
    }

    nonisolated static func topLearnedPhrases(
        for phase: HypnosisMetadata.Phase,
        knowledge: CorpusPhaseKnowledge,
        corpusLearning: AnalyzerConfig.CorpusLearning = .init(),
        limit: Int
    ) -> [String] {
        func weightedValue(_ entry: (key: String, value: Double)) -> Double {
            entry.value * corpusLearning.sourceMultiplier(
                for: knowledge.phraseSourcePacks[phase]?[entry.key] ?? Set<String>(),
                phase: phase
            )
        }

        return Array((knowledge.phraseWeights[phase] ?? [:])
            .filter { phrase, _ in
                corpusLearning.sourceMultiplier(
                    for: knowledge.phraseSourcePacks[phase]?[phrase] ?? Set<String>(),
                    phase: phase
                ) > 0
            }
            .sorted { lhs, rhs in
                let lhsValue = weightedValue(lhs)
                let rhsValue = weightedValue(rhs)
                if abs(lhsValue - rhsValue) < 0.0001 { return lhs.key < rhs.key }
                return lhsValue > rhsValue
            }
            .prefix(limit)
            .map(\.key))
    }

    nonisolated static func contextualFewShotScore(
        example: AnalyzerConfig.ChunkedAnalyzer.FewShotExample,
        targetPosition: Double,
        previousPhase: HypnosisMetadata.Phase?,
        likelyPhases: Set<HypnosisMetadata.Phase>,
        knowledge: CorpusPhaseKnowledge,
        corpusLearning: AnalyzerConfig.CorpusLearning = .init()
    ) -> Double {
        let positionPenalty = abs(example.position - targetPosition)
        let phase = HypnosisMetadata.Phase(rawValue: example.correctPhase)
        let likelyBonus = phase.map { likelyPhases.contains($0) ? 0.8 : 0.0 } ?? 0.0
        let transitionBonus: Double
        if let previousPhase, let phase {
            transitionBonus = (knowledge.transitionPriors[previousPhase]?[phase] ?? 0.0) * 1.2
        } else {
            transitionBonus = 0.0
        }

        let baseScore = likelyBonus + transitionBonus - positionPenalty * 1.8
        return baseScore * sourceMultiplier(for: example, corpusLearning: corpusLearning)
    }

    nonisolated static func sourceMultiplier(
        for example: AnalyzerConfig.ChunkedAnalyzer.FewShotExample,
        corpusLearning: AnalyzerConfig.CorpusLearning
    ) -> Double {
        let phase = HypnosisMetadata.Phase(rawValue: example.correctPhase) ?? .suggestions
        let sourcePackIDs = example.sourcePackID.map { Set([$0]) } ?? Set<String>()
        return corpusLearning.sourceMultiplier(for: sourcePackIDs, phase: phase)
    }

    nonisolated static func nextOrderedPhase(after phase: HypnosisMetadata.Phase) -> HypnosisMetadata.Phase? {
        let phases = HypnosisMetadata.Phase.orderedHypnosisPhases
        guard let index = phases.firstIndex(of: phase), index < phases.count - 1 else { return nil }
        return phases[index + 1]
    }

    nonisolated static func phaseOrderIndex(_ phase: HypnosisMetadata.Phase) -> Int {
        HypnosisMetadata.Phase.orderedHypnosisPhases.firstIndex(of: phase) ?? .max
    }

    nonisolated static func runPass(
        jobs: [ChunkJob],
        previousResults: [HypnosisMetadata.Phase?]?,
        totalDuration: Double,
        model: SystemLanguageModel,
        systemInstructions: String,
        knowledge: CorpusPhaseKnowledge,
        corpusLearning: AnalyzerConfig.CorpusLearning = .init(),
        fewShotSeedExamples: [AnalyzerConfig.ChunkedAnalyzer.FewShotExample],
        maxConcurrentRequests: Int = 2,
        onCompletedJob: (() async -> Void)? = nil,
        classify: @escaping ChunkClassifier = { request, previousPhase, model in
            try await Self.classifySingleChunk(
                request: request,
                previousPhase: previousPhase,
                model: model
            )
        }
    ) async throws -> [(Int, [TimedClassification])] {
        try await withThrowingTaskGroup(of: (Int, [TimedClassification]).self) { group in
            var nextJobIndex = 0
            let requestLimit = max(1, min(maxConcurrentRequests, jobs.count))

            func enqueueNextJob() {
                guard nextJobIndex < jobs.count else { return }
                let job = jobs[nextJobIndex]
                nextJobIndex += 1
                let prev = job.index > 0 ? previousResults?[job.index - 1] ?? nil : nil
                group.addTask {
                    try Task.checkCancellation()
                    if job.text.trimmingCharacters(in: .whitespaces).isEmpty {
                        let classifications = prev.map {
                            [TimedClassification(start: job.start, end: job.end, phase: $0)]
                        } ?? []
                        return (job.index, classifications)
                    }
                    let request = ChunkRequest(
                        text: job.text, startTime: job.start, endTime: job.end,
                        sessionPositionPct: job.positionPct, totalDuration: totalDuration,
                        systemInstructions: systemInstructions,
                        corpusHints: Self.contextualPromptHints(
                            positionPct: job.positionPct,
                            previousPhase: prev,
                            knowledge: knowledge,
                            corpusLearning: corpusLearning
                        ),
                        fewShotExamples: Self.contextualFewShotExamples(
                            positionPct: job.positionPct,
                            previousPhase: prev,
                            knowledge: knowledge,
                            corpusLearning: corpusLearning,
                            baseExamples: fewShotSeedExamples
                        )
                    )
                    let classifications = try await Self.classifySingleChunk(
                        request: request,
                        previousPhase: prev,
                        model: model
                    )
                    return (job.index, classifications)
                }
            }

            for _ in 0..<requestLimit {
                enqueueNextJob()
            }

            var pairs: [(Int, [TimedClassification])] = []
            while let pair = try await group.next() {
                pairs.append(pair)
                if let onCompletedJob {
                    await onCompletedJob()
                }
                enqueueNextJob()
            }
            return pairs
        }
    }

    static func assembleTimeline(
        bucketCount: Int,
        classifications: [TimedClassification]
    ) -> [HypnosisMetadata.Phase?] {
        var timeline = [HypnosisMetadata.Phase?](repeating: nil, count: bucketCount)
        for classification in classifications {
            let start = max(0, min(Int(classification.start), bucketCount - 1))
            let end = max(0, min(Int(ceil(classification.end)), bucketCount))
            guard start < end else { continue }
            for idx in start..<end { timeline[idx] = classification.phase }
        }
        return timeline
    }

    /// Classifies a single chunk; splits in half recursively on context-window overflow.
    static func classifySingleChunk(
        request: ChunkRequest,
        previousPhase: HypnosisMetadata.Phase?,
        model: SystemLanguageModel
    ) async throws -> [TimedClassification] {
        try Task.checkCancellation()
        let positionHint = buildPositionHint(pct: request.sessionPositionPct)
        let previousHint = previousPhase.map { "The previous segment was: \($0.rawValue)." } ?? ""
        let fewShotText = renderFewShotExamples(request.fewShotExamples)
        let prompt = """
            \(positionHint)
            \(previousHint)
            \(request.corpusHints)
            \(fewShotText)

            Transcript segment (\(Int(request.startTime))s–\(Int(request.endTime))s \
            of \(Int(request.totalDuration))s total):
            "\(request.text)"

            Classify this transcript segment into the single best structural hypnosis phase.
            """
        let session = LanguageModelSession(model: model, instructions: request.systemInstructions)
        do {
            let response = try await session.respond(to: prompt, generating: ChunkPhaseClassification.self)
            return [
                TimedClassification(
                    start: request.startTime,
                    end: request.endTime,
                    phase: response.content.normalizedPhase
                )
            ]
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            return try await splitAndClassify(request: request, previousPhase: previousPhase, model: model)
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            return previousPhase.map {
                [TimedClassification(start: request.startTime, end: request.endTime, phase: $0)]
            } ?? []
        } catch LanguageModelSession.GenerationError.refusal {
            return previousPhase.map {
                [TimedClassification(start: request.startTime, end: request.endTime, phase: $0)]
            } ?? []
        }
    }

    static func splitAndClassify(
        request: ChunkRequest,
        previousPhase: HypnosisMetadata.Phase?,
        model: SystemLanguageModel
    ) async throws -> [TimedClassification] {
        let midTime = (request.startTime + request.endTime) / 2.0
        let words = request.text.components(separatedBy: " ")
        guard words.count >= 2, request.endTime - request.startTime >= 1 else {
            return previousPhase.map {
                [TimedClassification(start: request.startTime, end: request.endTime, phase: $0)]
            } ?? []
        }
        let midIdx = words.count / 2
        let midPct = Int((midTime / request.totalDuration) * 100.0)
        let first = ChunkRequest(
            text: words.prefix(midIdx).joined(separator: " "),
            startTime: request.startTime, endTime: midTime,
            sessionPositionPct: request.sessionPositionPct, totalDuration: request.totalDuration,
            systemInstructions: request.systemInstructions,
            corpusHints: request.corpusHints,
            fewShotExamples: request.fewShotExamples
        )
        let second = ChunkRequest(
            text: words.dropFirst(midIdx).joined(separator: " "),
            startTime: midTime, endTime: request.endTime,
            sessionPositionPct: midPct, totalDuration: request.totalDuration,
            systemInstructions: request.systemInstructions,
            corpusHints: request.corpusHints,
            fewShotExamples: request.fewShotExamples
        )
        let firstResults = try await classifySingleChunk(
            request: first,
            previousPhase: previousPhase,
            model: model
        )
        try Task.checkCancellation()
        let secondResults = try await classifySingleChunk(
            request: second,
            previousPhase: firstResults.last?.phase ?? previousPhase,
            model: model
        )
        return firstResults + secondResults
    }
}

// MARK: - Position Hints & Response Parsing

private extension ChunkedPhaseAnalyzer {

    static func buildPositionHint(pct: Int) -> String {
        switch pct {
        case 0..<8:
            return "This is the BEGINNING of the session (\(pct)%). Expect orientation-style induction."
        case 8..<20:
            return "This is early in the session (\(pct)%). Likely induction or early deepening; fractionation is a technique, not a phase."
        case 20..<40:
            return "This is the early-middle (\(pct)%). Likely deepening; fractionation and confusion are techniques inside the structural phase."
        case 40..<60:
            return "This is the middle (\(pct)%). Likely deepening or suggestions; confusion language is a technique, not its own phase."
        case 60..<78:
            return "This is the later-middle (\(pct)%). Likely suggestions, erotic_suggestions, or brainwashing if repetitive indoctrination language appears."
        case 75..<88:
            return "This is LATE (\(pct)%). Watch for brainwashing, post_hypnotic_conditioning, or early emergence."
        case 88..<95:
            return "This is NEAR THE END (\(pct)%). Very likely emergence."
        default:
            return "This is the FINAL PART (\(pct)%). Expect emergence — waking, re-orientation."
        }
    }

}
