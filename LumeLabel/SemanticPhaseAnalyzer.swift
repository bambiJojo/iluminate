//
//  SemanticPhaseAnalyzer.swift
//  LumeLabel
//
//  Experimental, on-device phase evidence from sentence meaning. This stays in
//  LumeLabel until corpus measurement shows that it improves on phrase matching.
//

import Foundation
import NaturalLanguage

nonisolated struct SemanticPhaseAnalyzer: Sendable {
    struct Configuration: Sendable {
        var windowWordCount: Int
        var windowStride: Int
        var positionPenalty: Double
        var confidenceTemperature: Double
        var smoothingRadius: Int

        init(
            windowWordCount: Int = 28,
            windowStride: Int = 14,
            positionPenalty: Double = 0.12,
            confidenceTemperature: Double = 0.15,
            smoothingRadius: Int = 2
        ) {
            self.windowWordCount = max(2, windowWordCount)
            self.windowStride = max(1, windowStride)
            self.positionPenalty = max(0, positionPenalty)
            self.confidenceTemperature = max(0.01, confidenceTemperature)
            self.smoothingRadius = max(0, smoothingRadius)
        }
    }

    struct Example: Sendable {
        let phase: HypnosisMetadata.Phase
        let text: String
        let position: Double
        let sourceExampleID: UUID?
        let sourceFilename: String?

        init(
            phase: HypnosisMetadata.Phase,
            text: String,
            position: Double,
            sourceExampleID: UUID? = nil,
            sourceFilename: String? = nil
        ) {
            self.phase = phase.labelingPhase
            self.text = text
            self.position = min(max(position, 0), 1)
            self.sourceExampleID = sourceExampleID
            self.sourceFilename = sourceFilename
        }
    }

    struct Window: Identifiable, Sendable {
        let id: UUID
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
        let phase: HypnosisMetadata.Phase
        let confidence: Double
        let matchedExampleText: String
        let semanticDistance: Double
    }

    struct Segment: Identifiable, Sendable {
        let id: UUID
        let phase: HypnosisMetadata.Phase
        let startTime: TimeInterval
        let endTime: TimeInterval
        let confidence: Double
        let windowCount: Int
        let matchedExampleText: String
    }

    struct Analysis: Sendable {
        let windows: [Window]
        let segments: [Segment]
        let exampleCount: Int
    }

    enum AnalysisError: LocalizedError {
        case sentenceEmbeddingUnavailable

        var errorDescription: String? {
            switch self {
            case .sentenceEmbeddingUnavailable:
                return "The on-device English sentence embedding is unavailable."
            }
        }
    }

    let examples: [Example]
    let configuration: Configuration
    private let semanticDistance: (@Sendable (String, String) -> Double)?

    init(
        examples: [Example],
        configuration: Configuration = .init()
    ) {
        self.examples = examples.filter {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        self.configuration = configuration
        self.semanticDistance = nil
    }

    init(
        examples: [Example],
        configuration: Configuration = .init(),
        semanticDistance: @escaping @Sendable (String, String) -> Double
    ) {
        self.examples = examples.filter {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        self.configuration = configuration
        self.semanticDistance = semanticDistance
    }

    init(
        corpusKnowledge: CorpusPhaseKnowledge,
        configuration: Configuration = .init()
    ) {
        let labeledExamples = corpusKnowledge.fewShotExamples.compactMap { example -> Example? in
            guard example.sourcePackID == nil,
                  let phase = TrancePhase(rawValue: example.correctPhase) else {
                return nil
            }
            return Example(
                phase: phase,
                text: example.text,
                position: example.position
            )
        }
        self.init(examples: labeledExamples, configuration: configuration)
    }

    func analyze(transcription: AudioTranscriptionResult) throws -> Analysis {
        try Task.checkCancellation()
        guard examples.isEmpty == false else {
            return Analysis(windows: [], segments: [], exampleCount: 0)
        }
        let words = HypnosisPhaseAnalyzer.approximateWordTimestamps(
            from: transcription.segments
        )
        guard words.isEmpty == false else {
            return Analysis(windows: [], segments: [], exampleCount: examples.count)
        }

        let inputWindows = makeWindows(
            from: words,
            duration: transcription.duration
        )
        let windows: [Window]
        if let semanticDistance {
            windows = try inputWindows.map { inputWindow in
                try Task.checkCancellation()
                return classify(
                    inputWindow,
                    semanticDistanceBetween: semanticDistance
                )
            }
        } else {
            guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
                throw AnalysisError.sentenceEmbeddingUnavailable
            }
            let embeddedExamples = examples.compactMap { example -> (Example, [Double])? in
                guard let vector = embedding.vector(for: example.text) else { return nil }
                return (example, vector)
            }
            let candidateExamples = embeddedExamples.map(\.0)
            let vectorsByText = embeddedExamples.reduce(into: [String: [Double]]()) {
                $0[$1.0.text] = $1.1
            }

            windows = try inputWindows.compactMap { inputWindow in
                try Task.checkCancellation()
                guard let windowVector = embedding.vector(for: inputWindow.text),
                      candidateExamples.isEmpty == false else {
                    return nil
                }
                return classify(
                    inputWindow,
                    examples: candidateExamples
                ) { _, exampleText in
                    guard let exampleVector = vectorsByText[exampleText] else {
                        return .infinity
                    }
                    return Self.cosineDistance(windowVector, exampleVector)
                }
            }
        }

        return Analysis(
            windows: windows,
            segments: makeSegments(from: windows, duration: transcription.duration),
            exampleCount: examples.count
        )
    }

    private struct InputWindow {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
        let position: Double
    }

    private func makeWindows(
        from words: [WordTimestamp],
        duration: TimeInterval
    ) -> [InputWindow] {
        let windowWordCount = min(configuration.windowWordCount, words.count)
        let finalStart = max(0, words.count - windowWordCount)
        var starts = Array(
            stride(
                from: 0,
                through: finalStart,
                by: configuration.windowStride
            )
        )
        if starts.last != finalStart {
            starts.append(finalStart)
        }

        return starts.map { startIndex in
            let endIndex = min(startIndex + windowWordCount, words.count)
            let windowWords = words[startIndex..<endIndex]
            let startTime = windowWords.first?.startTime ?? 0
            let endTime = windowWords.last?.endTime ?? startTime
            let midpoint = (startTime + endTime) / 2
            let position = duration > 0 ? midpoint / duration : 0.5
            return InputWindow(
                startTime: startTime,
                endTime: endTime,
                text: windowWords.map(\.word).joined(separator: " "),
                position: min(max(position, 0), 1)
            )
        }
    }

    private func classify(
        _ inputWindow: InputWindow,
        examples candidateExamples: [Example]? = nil,
        semanticDistanceBetween: (String, String) -> Double
    ) -> Window {
        let matches = (candidateExamples ?? examples).map { example in
            let semanticDistance = semanticDistanceBetween(
                inputWindow.text,
                example.text
            )
            let positionDistance = abs(inputWindow.position - example.position)
                * configuration.positionPenalty
            return (
                example: example,
                semanticDistance: semanticDistance,
                adjustedDistance: semanticDistance + positionDistance
            )
        }
        let bestByPhase = Dictionary(grouping: matches, by: { $0.example.phase })
            .compactMapValues { phaseMatches in
                phaseMatches.min { $0.adjustedDistance < $1.adjustedDistance }
            }
        guard let winner = bestByPhase.values.min(by: {
            $0.adjustedDistance < $1.adjustedDistance
        }) else {
            preconditionFailure("Filtered semantic examples unexpectedly produced no phase candidates.")
        }

        let minimumDistance = winner.adjustedDistance
        let phaseWeights = bestByPhase.values.map {
            exp(
                -($0.adjustedDistance - minimumDistance)
                    / configuration.confidenceTemperature
            )
        }
        let totalWeight = max(phaseWeights.reduce(0, +), .leastNonzeroMagnitude)
        let confidence = 1.0 / totalWeight

        return Window(
            id: UUID(),
            startTime: inputWindow.startTime,
            endTime: inputWindow.endTime,
            text: inputWindow.text,
            phase: winner.example.phase,
            confidence: confidence,
            matchedExampleText: winner.example.text,
            semanticDistance: winner.semanticDistance
        )
    }

    private static func cosineDistance(
        _ lhs: [Double],
        _ rhs: [Double]
    ) -> Double {
        guard lhs.count == rhs.count, lhs.isEmpty == false else { return .infinity }
        var dotProduct = 0.0
        var lhsMagnitude = 0.0
        var rhsMagnitude = 0.0
        for index in lhs.indices {
            dotProduct += lhs[index] * rhs[index]
            lhsMagnitude += lhs[index] * lhs[index]
            rhsMagnitude += rhs[index] * rhs[index]
        }
        let denominator = sqrt(lhsMagnitude * rhsMagnitude)
        guard denominator > .leastNonzeroMagnitude else { return .infinity }
        return 1.0 - (dotProduct / denominator)
    }

    private func makeSegments(
        from windows: [Window],
        duration: TimeInterval
    ) -> [Segment] {
        guard let firstWindow = windows.first else { return [] }
        let phases = stabilizedPhases(for: windows)
        guard let firstPhase = phases.first else { return [] }

        var segments: [Segment] = []
        var runWindows = [firstWindow]
        var runPhase = firstPhase
        var runStart: TimeInterval = 0

        for (window, phase) in zip(windows.dropFirst(), phases.dropFirst()) {
            guard phase != runPhase else {
                runWindows.append(window)
                continue
            }

            let previousWindow = runWindows[runWindows.count - 1]
            let previousMidpoint = (previousWindow.startTime + previousWindow.endTime) / 2
            let nextMidpoint = (window.startTime + window.endTime) / 2
            let boundary = (previousMidpoint + nextMidpoint) / 2
            segments.append(makeSegment(
                windows: runWindows,
                phase: runPhase,
                startTime: runStart,
                endTime: boundary
            ))
            runStart = boundary
            runWindows = [window]
            runPhase = phase
        }

        segments.append(makeSegment(
            windows: runWindows,
            phase: runPhase,
            startTime: runStart,
            endTime: max(runStart, duration)
        ))
        return segments
    }

    private func stabilizedPhases(
        for windows: [Window]
    ) -> [HypnosisMetadata.Phase] {
        guard configuration.smoothingRadius > 0, windows.count >= 3 else {
            return windows.map(\.phase)
        }

        return windows.indices.map { index in
            let lower = max(windows.startIndex, index - configuration.smoothingRadius)
            let upper = min(windows.index(before: windows.endIndex), index + configuration.smoothingRadius)
            let neighborhood = windows[lower...upper]
            let counts = neighborhood.reduce(into: [HypnosisMetadata.Phase: Int]()) {
                $0[$1.phase, default: 0] += 1
            }
            let maximumCount = counts.values.max() ?? 0
            let leaders = Set(counts.compactMap { phase, count in
                count == maximumCount ? phase : nil
            })

            if leaders.contains(windows[index].phase) {
                return windows[index].phase
            }
            return leaders.max { lhs, rhs in
                let lhsConfidence = neighborhood
                    .filter { $0.phase == lhs }
                    .reduce(0.0) { $0 + $1.confidence }
                let rhsConfidence = neighborhood
                    .filter { $0.phase == rhs }
                    .reduce(0.0) { $0 + $1.confidence }
                return lhsConfidence < rhsConfidence
            } ?? windows[index].phase
        }
    }

    private func makeSegment(
        windows: [Window],
        phase: HypnosisMetadata.Phase,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> Segment {
        let supportingWindows = windows.filter { $0.phase == phase }
        let evidenceWindows = supportingWindows.isEmpty ? windows : supportingWindows
        let averageConfidence = evidenceWindows.reduce(0.0) { $0 + $1.confidence }
            / Double(max(evidenceWindows.count, 1))
        let supportFraction = Double(supportingWindows.count) / Double(max(windows.count, 1))
        let confidence = averageConfidence * max(supportFraction, 0.25)
        let representative = evidenceWindows.max { $0.confidence < $1.confidence }
            ?? windows[0]
        return Segment(
            id: UUID(),
            phase: phase,
            startTime: startTime,
            endTime: endTime,
            confidence: confidence,
            windowCount: windows.count,
            matchedExampleText: representative.matchedExampleText
        )
    }
}

nonisolated enum SemanticPhaseExampleStore {
    struct Source: Sendable {
        let id: UUID
        let filename: String
        let duration: TimeInterval
        let phaseSegments: [AnalyzerTrainingExample.PhaseSegment]
        let transcription: AudioTranscriptionResult
    }

    private struct CachedTranscription: Decodable {
        let audioSHA256: String
        let transcription: AudioTranscriptionResult
    }

    static func load(
        from corpusDirectory: URL,
        excluding excludedExampleID: UUID?
    ) throws -> [SemanticPhaseAnalyzer.Example] {
        let dataset = try AnalyzerOptimizationDataset.load(from: corpusDirectory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let sources = dataset.examples.compactMap { example -> Source? in
            guard example.example.labelTrust.isTrustedForLearning else {
                return nil
            }
            let cacheURL = dataset.transcriptCacheDirectory
                .appending(path: "\(example.example.audio.sha256).json")
            guard let data = try? Data(contentsOf: cacheURL),
                  let cached = try? decoder.decode(CachedTranscription.self, from: data),
                  cached.audioSHA256 == example.example.audio.sha256 else {
                return nil
            }
            return Source(
                id: example.id,
                filename: example.originalFilename,
                duration: example.duration,
                phaseSegments: example.phaseSegments,
                transcription: cached.transcription
            )
        }
        return makeExamples(from: sources, excluding: excludedExampleID)
    }

    static func makeExamples(
        from sources: [Source],
        excluding excludedExampleID: UUID?
    ) -> [SemanticPhaseAnalyzer.Example] {
        sources
            .filter { $0.id != excludedExampleID }
            .flatMap(makeExamples(from:))
    }

    private static func makeExamples(
        from source: Source
    ) -> [SemanticPhaseAnalyzer.Example] {
        let words = HypnosisPhaseAnalyzer.approximateWordTimestamps(
            from: source.transcription.segments
        )
        let exampleWordCount = 40

        return source.phaseSegments.flatMap { phaseSegment -> [SemanticPhaseAnalyzer.Example] in
            let phaseWords = words.filter {
                $0.startTime >= phaseSegment.startTime
                    && $0.startTime < phaseSegment.endTime
            }
            guard phaseWords.isEmpty == false else { return [] }

            let windowWordCount = min(exampleWordCount, phaseWords.count)
            let finalStart = max(0, phaseWords.count - windowWordCount)
            let middleStart = max(0, (phaseWords.count - windowWordCount) / 2)
            let starts = Array(Set([0, middleStart, finalStart])).sorted()

            return starts.map { startIndex in
                let endIndex = min(startIndex + windowWordCount, phaseWords.count)
                let excerptWords = phaseWords[startIndex..<endIndex]
                let excerptStart = excerptWords.first?.startTime ?? phaseSegment.startTime
                let excerptEnd = excerptWords.last?.endTime ?? phaseSegment.endTime
                let position = source.duration > 0
                    ? ((excerptStart + excerptEnd) / 2) / source.duration
                    : 0.5
                return SemanticPhaseAnalyzer.Example(
                    phase: phaseSegment.phase,
                    text: excerptWords.map(\.word).joined(separator: " "),
                    position: position,
                    sourceExampleID: source.id,
                    sourceFilename: source.filename
                )
            }
        }
    }
}
