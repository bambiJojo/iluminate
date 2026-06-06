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

    nonisolated var url: URL {
        if filename.hasPrefix("/") {
            return URL(filePath: filename).standardizedFileURL
        }
        return URL.documentsDirectory.appending(path: filename)
    }
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
        case normalization
        case expectationSetting
        case rapportBuilding
        case suggestibilityTesting
        case eyeFixation
        case breathingFocus
        case progressiveRelaxation
        case sensoryNarrowing
        case pacingExperience
        case countingDown
        case descendingImagery
        case fractionation
        case heavinessContrast
        case timeDistortion
        case directSuggestion
        case indirectSuggestion
        case metaphoricalStory
        case embeddedCommand
        case egoStrengthening
        case reframing
        case partsBased
        case futurePacing
        case anchoringResponse
        case triggerInstallation
        case causeEffectFraming
        case countingUp
        case eyeOpening
        case physicalReengagement
        case temporalOrientation
        case pacingAndLeading
        case ambiguousLanguage
        case conversationalTrance
        case utilizationOfResponse
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
    let textSnippet: String?
    let strength: Double

    init(
        id: UUID = UUID(),
        type: MarkerType,
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

struct HypnoticTechnique: Codable, Identifiable, Sendable {
    let id: UUID
    let technique: String
    let timestamp: TimeInterval
    let description: String
    let suggestedLightSync: String

    init(
        id: UUID = UUID(),
        technique: String,
        timestamp: TimeInterval,
        description: String,
        suggestedLightSync: String
    ) {
        self.id = id
        self.technique = technique
        self.timestamp = timestamp
        self.description = description
        self.suggestedLightSync = suggestedLightSync
    }
}

struct TechniqueDetectionResult: Codable, Sendable {
    let techniques: [HypnoticTechnique]
    let markers: [LinguisticMarker]

    var sortedTechniques: [HypnoticTechnique] {
        techniques.sorted { $0.timestamp < $1.timestamp }
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
