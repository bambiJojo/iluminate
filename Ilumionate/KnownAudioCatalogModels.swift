//
//  KnownAudioCatalogModels.swift
//  Ilumionate
//

import Foundation

/// A neutral descriptor for a bundled transcript. The catalog remains dormant
/// unless the imported filename or embedded title confidently matches an entry.
nonisolated struct KnownAudioCatalogEntry: Codable, Identifiable, Sendable {
    let id: String
    let series: String
    let trackNumber: String
    let title: String
    let aliases: [String]
    let contentFingerprints: [String]
    let role: PlaylistSessionRole
    let seedProfile: KnownAudioSeedProfile
    let creator: String?
    let sourceKind: KnownAudioTranscriptSourceKind
    let sourceDocument: String
    let sourceURL: URL?
    let transcript: String
    let goldLightScore: KnownAudioGoldLightScore
}

nonisolated enum KnownAudioSeedProfile: String, Codable, Sendable {
    case induction
    case deepening
    case conditioning
    case emergence
    case sleep
}

nonisolated enum KnownAudioTranscriptSourceKind: String, Codable, Sendable {
    case communityTranscript
    case catalogMetadata
    case localAudioReview
}

nonisolated struct KnownAudioCatalogMatch: Sendable {
    let entry: KnownAudioCatalogEntry
    let confidence: Double
}

/// A reviewed, versioned light timeline authored in normalized time so one
/// canonical score remains synchronized with every recognized copy of a track.
nonisolated struct KnownAudioGoldLightScore: Codable, Sendable {
    let scoreVersion: Int
    let sessionID: UUID
    let designIntent: String
    let playlistPlacement: KnownAudioGoldPlaylistPlacement
    let evidenceKind: KnownAudioGoldEvidenceKind
    let timingBasis: KnownAudioGoldTimingBasis
    let referenceDuration: Double?
    let transcriptCoverage: Double?
    let transcriptAnchorCount: Int
    let evidenceAnchors: [KnownAudioGoldEvidenceAnchor]
    let moments: [KnownAudioGoldLightMoment]
}

nonisolated enum KnownAudioGoldEvidenceKind: String, Codable, Sendable {
    case communityTranscript
    case localAudioReview
    case catalogMetadata
}

nonisolated enum KnownAudioGoldTimingBasis: String, Codable, Sendable {
    case referenceAudio
    case transcriptMarkers
    case transcriptOrder
    case reviewedAudioTiming
    case intentOnly
}

nonisolated struct KnownAudioGoldEvidenceAnchor: Codable, Sendable {
    let position: Double
    let cue: String
    let source: KnownAudioGoldEvidenceAnchorSource
}

nonisolated enum KnownAudioGoldEvidenceAnchorSource: String, Codable, Sendable {
    case timedTranscript
    case transcriptOrder
    case localModelTranscript
    case reviewedIntent
}

nonisolated enum KnownAudioGoldPlaylistPlacement: String, Codable, Sendable {
    case entry
    case early
    case earlyOrMiddle
    case middle
    case late
    case exit
    case sleepExit
}

nonisolated struct KnownAudioGoldLightMoment: Codable, Sendable {
    let position: Double
    let frequency: Double
    let intensity: Double
    let waveform: KnownAudioGoldWaveform
    let rampDuration: Double?
    let bilateral: Bool?
    let bilateralTransitionDuration: Double?
    let colorTemperature: Double?
}

nonisolated enum KnownAudioGoldWaveform: String, Codable, Sendable {
    case sine
    case triangle
    case softPulse = "soft_pulse"
    case noiseModulatedSine = "noise_sine"
}

nonisolated struct KnownAudioCatalogDocument: Codable, Sendable {
    let schemaVersion: Int
    let sourceNotice: String
    let entries: [KnownAudioCatalogEntry]
}
