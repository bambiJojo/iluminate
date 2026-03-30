//
//  LabeledFile.swift
//  Ilumionate
//
//  Ground-truth labeled audio file for analyzer training.
//

import Foundation
import CryptoKit

struct LabeledFile: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var version: Int = 1
    var audioFilename: String
    var audioDuration: TimeInterval
    var audioSHA256: String
    var expectedContentType: AnalysisResult.ContentType
    var expectedFrequencyBand: FrequencyBand
    var phases: [LabeledPhase]
    var techniques: [LabeledTechnique]
    var labeledAt: Date
    var labelerNotes: String

    var status: LabelStatus {
        if phases.isEmpty { return .unlabeled }
        let allHaveNotes = phases.allSatisfy { !($0.notes ?? "").isEmpty }
        return allHaveNotes ? .refined : .rough
    }

    enum LabelStatus: String, Codable, Sendable {
        case unlabeled, rough, refined
    }

    struct FrequencyBand: Codable, Sendable {
        var lower: Double
        var upper: Double
        var closedRange: ClosedRange<Double> { lower...upper }
    }

    struct LabeledPhase: Codable, Identifiable, Sendable {
        var id: UUID = UUID()
        var phase: HypnosisMetadata.Phase
        var startTime: TimeInterval
        var endTime: TimeInterval
        var notes: String?
    }

    struct LabeledTechnique: Codable, Identifiable, Sendable {
        var id: UUID = UUID()
        var name: String
        var startTime: TimeInterval
        var endTime: TimeInterval
    }

    /// Computes SHA256 of the first 64KB of the audio file.
    static func computeSHA256(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        guard !chunk.isEmpty else { return nil }
        return SHA256.hash(data: chunk).map { String(format: "%02x", $0) }.joined()
    }
}

extension LabeledFile: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: LabeledFile, rhs: LabeledFile) -> Bool { lhs.id == rhs.id }
}
