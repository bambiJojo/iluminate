//
//  TranscriptCacheStore.swift
//  LumeLabel
//
//  One cache format for per-file, bulk, and safety-scoped transcription.
//

import Foundation

nonisolated enum TranscriptCacheStore {
    private struct CachedTranscription: Codable {
        let schemaVersion: Int
        let cachedAt: Date
        let exampleID: UUID
        let audioSHA256: String
        let transcription: AudioTranscriptionResult
    }

    static func load(
        for file: LabeledFile,
        in datasetDirectory: URL
    ) throws -> AudioTranscriptionResult? {
        guard file.audioSHA256.isEmpty == false else { return nil }
        let url = TranscriptInventory.cacheURL(forHash: file.audioSHA256, in: datasetDirectory)
        guard FileManager.default.fileExists(atPath: url.path()) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let cached = try decoder.decode(CachedTranscription.self, from: Data(contentsOf: url))
        guard cached.audioSHA256 == file.audioSHA256 else { return nil }
        return cached.transcription
    }

    static func save(
        _ result: AudioTranscriptionResult,
        for file: LabeledFile,
        in datasetDirectory: URL
    ) throws {
        guard file.audioSHA256.isEmpty == false else { return }
        let destination = TranscriptInventory.cacheURL(forHash: file.audioSHA256, in: datasetDirectory)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(
            CachedTranscription(
                schemaVersion: 1,
                cachedAt: Date(),
                exampleID: file.id,
                audioSHA256: file.audioSHA256,
                transcription: result
            )
        ).write(to: destination, options: .atomic)
    }
}
