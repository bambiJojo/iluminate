//
//  AnalyzerTranscriptCache.swift
//  Ilumionate
//
//  Persistent transcription cache for analyzer-optimizer runs.
//

import Foundation
import os

private extension URL {
    var isReadableFile: Bool { FileManager.default.isReadableFile(atPath: path()) }
}

actor AnalyzerTranscriptCache {
    struct PreparedTranscription: Codable, Sendable {
        let transcription: AudioTranscriptionResult
        let wordTimestamps: [WordTimestamp]
        let heuristicContentType: AudioContentType
        let wordCount: Int

        /// Cached alongside the transcript because deriving it needs the audio.
        ///
        /// Without this every consumer that wants speech rate, pitch or pause
        /// structure has to decode the whole file again — which is what the
        /// structural detector had to do, in a separate tool, to be evaluated at
        /// all. Prosody is also the signal that mattered most there: adding it
        /// roughly doubled boundary recall over text alone.
        ///
        /// `nil` when the audio could not be read. A missing profile degrades a
        /// consumer to text-only; it must never fail a transcript that is
        /// otherwise usable.
        let prosody: ProsodicProfile?
    }

    private struct CachedPreparedFields: Codable, Sendable {
        let wordTimestamps: [WordTimestamp]
        let heuristicContentType: AudioContentType
        let wordCount: Int
        /// Optional so a schema-2 cache still decodes; a nil here is refilled by
        /// one audio pass rather than invalidating the transcript.
        let prosody: ProsodicProfile?
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
        if let official = BundledAudioTranscriptCatalog.shared.transcription(
            filename: example.originalFilename,
            duration: example.duration
        ) {
            let prepared = makePreparedTranscription(from: official, audioURL: example.audioURL)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try writeCachedTranscription(
                transcription: official,
                prepared: prepared,
                for: example,
                cacheURL: cacheURL,
                encoder: encoder
            )
            return prepared
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if FileManager.default.fileExists(atPath: cacheURL.path()) {
            let data = try Data(contentsOf: cacheURL)
            let cached = try decoder.decode(CachedTranscription.self, from: data)
            if cached.audioSHA256 == example.example.audio.sha256 {
                // A schema-2 entry has everything but prosody. Refill it with one
                // audio pass rather than discarding a good transcript — and only
                // when the audio is actually there, so a relocated corpus keeps
                // working text-only.
                if let prepared = cached.prepared,
                   prepared.prosody != nil || example.audioURL.isReadableFile == false {
                    return PreparedTranscription(
                        transcription: cached.transcription,
                        wordTimestamps: prepared.wordTimestamps,
                        heuristicContentType: prepared.heuristicContentType,
                        wordCount: prepared.wordCount,
                        prosody: prepared.prosody
                    )
                }

                let upgraded = makePreparedTranscription(from: cached.transcription, audioURL: example.audioURL)
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
        let prepared = makePreparedTranscription(from: transcription, audioURL: example.audioURL)
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
        from transcription: AudioTranscriptionResult,
        audioURL: URL?
    ) -> PreparedTranscription {
        PreparedTranscription(
            transcription: transcription,
            wordTimestamps: HypnosisPhaseAnalyzer.approximateWordTimestamps(from: transcription.segments),
            heuristicContentType: AnalyzerEvaluationEngine.heuristicContentType(for: transcription),
            wordCount: transcription.wordCount,
            prosody: prosody(for: transcription, audioURL: audioURL)
        )
    }

    /// Never throws. Prosody is an enrichment: a corpus entry whose audio has
    /// moved should still be usable for everything text-based.
    private nonisolated static func prosody(
        for transcription: AudioTranscriptionResult,
        audioURL: URL?
    ) -> ProsodicProfile? {
        guard let audioURL, FileManager.default.fileExists(atPath: audioURL.path()) else { return nil }
        do {
            return try ProsodyAnalyzer().analyze(url: audioURL, segments: transcription.segments)
        } catch {
            Log.analysis.error(
                "Prosody unavailable for \(audioURL.lastPathComponent): \(error.localizedDescription)"
            )
            return nil
        }
    }

    private nonisolated static func writeCachedTranscription(
        transcription: AudioTranscriptionResult,
        prepared: PreparedTranscription,
        for example: AnalyzerOptimizationDataset.Example,
        cacheURL: URL,
        encoder: JSONEncoder
    ) throws {
        let payload = CachedTranscription(
            schemaVersion: 3,
            cachedAt: Date(),
            exampleID: example.example.exampleID,
            audioSHA256: example.example.audio.sha256,
            transcription: transcription,
            prepared: CachedPreparedFields(
                wordTimestamps: prepared.wordTimestamps,
                heuristicContentType: prepared.heuristicContentType,
                wordCount: prepared.wordCount,
                prosody: prepared.prosody
            )
        )
        let data = try encoder.encode(payload)
        try data.write(to: cacheURL, options: .atomic)
    }
}
