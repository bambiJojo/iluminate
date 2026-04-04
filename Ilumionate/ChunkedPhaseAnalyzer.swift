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
import FoundationModels

// MARK: - Analyzer

/// Foundation Models-backed hypnosis phase classifier.
struct ChunkedPhaseAnalyzer {

    let config: AnalyzerConfig.ChunkedAnalyzer

    init(config: AnalyzerConfig.ChunkedAnalyzer? = nil) {
        self.config = config ?? AnalyzerConfigLoader.load().chunkedAnalyzer
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
            timeline = Self.enforcePhaseOrdering(timeline: timeline)
            timeline = Self.collapseShortRuns(timeline, minRun: max(20, Int(duration * 0.035)))
            let segments = Self.consolidatePhaseSegments(timeline: timeline, duration: duration)
            let distinctCount = Set(segments.map(\.phase)).count
            guard distinctCount >= 2 else {
                print("⚠️ ChunkedPhaseAnalyzer: \(distinctCount) phase(s) detected — keyword fallback")
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

    struct ChunkRequest: Sendable {
        let text: String
        let startTime: Double
        let endTime: Double
        let sessionPositionPct: Int
        let totalDuration: Double
        let systemInstructions: String
    }
}

// MARK: - Classification Pipeline

private extension ChunkedPhaseAnalyzer {

    func classifyChunks(
        wordTimestamps: [WordTimestamp],
        duration: Double,
        onProgress: (@Sendable (Double) async -> Void)?
    ) async throws -> [HypnosisMetadata.Phase?] {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let jobs = buildJobs(from: wordTimestamps, duration: duration)
        let (evenIdxs, oddIdxs) = Self.evenOddIndices(count: jobs.count)
        var results = [HypnosisMetadata.Phase?](repeating: nil, count: jobs.count)

        let instructions = config.systemInstructions
        let evenPairs = try await Self.runPass(
            jobs: evenIdxs.map { jobs[$0] }, previousResults: nil,
            totalDuration: duration, model: model, systemInstructions: instructions
        )
        for (idx, phase) in evenPairs { results[idx] = phase }
        await onProgress?(0.5)

        let oddPairs = try await Self.runPass(
            jobs: oddIdxs.map { jobs[$0] }, previousResults: results,
            totalDuration: duration, model: model, systemInstructions: instructions
        )
        for (idx, phase) in oddPairs { results[idx] = phase }
        await onProgress?(1.0)

        return Self.assembleTimeline(bucketCount: max(1, Int(ceil(duration))), jobs: jobs, results: results)
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

    static func runPass(
        jobs: [ChunkJob],
        previousResults: [HypnosisMetadata.Phase?]?,
        totalDuration: Double,
        model: SystemLanguageModel,
        systemInstructions: String
    ) async throws -> [(Int, HypnosisMetadata.Phase?)] {
        try await withThrowingTaskGroup(of: (Int, HypnosisMetadata.Phase?).self) { group in
            for job in jobs {
                let prev = job.index > 0 ? previousResults?[job.index - 1] ?? nil : nil
                group.addTask {
                    if job.text.trimmingCharacters(in: .whitespaces).isEmpty { return (job.index, prev) }
                    let request = ChunkRequest(
                        text: job.text, startTime: job.start, endTime: job.end,
                        sessionPositionPct: job.positionPct, totalDuration: totalDuration,
                        systemInstructions: systemInstructions
                    )
                    let phase = try await classifySingleChunk(request: request, previousPhase: prev, model: model)
                    return (job.index, phase)
                }
            }
            var pairs: [(Int, HypnosisMetadata.Phase?)] = []
            for try await pair in group { pairs.append(pair) }
            return pairs
        }
    }

    static func assembleTimeline(
        bucketCount: Int,
        jobs: [ChunkJob],
        results: [HypnosisMetadata.Phase?]
    ) -> [HypnosisMetadata.Phase?] {
        var timeline = [HypnosisMetadata.Phase?](repeating: nil, count: bucketCount)
        for job in jobs {
            let start = max(0, min(Int(job.start), bucketCount - 1))
            let end   = max(0, min(Int(ceil(job.end)), bucketCount))
            for idx in start..<end { timeline[idx] = results[job.index] }
        }
        return timeline
    }

    /// Classifies a single chunk; splits in half recursively on context-window overflow.
    static func classifySingleChunk(
        request: ChunkRequest,
        previousPhase: HypnosisMetadata.Phase?,
        model: SystemLanguageModel
    ) async throws -> HypnosisMetadata.Phase? {
        let positionHint = buildPositionHint(pct: request.sessionPositionPct)
        let previousHint = previousPhase.map { "The previous segment was: \($0.rawValue)." } ?? ""
        let prompt = """
            \(positionHint)
            \(previousHint)

            Transcript segment (\(Int(request.startTime))s–\(Int(request.endTime))s \
            of \(Int(request.totalDuration))s total):
            "\(request.text)"

            Phase:
            """
        let session = LanguageModelSession(model: model, instructions: request.systemInstructions)
        do {
            let response = try await session.respond(to: prompt)
            return phaseFromResponse(response.content)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            return try await splitAndClassify(request: request, previousPhase: previousPhase, model: model)
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            return previousPhase
        } catch LanguageModelSession.GenerationError.refusal {
            return previousPhase
        }
    }

    static func splitAndClassify(
        request: ChunkRequest,
        previousPhase: HypnosisMetadata.Phase?,
        model: SystemLanguageModel
    ) async throws -> HypnosisMetadata.Phase? {
        let midTime = (request.startTime + request.endTime) / 2.0
        let words = request.text.components(separatedBy: " ")
        let midIdx = words.count / 2
        let midPct = Int((midTime / request.totalDuration) * 100.0)
        let first = ChunkRequest(
            text: words.prefix(midIdx).joined(separator: " "),
            startTime: request.startTime, endTime: midTime,
            sessionPositionPct: request.sessionPositionPct, totalDuration: request.totalDuration,
            systemInstructions: request.systemInstructions
        )
        let second = ChunkRequest(
            text: words.dropFirst(midIdx).joined(separator: " "),
            startTime: midTime, endTime: request.endTime,
            sessionPositionPct: midPct, totalDuration: request.totalDuration,
            systemInstructions: request.systemInstructions
        )
        async let phase1 = classifySingleChunk(request: first, previousPhase: previousPhase, model: model)
        async let phase2 = classifySingleChunk(request: second, previousPhase: previousPhase, model: model)
        let (result1, result2) = try await (phase1, phase2)
        return result2 ?? result1
    }
}

// MARK: - Position Hints & Response Parsing

private extension ChunkedPhaseAnalyzer {

    static func buildPositionHint(pct: Int) -> String {
        switch pct {
        case 0..<8:
            return "This is the BEGINNING of the session (\(pct)%). Expect pre_talk or early induction."
        case 8..<20:
            return "This is early in the session (\(pct)%). Likely induction or beginning of deepening."
        case 20..<40:
            return "This is the early-middle (\(pct)%). Likely deepening or early therapy (passive trance)."
        case 40..<55:
            return "This is the middle (\(pct)%). Therapy (passive) or suggestions (active commands)."
        case 55..<75:
            return "This is the later-middle (\(pct)%). Likely suggestions — 'you will', 'from now on'."
        case 75..<88:
            return "This is LATE (\(pct)%). Watch for emergence or post_hypnotic_conditioning."
        case 88..<95:
            return "This is NEAR THE END (\(pct)%). Very likely emergence."
        default:
            return "This is the FINAL PART (\(pct)%). Expect emergence — waking, re-orientation."
        }
    }

    static func phaseFromResponse(_ response: String) -> HypnosisMetadata.Phase? {
        let cleaned = response.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = HypnosisMetadata.Phase(rawValue: cleaned) { return exact }
        let candidates: [HypnosisMetadata.Phase] = [
            .preTalk, .induction, .deepening, .therapy,
            .suggestions, .conditioning, .emergence
        ]
        for phase in candidates where cleaned.localizedStandardContains(phase.rawValue) { return phase }
        if cleaned.localizedStandardContains("pre_induction") ||
           cleaned.localizedStandardContains("pre induction") ||
           cleaned.localizedStandardContains("pre-induction") { return .preTalk }
        if cleaned.localizedStandardContains("deep_trance") ||
           cleaned.localizedStandardContains("deep trance") { return .therapy }
        if cleaned.localizedStandardContains("conditioning") ||
           cleaned.localizedStandardContains("post_hypnotic") { return .conditioning }
        return nil
    }
}
