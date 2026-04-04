//
//  AnalyzerTrainingSupport.swift
//  LumeLabel
//
//  Minimal shared model surface needed by the analyzer optimizer and
//  transcription pipeline inside the macOS labeling utility.
//

import Foundation

struct AudioFile: Identifiable, Codable, Sendable {
    let id: UUID
    var filename: String
    let duration: TimeInterval
    let fileSize: Int64
    let createdDate: Date

    nonisolated var url: URL { URL.documentsDirectory.appending(path: filename) }
}

struct AnalysisResult: Sendable {
    typealias ContentType = AudioContentType
}

struct HypnosisMetadata: Sendable {
    typealias Phase = TrancePhase

    enum ConfidenceLevel: String, Codable, Sendable {
        case high
        case medium
        case low
    }
}

struct LinguisticMarker: Codable, Identifiable, Sendable {
    enum MarkerType: String, Codable, Sendable {
        case generic
    }

    let id: UUID
    let type: MarkerType
    let timestamp: TimeInterval
    let textSnippet: String?
    let strength: Double

    init(
        id: UUID = UUID(),
        type: MarkerType = .generic,
        timestamp: TimeInterval,
        textSnippet: String? = nil,
        strength: Double = 1.0
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.textSnippet = textSnippet
        self.strength = strength
    }
}

struct PhaseSegment: Codable, Identifiable, Sendable {
    let id: UUID
    let phase: HypnosisMetadata.Phase
    let startTime: TimeInterval
    let endTime: TimeInterval
    let characteristics: String
    let tranceDepthEstimate: Double
    let linguisticMarkers: [LinguisticMarker]
    let confidenceLevel: HypnosisMetadata.ConfidenceLevel
    let confidenceRationale: String?
    let transitionTarget: HypnosisMetadata.Phase?

    init(
        id: UUID = UUID(),
        phase: HypnosisMetadata.Phase,
        startTime: TimeInterval,
        endTime: TimeInterval,
        characteristics: String,
        tranceDepthEstimate: Double,
        linguisticMarkers: [LinguisticMarker] = [],
        confidenceLevel: HypnosisMetadata.ConfidenceLevel = .medium,
        confidenceRationale: String? = nil,
        transitionTarget: HypnosisMetadata.Phase? = nil
    ) {
        self.id = id
        self.phase = phase
        self.startTime = startTime
        self.endTime = endTime
        self.characteristics = characteristics
        self.tranceDepthEstimate = tranceDepthEstimate
        self.linguisticMarkers = linguisticMarkers
        self.confidenceLevel = confidenceLevel
        self.confidenceRationale = confidenceRationale
        self.transitionTarget = transitionTarget
    }
}
