//
//  AnalyzerTranscriptCache.swift
//  Ilumionate
//
//  Persistent transcription cache for analyzer-optimizer runs.
//

import Foundation

actor AnalyzerTranscriptCache {
    private struct CachedTranscription: Codable {
        let schemaVersion: Int
        let cachedAt: Date
        let exampleID: UUID
        let audioSHA256: String
        let transcription: AudioTranscriptionResult
    }

    private let cacheDirectory: URL

    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
    }

    func transcription(
        for example: AnalyzerOptimizationDataset.Example,
        transcribe: (@Sendable (AnalyzerOptimizationDataset.Example) async throws -> AudioTranscriptionResult)? = nil
    ) async throws -> AudioTranscriptionResult {
        try ensureCacheDirectory()

        let cacheURL = cacheURL(for: example)
        if FileManager.default.fileExists(atPath: cacheURL.path()) {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cached = try decoder.decode(CachedTranscription.self, from: data)
            if cached.audioSHA256 == example.example.audio.sha256 {
                return cached.transcription
            }
        }

        guard let transcribe else {
            throw AnalyzerOptimizerError.transcriberRequired(example.example.exampleID)
        }

        let transcription = try await transcribe(example)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let payload = CachedTranscription(
            schemaVersion: 1,
            cachedAt: Date(),
            exampleID: example.example.exampleID,
            audioSHA256: example.example.audio.sha256,
            transcription: transcription
        )
        let data = try encoder.encode(payload)
        try data.write(to: cacheURL, options: .atomic)

        return transcription
    }

    private func cacheURL(for example: AnalyzerOptimizationDataset.Example) -> URL {
        cacheDirectory.appending(path: "\(example.example.audio.sha256).json")
    }

    private func ensureCacheDirectory() throws {
        guard !FileManager.default.fileExists(atPath: cacheDirectory.path()) else { return }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
