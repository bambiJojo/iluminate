//
//  AudioFile.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/10/26.
//

import Foundation

/// Multi-dimensional rating system for hypno audio
nonisolated struct DetailedRating: Codable, Sendable, Equatable {
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
nonisolated struct AudioFile: Identifiable, Codable, Sendable {
    let id: UUID
    var filename: String
    let duration: TimeInterval
    let fileSize: Int64
    let createdDate: Date
    var contentFingerprint: String?
    /// Set when the file was fetched from a publisher rather than imported by
    /// the user. Optional so every previously stored library decodes unchanged.
    var remoteSource: RemoteAudioSource?

    var transcription: String?
    var analysisResult: AnalysisResult?
    var deadTimeProfile: DeadTimeProfile?
    var trackMetadata: AudioTrackMetadata?
    var userTitle: String?

    // User Organization Data
    var creator: String? // Voice/narrator/hypnotist name for grouping in Library
    var isFavorite: Bool?
    var rating: Int? // 0 to 5 (legacy - kept for compatibility)
    var detailedRating: DetailedRating?
    var tags: [String]?
    var lastPlayedDate: Date?
    var playCount: Int?
    var sessionNotes: String? // User notes about the session

    // Library files are typically stored relative to Documents, but training and
    // migration flows can hand us an absolute path that should be preserved.
    nonisolated var url: URL {
        if filename.hasPrefix("/") {
            return URL(filePath: filename).standardizedFileURL
        }
        return URL.documentsDirectory.appending(path: filename)
    }

    // Exclude `url` from serialization — it is always derived from `filename`.
    // Old stored data may contain a `url` field; Codable ignores unknown keys.
    enum CodingKeys: String, CodingKey {
        case id, filename, duration, fileSize, createdDate, contentFingerprint
        case remoteSource
        case transcription, analysisResult, deadTimeProfile
        case trackMetadata, userTitle
        case creator, isFavorite, rating, detailedRating, tags
        case lastPlayedDate, playCount, sessionNotes
    }

    init(id: UUID = UUID(), filename: String, duration: TimeInterval,
         fileSize: Int64, createdDate: Date = Date(),
         isFavorite: Bool? = nil, rating: Int? = nil, tags: [String]? = nil,
         lastPlayedDate: Date? = nil, playCount: Int? = nil,
         trackMetadata: AudioTrackMetadata? = nil, userTitle: String? = nil,
         contentFingerprint: String? = nil,
         remoteSource: RemoteAudioSource? = nil) {
        self.id = id
        self.filename = filename
        self.duration = duration
        self.fileSize = fileSize
        self.createdDate = createdDate
        self.contentFingerprint = contentFingerprint
        self.remoteSource = remoteSource
        self.isFavorite = isFavorite
        self.rating = rating
        self.tags = tags
        self.lastPlayedDate = lastPlayedDate
        self.playCount = playCount
        self.trackMetadata = trackMetadata
        self.userTitle = userTitle
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
        AudioTrackMetadata.cleaned(userTitle)
            ?? trackMetadata?.preferredTitle
            ?? URL(filePath: filename).deletingPathExtension().lastPathComponent
    }

    var creatorDisplayName: String? {
        AudioTrackMetadata.cleaned(creator) ?? trackMetadata?.creator
    }

    var discoveredThemes: [String] {
        trackMetadata?.themes ?? []
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
    /// Field-wise rather than identity-only, because SwiftUI diffs on this:
    /// narrowing it to `id` would stop rows refreshing when a rating or title
    /// changes in place.
    ///
    /// The two identity fields are included so that values differing only in
    /// which audio they refer to never compare equal — `PlaylistTrackDownloadOutcome`
    /// wraps an `AudioFile` and is `Equatable`, and without these a downloaded
    /// file and a different one with the same metadata were indistinguishable.
    static func == (lhs: AudioFile, rhs: AudioFile) -> Bool {
        lhs.id == rhs.id &&
        lhs.contentFingerprint == rhs.contentFingerprint &&
        lhs.remoteSource == rhs.remoteSource &&
        lhs.filename == rhs.filename &&
        lhs.isFavorite == rhs.isFavorite &&
        lhs.rating == rhs.rating &&
        lhs.detailedRating == rhs.detailedRating &&
        lhs.tags == rhs.tags &&
        lhs.creator == rhs.creator &&
        lhs.lastPlayedDate == rhs.lastPlayedDate &&
        lhs.playCount == rhs.playCount &&
        lhs.sessionNotes == rhs.sessionNotes &&
        lhs.trackMetadata == rhs.trackMetadata &&
        lhs.userTitle == rhs.userTitle
    }
}

extension AudioFile: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Results from AI audio analysis
nonisolated struct AnalysisResult: Codable, Sendable {
    nonisolated enum Mood: String, Codable, Sendable {
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
    let expertAnalysis: ExpertAnalysis?
    var prosodicProfile: ProsodicProfile?
    var techniqueDetection: TechniqueDetectionResult?
    var transcriptAnalysis: TranscriptAnalysis?
    let discoveredMetadata: AudioTrackMetadata?

    nonisolated init(mood: Mood, energyLevel: Double, suggestedFrequencyRange: ClosedRange<Double>,
         suggestedIntensity: Double, suggestedColorTemperature: Double? = nil,
         keyMoments: [KeyMoment], aiSummary: String, recommendedPreset: String,
         contentType: ContentType = .unknown,
         hypnosisMetadata: HypnosisMetadata? = nil,
         temporalAnalysis: TemporalAnalysis? = nil,
         voiceCharacteristics: VoiceCharacteristics? = nil,
         classificationConfidence: ClassificationConfidence? = nil,
         expertAnalysis: ExpertAnalysis? = nil,
         prosodicProfile: ProsodicProfile? = nil,
         techniqueDetection: TechniqueDetectionResult? = nil,
         transcriptAnalysis: TranscriptAnalysis? = nil,
         discoveredMetadata: AudioTrackMetadata? = nil) {
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
        self.expertAnalysis = expertAnalysis
        self.prosodicProfile = prosodicProfile
        self.techniqueDetection = techniqueDetection
        self.transcriptAnalysis = transcriptAnalysis
        self.discoveredMetadata = discoveredMetadata
    }
}

/// Expert-level diagnostics explaining how trustworthy the analyzer output is
/// and where future analyzer or label-review work should focus.
nonisolated struct ExpertAnalysis: Codable, Sendable {
    nonisolated enum Verdict: String, Codable, Sendable {
        case productionReady
        case reviewRecommended
        case needsRelabeling

        var displayName: String {
            switch self {
            case .productionReady: return "Production Ready"
            case .reviewRecommended: return "Review Recommended"
            case .needsRelabeling: return "Needs Relabeling"
            }
        }
    }

    nonisolated enum Severity: String, Codable, Sendable {
        case info
        case warning
        case critical
    }

    nonisolated struct Finding: Codable, Identifiable, Sendable {
        let id: UUID
        let title: String
        let detail: String
        let severity: Severity

        init(id: UUID = UUID(), title: String, detail: String, severity: Severity) {
            self.id = id
            self.title = title
            self.detail = detail
            self.severity = severity
        }
    }

    nonisolated struct ImprovementAction: Codable, Identifiable, Sendable {
        let id: UUID
        let priority: Int
        let title: String
        let detail: String

        init(id: UUID = UUID(), priority: Int, title: String, detail: String) {
            self.id = id
            self.priority = priority
            self.title = title
            self.detail = detail
        }
    }

    nonisolated struct ReviewMoment: Codable, Identifiable, Sendable {
        let id: UUID
        let time: TimeInterval
        let phase: HypnosisMetadata.Phase?
        let reason: String

        init(id: UUID = UUID(), time: TimeInterval, phase: HypnosisMetadata.Phase?, reason: String) {
            self.id = id
            self.time = time
            self.phase = phase
            self.reason = reason
        }
    }

    let qualityScore: Double
    let verdict: Verdict
    let summary: String
    let findings: [Finding]
    let improvementActions: [ImprovementAction]
    let reviewMoments: [ReviewMoment]
}

/// Represents a significant moment in the audio
nonisolated struct KeyMoment: Codable, Identifiable, Sendable {
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
nonisolated struct HypnosisMetadata: Codable, Sendable {
    typealias Phase = TrancePhase

    nonisolated enum ConfidenceLevel: String, Codable, Sendable {
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

    nonisolated enum InductionStyle: String, Codable, Sendable {
        case progressive
        case authoritarian
        case permissive
        case confusion
        case rapid
        case ericksonian
        case conversational
    }

    nonisolated enum TranceDeph: String, Codable, Sendable {
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

    init(
        phases: [PhaseSegment],
        inductionStyle: InductionStyle?,
        estimatedTranceDeph: TranceDeph,
        suggestionDensity: Double?,
        languagePatterns: [String],
        detectedTechniques: [HypnoticTechnique]
    ) {
        self.phases = PhaseSegment.ensuringUniqueIDs(in: phases)
        self.inductionStyle = inductionStyle
        self.estimatedTranceDeph = estimatedTranceDeph
        self.suggestionDensity = suggestionDensity
        self.languagePatterns = languagePatterns
        self.detectedTechniques = detectedTechniques
    }

    private enum CodingKeys: String, CodingKey {
        case phases
        case inductionStyle
        case estimatedTranceDeph
        case suggestionDensity
        case languagePatterns
        case detectedTechniques
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            phases: try container.decode([PhaseSegment].self, forKey: .phases),
            inductionStyle: try container.decodeIfPresent(InductionStyle.self, forKey: .inductionStyle),
            estimatedTranceDeph: try container.decode(TranceDeph.self, forKey: .estimatedTranceDeph),
            suggestionDensity: try container.decodeIfPresent(Double.self, forKey: .suggestionDensity),
            languagePatterns: try container.decode([String].self, forKey: .languagePatterns),
            detectedTechniques: try container.decode([HypnoticTechnique].self, forKey: .detectedTechniques)
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phases, forKey: .phases)
        try container.encodeIfPresent(inductionStyle, forKey: .inductionStyle)
        try container.encode(estimatedTranceDeph, forKey: .estimatedTranceDeph)
        try container.encodeIfPresent(suggestionDensity, forKey: .suggestionDensity)
        try container.encode(languagePatterns, forKey: .languagePatterns)
        try container.encode(detectedTechniques, forKey: .detectedTechniques)
    }
}

/// A phase segment within a hypnosis session
nonisolated struct PhaseSegment: Codable, Identifiable, Sendable {
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

    /// Preserves the first occurrence of an identity and repairs duplicates
    /// introduced when one analyzed segment is split into several timeline pieces.
    static func ensuringUniqueIDs(in segments: [PhaseSegment]) -> [PhaseSegment] {
        var seen = Set<UUID>()
        return segments.map { segment in
            guard seen.insert(segment.id).inserted == false else { return segment }
            return PhaseSegment(
                phase: segment.phase,
                startTime: segment.startTime,
                endTime: segment.endTime,
                characteristics: segment.characteristics,
                tranceDepthEstimate: segment.tranceDepthEstimate,
                linguisticMarkers: segment.linguisticMarkers,
                confidenceLevel: segment.confidenceLevel,
                confidenceRationale: segment.confidenceRationale,
                transitionTarget: segment.transitionTarget
            )
        }
    }
}

/// Linguistic markers detected in hypnotic language
nonisolated struct LinguisticMarker: Codable, Identifiable, Sendable {
    nonisolated enum MarkerType: String, Codable, Sendable {
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
nonisolated struct HypnoticTechnique: Codable, Identifiable, Sendable {
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
nonisolated enum PauseCategory: String, Codable, Sendable {
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
nonisolated struct DetectedPause: Codable, Sendable, Identifiable {
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
nonisolated struct ProsodicProfile: Codable, Sendable {
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
nonisolated struct TemporalAnalysis: Codable, Sendable {
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
nonisolated struct VoiceCharacteristics: Codable, Sendable {
    let averagePace: Double? // words per minute
    let paceVariation: Double? // variance in speaking rate
    let pausePatterns: [TimeInterval] // significant pauses
    let tonalQualities: [String] // "soothing", "authoritative", "rhythmic"
    let volumePattern: String? // "steady", "gradually quieter", "dynamic"
}

// MARK: - Classification Confidence

/// Confidence metrics for AI classification
nonisolated struct ClassificationConfidence: Codable, Sendable {
    let overallConfidence: Double // 0.0-1.0
    let isDefinitelyHypnosis: Bool
    let ambiguousSegments: [TimeInterval] // timestamps needing review
    let alternativeInterpretations: [String]
    let detectionCriteria: [String] // what led to classification
}
