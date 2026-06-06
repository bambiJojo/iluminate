//
//  AnalyzerTranscriptCache.swift
//  Ilumionate
//
//  Persistent transcription cache for analyzer-optimizer runs.
//

import Foundation

actor AnalyzerTranscriptCache {
    struct PreparedTranscription: Codable, Sendable {
        let transcription: AudioTranscriptionResult
        let wordTimestamps: [WordTimestamp]
        let heuristicContentType: AudioContentType
        let wordCount: Int
    }

    private struct CachedPreparedFields: Codable, Sendable {
        let wordTimestamps: [WordTimestamp]
        let heuristicContentType: AudioContentType
        let wordCount: Int
    }

    private struct CachedTranscription: Codable {
        let schemaVersion: Int
        let cachedAt: Date
        let exampleID: UUID
        let audioSHA256: String
        let transcription: AudioTranscriptionResult
        let prepared: CachedPreparedFields?
    }

    private let cacheDirectory: URL
    private var preparedCache: [String: PreparedTranscription] = [:]
    private var inFlightPreparedTasks: [String: Task<PreparedTranscription, Error>] = [:]

    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
    }

    func transcription(
        for example: AnalyzerOptimizationDataset.Example,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)? = nil
    ) async throws -> AudioTranscriptionResult {
        let prepared = try await preparedTranscription(for: example, transcribe: transcribe)
        return prepared.transcription
    }

    func preparedTranscription(
        for example: AnalyzerOptimizationDataset.Example,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)? = nil
    ) async throws -> PreparedTranscription {
        try ensureCacheDirectory()

        let cacheKey = example.example.audio.sha256
        if let prepared = preparedCache[cacheKey] {
            return prepared
        }
        if let inFlightTask = inFlightPreparedTasks[cacheKey] {
            return try await inFlightTask.value
        }

        let cacheURL = cacheURL(for: example)
        let task = Task<PreparedTranscription, Error> {
            try await Self.loadOrBuildPreparedTranscription(
                for: example,
                transcribe: transcribe,
                cacheURL: cacheURL
            )
        }
        inFlightPreparedTasks[cacheKey] = task

        defer {
            inFlightPreparedTasks[cacheKey] = nil
        }

        let prepared = try await task.value
        preparedCache[cacheKey] = prepared
        return prepared
    }

    private func cacheURL(for example: AnalyzerOptimizationDataset.Example) -> URL {
        cacheDirectory.appending(path: "\(example.example.audio.sha256).json")
    }

    private func ensureCacheDirectory() throws {
        guard !FileManager.default.fileExists(atPath: cacheDirectory.path()) else { return }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private nonisolated static func loadOrBuildPreparedTranscription(
        for example: AnalyzerOptimizationDataset.Example,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)?,
        cacheURL: URL
    ) async throws -> PreparedTranscription {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if FileManager.default.fileExists(atPath: cacheURL.path()) {
            let data = try Data(contentsOf: cacheURL)
            let cached = try decoder.decode(CachedTranscription.self, from: data)
            if cached.audioSHA256 == example.example.audio.sha256 {
                if let prepared = cached.prepared {
                    return PreparedTranscription(
                        transcription: cached.transcription,
                        wordTimestamps: prepared.wordTimestamps,
                        heuristicContentType: prepared.heuristicContentType,
                        wordCount: prepared.wordCount
                    )
                }

                let upgraded = makePreparedTranscription(from: cached.transcription)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try writeCachedTranscription(
                    transcription: cached.transcription,
                    prepared: upgraded,
                    for: example,
                    cacheURL: cacheURL,
                    encoder: encoder
                )
                return upgraded
            }
        }

        guard let transcribe else {
            throw AnalyzerOptimizerError.transcriberRequired(example.example.exampleID)
        }

        let transcription = try await transcribe(example)
        let prepared = makePreparedTranscription(from: transcription)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try writeCachedTranscription(
            transcription: transcription,
            prepared: prepared,
            for: example,
            cacheURL: cacheURL,
            encoder: encoder
        )
        return prepared
    }

    private nonisolated static func makePreparedTranscription(
        from transcription: AudioTranscriptionResult
    ) -> PreparedTranscription {
        PreparedTranscription(
            transcription: transcription,
            wordTimestamps: HypnosisPhaseAnalyzer.approximateWordTimestamps(from: transcription.segments),
            heuristicContentType: AnalyzerEvaluationEngine.heuristicContentType(for: transcription),
            wordCount: transcription.wordCount
        )
    }

    private nonisolated static func writeCachedTranscription(
        transcription: AudioTranscriptionResult,
        prepared: PreparedTranscription,
        for example: AnalyzerOptimizationDataset.Example,
        cacheURL: URL,
        encoder: JSONEncoder
    ) throws {
        let payload = CachedTranscription(
            schemaVersion: 2,
            cachedAt: Date(),
            exampleID: example.example.exampleID,
            audioSHA256: example.example.audio.sha256,
            transcription: transcription,
            prepared: CachedPreparedFields(
                wordTimestamps: prepared.wordTimestamps,
                heuristicContentType: prepared.heuristicContentType,
                wordCount: prepared.wordCount
            )
        )
        let data = try encoder.encode(payload)
        try data.write(to: cacheURL, options: .atomic)
    }
}
