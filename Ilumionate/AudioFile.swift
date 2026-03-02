//
//  AudioFile.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation

/// Represents an audio file that can be used for session generation
struct AudioFile: Identifiable, Codable {
    let id: UUID
    let filename: String
    let url: URL
    let duration: TimeInterval
    let fileSize: Int64
    let createdDate: Date

    // Optional analysis data
    var transcription: String?
    var analysisResult: AnalysisResult?
    var deadTimeProfile: DeadTimeProfile?

    init(id: UUID = UUID(), filename: String, url: URL, duration: TimeInterval,
         fileSize: Int64, createdDate: Date = Date()) {
        self.id = id
        self.filename = filename
        self.url = url
        self.duration = duration
        self.fileSize = fileSize
        self.createdDate = createdDate
    }

    // MARK: - Computed Properties

    var durationFormatted: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var isAnalyzed: Bool {
        analysisResult != nil
    }

    var hasTranscription: Bool {
        transcription != nil && !(transcription?.isEmpty ?? true)
    }
}

/// Results from AI audio analysis
struct AnalysisResult: Codable {
    enum Mood: String, Codable {
        case relaxing
        case energizing
        case neutral
        case meditative
        case uplifting
        case melancholic
    }

    enum ContentType: String, Codable {
        case hypnosis
        case meditation
        case music
        case guidedImagery
        case affirmations
        case unknown
    }

    let mood: Mood
    let energyLevel: Double // 0.0 (very calm) to 1.0 (very energetic)
    let suggestedFrequencyRange: ClosedRange<Double>
    let suggestedIntensity: Double
    let suggestedColorTemperature: Double? // Kelvin
    let keyMoments: [KeyMoment]
    let aiSummary: String
    let recommendedPreset: String

    // Enhanced analysis data
    let contentType: ContentType
    let hypnosisMetadata: HypnosisMetadata?
    let temporalAnalysis: TemporalAnalysis?
    let voiceCharacteristics: VoiceCharacteristics?
    let classificationConfidence: ClassificationConfidence?

    init(mood: Mood, energyLevel: Double, suggestedFrequencyRange: ClosedRange<Double>,
         suggestedIntensity: Double, suggestedColorTemperature: Double? = nil,
         keyMoments: [KeyMoment], aiSummary: String, recommendedPreset: String,
         contentType: ContentType = .unknown,
         hypnosisMetadata: HypnosisMetadata? = nil,
         temporalAnalysis: TemporalAnalysis? = nil,
         voiceCharacteristics: VoiceCharacteristics? = nil,
         classificationConfidence: ClassificationConfidence? = nil) {
        self.mood = mood
        self.energyLevel = energyLevel
        self.suggestedFrequencyRange = suggestedFrequencyRange
        self.suggestedIntensity = suggestedIntensity
        self.suggestedColorTemperature = suggestedColorTemperature
        self.keyMoments = keyMoments
        self.aiSummary = aiSummary
        self.recommendedPreset = recommendedPreset
        self.contentType = contentType
        self.hypnosisMetadata = hypnosisMetadata
        self.temporalAnalysis = temporalAnalysis
        self.voiceCharacteristics = voiceCharacteristics
        self.classificationConfidence = classificationConfidence
    }
}

/// Represents a significant moment in the audio
struct KeyMoment: Codable, Identifiable {
    let id: UUID
    let time: TimeInterval
    let description: String
    let suggestedAction: String // e.g., "increase intensity", "shift to warmer colors"

    init(id: UUID = UUID(), time: TimeInterval, description: String, suggestedAction: String) {
        self.id = id
        self.time = time
        self.description = description
        self.suggestedAction = suggestedAction
    }
}

// MARK: - Hypnosis-Specific Metadata

/// Detailed hypnosis session analysis
struct HypnosisMetadata: Codable {
    enum Phase: String, Codable {
        case preTalk = "pre_talk"
        case induction
        case deepening
        case therapy
        case suggestions
        case conditioning = "post_hypnotic_conditioning"
        case emergence
        case transitional // Used when phases blend

        var displayName: String {
            switch self {
            case .preTalk: return "Pre-Talk"
            case .induction: return "Induction"
            case .deepening: return "Deepening"
            case .therapy: return "Therapeutic Work"
            case .suggestions: return "Suggestions"
            case .conditioning: return "Post-Hypnotic Conditioning"
            case .emergence: return "Emergence"
            case .transitional: return "Transitional"
            }
        }
    }

    enum ConfidenceLevel: String, Codable {
        case high
        case medium
        case low

        var numericValue: Double {
            switch self {
            case .high: return 0.85
            case .medium: return 0.60
            case .low: return 0.35
            }
        }
    }

    enum InductionStyle: String, Codable {
        case progressive
        case authoritarian
        case permissive
        case confusion
        case rapid
        case ericksonian
        case conversational
    }

    enum TranceDeph: String, Codable {
        case light
        case medium
        case deep
        case somnambulism
    }

    let phases: [PhaseSegment]
    let inductionStyle: InductionStyle?
    let estimatedTranceDeph: TranceDeph
    let suggestionDensity: Double? // suggestions per minute
    let languagePatterns: [String] // "metaphor", "embedded commands", etc.
    let detectedTechniques: [HypnoticTechnique]
}

/// A phase segment within a hypnosis session
struct PhaseSegment: Codable, Identifiable {
    let id: UUID
    let phase: HypnosisMetadata.Phase
    let startTime: TimeInterval
    let endTime: TimeInterval
    let characteristics: String
    let tranceDepthEstimate: Double // 0.0-1.0
    let linguisticMarkers: [LinguisticMarker]
    let confidenceLevel: HypnosisMetadata.ConfidenceLevel
    let confidenceRationale: String?
    let transitionTarget: HypnosisMetadata.Phase? // For transitional phases

    init(id: UUID = UUID(), phase: HypnosisMetadata.Phase, startTime: TimeInterval,
         endTime: TimeInterval, characteristics: String, tranceDepthEstimate: Double,
         linguisticMarkers: [LinguisticMarker] = [],
         confidenceLevel: HypnosisMetadata.ConfidenceLevel = .medium,
         confidenceRationale: String? = nil,
         transitionTarget: HypnosisMetadata.Phase? = nil) {
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

/// Linguistic markers detected in hypnotic language
struct LinguisticMarker: Codable, Identifiable {
    enum MarkerType: String, Codable {
        // Phase 0 - Pre-Talk markers
        case normalization
        case expectationSetting
        case rapportBuilding
        case suggestibilityTesting

        // Phase 1 - Induction markers
        case eyeFixation
        case breathingFocus
        case progressiveRelaxation
        case sensoryNarrowing
        case pacingExperience

        // Phase 2 - Deepening markers
        case countingDown
        case descendingImagery
        case fractionation
        case heavinessContrast
        case timeDistortion

        // Phase 3 - Therapeutic markers
        case directSuggestion
        case indirectSuggestion
        case metaphoricalStory
        case embeddedCommand
        case egoStrengthening
        case reframing
        case partsBased

        // Phase 4 - Conditioning markers
        case futurePacing
        case anchoringResponse
        case triggerInstallation
        case causeEffectFraming

        // Phase 5 - Emergence markers
        case countingUp
        case eyeOpening
        case physicalReengagement
        case temporalOrientation

        // Ericksonian patterns
        case pacingAndLeading
        case ambiguousLanguage
        case conversationalTrance
        case utilizationOfResponse
    }

    let id: UUID
    let type: MarkerType
    let timestamp: TimeInterval
    let textSnippet: String? // Brief example from transcript
    let strength: Double // 0.0-1.0, how strongly this marker is present

    init(id: UUID = UUID(), type: MarkerType, timestamp: TimeInterval,
         textSnippet: String? = nil, strength: Double = 1.0) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.textSnippet = textSnippet
        self.strength = strength
    }
}

/// Detected hypnotic technique with timing
struct HypnoticTechnique: Codable, Identifiable {
    let id: UUID
    let technique: String // e.g., "arm levitation", "eye catalepsy"
    let timestamp: TimeInterval
    let description: String
    let suggestedLightSync: String // how to sync lights with this technique

    init(id: UUID = UUID(), technique: String, timestamp: TimeInterval,
         description: String, suggestedLightSync: String) {
        self.id = id
        self.technique = technique
        self.timestamp = timestamp
        self.description = description
        self.suggestedLightSync = suggestedLightSync
    }
}

// MARK: - Temporal Analysis

/// Analysis of how content evolves over time
struct TemporalAnalysis: Codable {
    let tranceDepthCurve: [Double] // sampled at regular intervals (0.0-1.0)
    let receptivityLevels: [Double] // suggestion receptivity at intervals
    let emotionalArc: [String] // emotional descriptors at intervals
    let samplingInterval: TimeInterval // seconds between samples

    var durationCovered: TimeInterval {
        Double(tranceDepthCurve.count) * samplingInterval
    }
}

// MARK: - Voice Characteristics

/// Analysis of vocal delivery and prosody
struct VoiceCharacteristics: Codable {
    let averagePace: Double? // words per minute
    let paceVariation: Double? // variance in speaking rate
    let pausePatterns: [TimeInterval] // significant pauses
    let tonalQualities: [String] // "soothing", "authoritative", "rhythmic"
    let volumePattern: String? // "steady", "gradually quieter", "dynamic"
}

// MARK: - Classification Confidence

/// Confidence metrics for AI classification
struct ClassificationConfidence: Codable {
    let overallConfidence: Double // 0.0-1.0
    let isDefinitelyHypnosis: Bool
    let ambiguousSegments: [TimeInterval] // timestamps needing review
    let alternativeInterpretations: [String]
    let detectionCriteria: [String] // what led to classification
}

// MARK: - ClosedRange Codable Extension

extension ClosedRange: Codable where Bound: Codable & Comparable {
    enum CodingKeys: String, CodingKey {
        case lowerBound
        case upperBound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lower = try container.decode(Bound.self, forKey: .lowerBound)
        let upper = try container.decode(Bound.self, forKey: .upperBound)
        self = lower...upper
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lowerBound, forKey: .lowerBound)
        try container.encode(upperBound, forKey: .upperBound)
    }
}
