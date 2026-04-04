//
//  AudioFile.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation

/// Multi-dimensional rating system for hypno audio
struct DetailedRating: Codable, Sendable, Equatable {
    var effectiveness: Int // How effective was the session? (1-5)
    var relaxation: Int // How relaxing was it? (1-5)
    var voiceQuality: Int // Voice quality/delivery (1-5)
    var notes: String? // Quick notes like "Great for sleep", "Too fast"
    var ratedDate: Date

    var overallRating: Int {
        Int(round(Double(effectiveness + relaxation + voiceQuality) / 3.0))
    }

    init(effectiveness: Int = 0, relaxation: Int = 0, voiceQuality: Int = 0, notes: String? = nil, ratedDate: Date = Date()) {
        self.effectiveness = effectiveness
        self.relaxation = relaxation
        self.voiceQuality = voiceQuality
        self.notes = notes
        self.ratedDate = ratedDate
    }
}

/// Represents an audio file that can be used for session generation
struct AudioFile: Identifiable, Codable, Sendable {
    let id: UUID
    var filename: String
    let duration: TimeInterval
    let fileSize: Int64
    let createdDate: Date

    var transcription: String?
    var analysisResult: AnalysisResult?
    var deadTimeProfile: DeadTimeProfile?

    // User Organization Data
    var creator: String? // Voice/narrator/hypnotist name for grouping in Library
    var isFavorite: Bool?
    var rating: Int? // 0 to 5 (legacy - kept for compatibility)
    var detailedRating: DetailedRating?
    var tags: [String]?
    var lastPlayedDate: Date?
    var playCount: Int?
    var sessionNotes: String? // User notes about the session

    // Computed from filename so the URL is always valid after app updates.
    // iOS sandbox container paths include a dynamic UUID that changes on update;
    // storing only the filename and reconstructing the URL at runtime avoids stale paths.
    nonisolated var url: URL { URL.documentsDirectory.appending(path: filename) }

    // Exclude `url` from serialization — it is always derived from `filename`.
    // Old stored data may contain a `url` field; Codable ignores unknown keys.
    enum CodingKeys: String, CodingKey {
        case id, filename, duration, fileSize, createdDate
        case transcription, analysisResult, deadTimeProfile
        case creator, isFavorite, rating, detailedRating, tags
        case lastPlayedDate, playCount, sessionNotes
    }

    init(id: UUID = UUID(), filename: String, duration: TimeInterval,
         fileSize: Int64, createdDate: Date = Date(),
         isFavorite: Bool? = nil, rating: Int? = nil, tags: [String]? = nil,
         lastPlayedDate: Date? = nil, playCount: Int? = nil) {
        self.id = id
        self.filename = filename
        self.duration = duration
        self.fileSize = fileSize
        self.createdDate = createdDate
        self.isFavorite = isFavorite
        self.rating = rating
        self.tags = tags
        self.lastPlayedDate = lastPlayedDate
        self.playCount = playCount
    }

    // MARK: - Computed Properties

    var durationFormatted: String {
        Duration.seconds(duration).formatted(.time(pattern: .minuteSecond))
    }

    var fileSizeFormatted: String {
        fileSize.formatted(.byteCount(style: .file))
    }

    var isAnalyzed: Bool {
        analysisResult != nil
    }

    var hasTranscription: Bool {
        transcription != nil && !(transcription?.isEmpty ?? true)
    }

    var displayName: String {
        URL(filePath: filename).deletingPathExtension().lastPathComponent
    }
    
    // Safe accessors for optional user data
    var favorite: Bool { isFavorite ?? false }
    var userRating: Int {
        detailedRating?.overallRating ?? rating ?? 0
    }
    var userTags: [String] { tags ?? [] }
    var effectivenessRating: Int { detailedRating?.effectiveness ?? 0 }
    var relaxationRating: Int { detailedRating?.relaxation ?? 0 }
    var voiceQualityRating: Int { detailedRating?.voiceQuality ?? 0 }
}

extension AudioFile: Equatable {
    static func == (lhs: AudioFile, rhs: AudioFile) -> Bool {
        lhs.id == rhs.id &&
        lhs.filename == rhs.filename &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.rating == rhs.rating &&
        lhs.detailedRating == rhs.detailedRating &&
        lhs.tags == rhs.tags &&
        lhs.creator == rhs.creator &&
        lhs.lastPlayedDate == rhs.lastPlayedDate &&
        lhs.playCount == rhs.playCount &&
        lhs.sessionNotes == rhs.sessionNotes
    }
}

extension AudioFile: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Results from AI audio analysis
struct AnalysisResult: Codable, Sendable {
    enum Mood: String, Codable, Sendable {
        case relaxing
        case energizing
        case neutral
        case meditative
        case uplifting
        case melancholic
    }

    typealias ContentType = AudioContentType

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
    var voiceCharacteristics: VoiceCharacteristics?
    let classificationConfidence: ClassificationConfidence?
    var prosodicProfile: ProsodicProfile?
    var techniqueDetection: TechniqueDetectionResult?

    nonisolated init(mood: Mood, energyLevel: Double, suggestedFrequencyRange: ClosedRange<Double>,
         suggestedIntensity: Double, suggestedColorTemperature: Double? = nil,
         keyMoments: [KeyMoment], aiSummary: String, recommendedPreset: String,
         contentType: ContentType = .unknown,
         hypnosisMetadata: HypnosisMetadata? = nil,
         temporalAnalysis: TemporalAnalysis? = nil,
         voiceCharacteristics: VoiceCharacteristics? = nil,
         classificationConfidence: ClassificationConfidence? = nil,
         prosodicProfile: ProsodicProfile? = nil,
         techniqueDetection: TechniqueDetectionResult? = nil) {
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
        self.prosodicProfile = prosodicProfile
        self.techniqueDetection = techniqueDetection
    }
}

/// Represents a significant moment in the audio
struct KeyMoment: Codable, Identifiable, Sendable {
    let id: UUID
    let time: TimeInterval
    let description: String
    let action: LightAction

    nonisolated init(id: UUID = UUID(), time: TimeInterval, description: String, action: LightAction) {
        self.id = id
        self.time = time
        self.description = description
        self.action = action
    }
}

// MARK: - Hypnosis-Specific Metadata

/// Detailed hypnosis session analysis
struct HypnosisMetadata: Codable, Sendable {
    typealias Phase = TrancePhase

    enum ConfidenceLevel: String, Codable, Sendable {
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

    enum InductionStyle: String, Codable, Sendable {
        case progressive
        case authoritarian
        case permissive
        case confusion
        case rapid
        case ericksonian
        case conversational
    }

    enum TranceDeph: String, Codable, Sendable {
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
struct PhaseSegment: Codable, Identifiable, Sendable {
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
struct LinguisticMarker: Codable, Identifiable, Sendable {
    enum MarkerType: String, Codable, Sendable {
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

        // Advanced technique markers
        case confusionTechnique
        case amnesiaSuggestion
        case doubleBinding
        case dissociation
        case ageRegression
        case hallucination
        case brainwashing
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
struct HypnoticTechnique: Codable, Identifiable, Sendable {
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

// MARK: - Prosodic Profile

/// How a pause in the audio should be categorized for light response decisions.
enum PauseCategory: String, Codable, Sendable {
    /// Normal speech breathing pause (1–3 s) — maintain current light state.
    case natural
    /// Intentional therapeutic pause (3–8 s) — gentle frequency dip.
    case deliberate
    /// Extended silence with music/tones only (>5 s) — switch to energy-following mode.
    case musicOnly
    /// Pure silence (>3 s, no audio at all) — maintain and slightly deepen.
    case silence
}

/// A detected pause in the audio timeline with surrounding context.
struct DetectedPause: Codable, Sendable, Identifiable {
    let id: UUID
    let startTime: TimeInterval
    let duration: TimeInterval
    let precedingText: String?
    let followingText: String?
    let category: PauseCategory

    init(id: UUID = UUID(), startTime: TimeInterval, duration: TimeInterval,
         precedingText: String? = nil, followingText: String? = nil,
         category: PauseCategory = .natural) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.precedingText = precedingText
        self.followingText = followingText
        self.category = category
    }
}

/// Audio-level prosodic features extracted from the raw audio signal and
/// WhisperKit transcript timing. All curves are sampled at `windowDuration`
/// intervals aligned to the start of the audio.
struct ProsodicProfile: Codable, Sendable {
    /// Duration of each analysis window in seconds (typically 3.0).
    let windowDuration: TimeInterval

    /// Words per minute in each window (0 when no speech detected).
    let speechRateCurve: [Double]

    /// Normalised RMS energy per window (0.0–1.0).
    let volumeCurve: [Double]

    /// Estimated fundamental frequency (F0) in Hz per window.
    /// 0 means no voiced speech was detected in that window.
    let pitchCurve: [Double]

    /// Fraction of each window containing speech vs silence (0.0–1.0).
    let speechSilenceRatio: [Double]

    /// All detected pauses with context and categorisation.
    let pauses: [DetectedPause]

    /// Total duration of the analysed audio.
    let totalDuration: TimeInterval

    // MARK: - Convenience

    /// Average speech rate across windows that contain speech.
    var averageSpeechRate: Double {
        let speaking = speechRateCurve.filter { $0 > 0 }
        guard !speaking.isEmpty else { return 0 }
        return speaking.reduce(0, +) / Double(speaking.count)
    }

    /// Standard deviation of speech rate across spoken windows.
    var speechRateVariance: Double {
        let speaking = speechRateCurve.filter { $0 > 0 }
        guard speaking.count > 1 else { return 0 }
        let mean = speaking.reduce(0, +) / Double(speaking.count)
        let sumSquaredDiff = speaking.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sumSquaredDiff / Double(speaking.count)).squareRoot()
    }

    /// Average pitch across windows that contain voiced speech.
    var averagePitch: Double {
        let voiced = pitchCurve.filter { $0 > 0 }
        guard !voiced.isEmpty else { return 0 }
        return voiced.reduce(0, +) / Double(voiced.count)
    }

    /// Speech rate at a specific time, clamped to nearest window.
    func speechRate(at time: TimeInterval) -> Double {
        let idx = Int(time / windowDuration)
        guard idx >= 0, idx < speechRateCurve.count else { return averageSpeechRate }
        return speechRateCurve[idx]
    }

    /// Volume at a specific time, clamped to nearest window.
    func volume(at time: TimeInterval) -> Double {
        let idx = Int(time / windowDuration)
        guard idx >= 0, idx < volumeCurve.count else { return 0.5 }
        return volumeCurve[idx]
    }

    /// Pitch at a specific time, clamped to nearest window.
    func pitch(at time: TimeInterval) -> Double {
        let idx = Int(time / windowDuration)
        guard idx >= 0, idx < pitchCurve.count else { return 0 }
        return pitchCurve[idx]
    }

    /// Speech-to-silence ratio at a specific time.
    func speechRatio(at time: TimeInterval) -> Double {
        let idx = Int(time / windowDuration)
        guard idx >= 0, idx < speechSilenceRatio.count else { return 0.5 }
        return speechSilenceRatio[idx]
    }
}

// MARK: - Temporal Analysis

/// Analysis of how content evolves over time
struct TemporalAnalysis: Codable, Sendable {
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
struct VoiceCharacteristics: Codable, Sendable {
    let averagePace: Double? // words per minute
    let paceVariation: Double? // variance in speaking rate
    let pausePatterns: [TimeInterval] // significant pauses
    let tonalQualities: [String] // "soothing", "authoritative", "rhythmic"
    let volumePattern: String? // "steady", "gradually quieter", "dynamic"
}

// MARK: - Classification Confidence

/// Confidence metrics for AI classification
struct ClassificationConfidence: Codable, Sendable {
    let overallConfidence: Double // 0.0-1.0
    let isDefinitelyHypnosis: Bool
    let ambiguousSegments: [TimeInterval] // timestamps needing review
    let alternativeInterpretations: [String]
    let detectionCriteria: [String] // what led to classification
}

