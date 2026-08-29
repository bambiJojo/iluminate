//
//  AnalysisPreferences.swift
//  Ilumionate
//
//  Persistent user preferences for the AI analysis pipeline and session generation.
//  Stored in UserDefaults; changes are applied immediately to subsequent analyses.
//

import Foundation
import Observation

// MARK: - Frequency Profile

enum FrequencyProfile: String, CaseIterable, Codable, Sendable {
    case conservative
    case standard
    case deep

    var displayName: String {
        switch self {
        case .conservative: "Conservative (0.5–15 Hz)"
        case .standard:     "Standard (0.5–30 Hz)"
        case .deep:         "Deep (0.5–40 Hz)"
        }
    }

    var description: String {
        switch self {
        case .conservative: "Gentle entrainment, ideal for beginners"
        case .standard:     "Full brainwave range for most content"
        case .deep:         "Extended range including gamma waves"
        }
    }

    var minFrequency: Double { 0.5 }

    var maxFrequency: Double {
        switch self {
        case .conservative: 15.0
        case .standard:     30.0
        case .deep:         40.0
        }
    }
}

// MARK: - Transition Style

enum TransitionStyle: String, CaseIterable, Codable, Sendable {
    case sharp
    case standard
    case fluid

    var displayName: String {
        switch self {
        case .sharp:    "Sharp"
        case .standard: "Standard"
        case .fluid:    "Fluid"
        }
    }

    var description: String {
        switch self {
        case .sharp:    "Abrupt transitions between states"
        case .standard: "Balanced transitions"
        case .fluid:    "Very smooth, barely perceptible changes"
        }
    }

    var smoothness: Double {
        switch self {
        case .sharp:    0.2
        case .standard: 0.8
        case .fluid:    1.0
        }
    }
}

// MARK: - Color Temperature Mode

enum ColorTempMode: String, CaseIterable, Codable, Sendable {
    case auto
    case warm
    case neutral
    case cool

    var displayName: String {
        switch self {
        case .auto:    "Auto"
        case .warm:    "Warm (2700K)"
        case .neutral: "Neutral (4000K)"
        case .cool:    "Cool (6000K)"
        }
    }

    var description: String {
        switch self {
        case .auto:    "Analysis selects the best temperature"
        case .warm:    "Relaxing, ideal for sleep & deep trance"
        case .neutral: "Balanced for general use"
        case .cool:    "Alerting, ideal for focus & energy"
        }
    }

    var kelvin: Double? {
        switch self {
        case .auto:    nil
        case .warm:    2700
        case .neutral: 4000
        case .cool:    6000
        }
    }
}

// MARK: - Content Hint

enum ContentHint: String, CaseIterable, Codable, Sendable {
    case none
    case hypnosis
    case eroticHypnosis
    case meditation
    case affirmation
    case sleepAid
    case energizing

    var displayName: String {
        switch self {
        case .none:        "Auto-detect"
        case .hypnosis:    "Hypnosis / Hypnotherapy"
        case .eroticHypnosis: "Erotic / Conditioning"
        case .meditation:  "Meditation / Mindfulness"
        case .affirmation: "Affirmations"
        case .sleepAid:    "Sleep Aid"
        case .energizing:  "Energizing / Focus"
        }
    }

    var sfSymbol: String {
        switch self {
        case .none:        "wand.and.sparkles"
        case .hypnosis:    "eye.fill"
        case .eroticHypnosis: "sparkles"
        case .meditation:  "leaf.fill"
        case .affirmation: "quote.bubble.fill"
        case .sleepAid:    "moon.fill"
        case .energizing:  "bolt.fill"
        }
    }

    var aiHint: String? {
        switch self {
        case .none: nil
        case .hypnosis:
            "This content is likely hypnosis or hypnotherapy. Pay close attention to " +
            "induction language, deepening techniques, post-hypnotic suggestions, and emergence cues."
        case .eroticHypnosis:
            "This content is likely erotic hypnosis or conditioning. Pay close attention to " +
            "suggestion-work, trigger conditioning, brainwashing-style language, and emergence cues."
        case .meditation:
            "This content is a guided meditation. Focus on breath phases, body scans, " +
            "visualization stages, and transitions between awareness states."
        case .affirmation:
            "This content contains affirmations. Optimize light patterns for the " +
            "repetitive, suggestion-based rhythm of affirmation delivery."
        case .sleepAid:
            "This content is designed to aid sleep. Bias recommendations toward slow " +
            "delta frequencies (0.5–4 Hz), low intensity, and warm color temperatures."
        case .energizing:
            "This content is energizing or focus-oriented. Bias toward beta frequencies " +
            "(14–30 Hz), higher intensity, and cooler color temperatures."
        }
    }
}

// MARK: - Analysis Preferences

/// Persistent preferences for the AI analysis pipeline and session generation.
/// All changes are saved to UserDefaults immediately via `didSet` observers.
@MainActor @Observable
final class AnalysisPreferences {
    struct Snapshot: Codable, Sendable {
        let contentHint: ContentHint
        let corpusSourceProfile: CorpusSourceProfile
        let customInstructions: String
        let intensityMultiplier: Double
        let frequencyProfile: FrequencyProfile
        let transitionStyle: TransitionStyle
        let colorTempMode: ColorTempMode
        let bilateralMode: Bool
        let autoAnalyzeOnImport: Bool

        init(
            contentHint: ContentHint,
            corpusSourceProfile: CorpusSourceProfile = .general,
            customInstructions: String,
            intensityMultiplier: Double,
            frequencyProfile: FrequencyProfile,
            transitionStyle: TransitionStyle,
            colorTempMode: ColorTempMode,
            bilateralMode: Bool,
            autoAnalyzeOnImport: Bool
        ) {
            self.contentHint = contentHint
            self.corpusSourceProfile = corpusSourceProfile
            self.customInstructions = customInstructions
            self.intensityMultiplier = intensityMultiplier
            self.frequencyProfile = frequencyProfile
            self.transitionStyle = transitionStyle
            self.colorTempMode = colorTempMode
            self.bilateralMode = bilateralMode
            self.autoAnalyzeOnImport = autoAnalyzeOnImport
        }

        private enum CodingKeys: String, CodingKey {
            case contentHint
            case corpusSourceProfile
            case customInstructions
            case intensityMultiplier
            case frequencyProfile
            case transitionStyle
            case colorTempMode
            case bilateralMode
            case autoAnalyzeOnImport
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            contentHint = try container.decode(ContentHint.self, forKey: .contentHint)
            corpusSourceProfile = try container.decodeIfPresent(
                CorpusSourceProfile.self,
                forKey: .corpusSourceProfile
            ) ?? .general
            customInstructions = try container.decode(String.self, forKey: .customInstructions)
            intensityMultiplier = try container.decode(Double.self, forKey: .intensityMultiplier)
            frequencyProfile = try container.decode(FrequencyProfile.self, forKey: .frequencyProfile)
            transitionStyle = try container.decode(TransitionStyle.self, forKey: .transitionStyle)
            colorTempMode = try container.decode(ColorTempMode.self, forKey: .colorTempMode)
            bilateralMode = try container.decode(Bool.self, forKey: .bilateralMode)
            autoAnalyzeOnImport = try container.decode(Bool.self, forKey: .autoAnalyzeOnImport)
        }
    }

    static let shared = AnalysisPreferences()

    // MARK: - AI Analysis

    var contentHint: ContentHint {
        didSet { UserDefaults.standard.set(contentHint.rawValue, forKey: Keys.contentHint) }
    }

    var corpusSourceProfile: CorpusSourceProfile {
        didSet { UserDefaults.standard.set(corpusSourceProfile.rawValue, forKey: CorpusSourceProfile.userDefaultsKey) }
    }

    var customInstructions: String {
        didSet { UserDefaults.standard.set(customInstructions, forKey: Keys.customInstructions) }
    }

    // MARK: - Session Generation

    var intensityMultiplier: Double {
        didSet { UserDefaults.standard.set(intensityMultiplier, forKey: Keys.intensity) }
    }

    var frequencyProfile: FrequencyProfile {
        didSet { UserDefaults.standard.set(frequencyProfile.rawValue, forKey: Keys.frequencyProfile) }
    }

    var transitionStyle: TransitionStyle {
        didSet { UserDefaults.standard.set(transitionStyle.rawValue, forKey: Keys.transitionStyle) }
    }

    var colorTempMode: ColorTempMode {
        didSet { UserDefaults.standard.set(colorTempMode.rawValue, forKey: Keys.colorTemp) }
    }

    var bilateralMode: Bool {
        didSet { UserDefaults.standard.set(bilateralMode, forKey: Keys.bilateral) }
    }

    // MARK: - Behavior

    var autoAnalyzeOnImport: Bool {
        didSet { UserDefaults.standard.set(autoAnalyzeOnImport, forKey: Keys.autoAnalyze) }
    }

    // MARK: - Derived Values

    /// Maps current preferences to a `SessionGenerator.GenerationConfig`.
    var generationConfig: SessionGenerator.GenerationConfig {
        SessionGenerator.GenerationConfig(
            intensityMultiplier: intensityMultiplier,
            minFrequency: frequencyProfile.minFrequency,
            maxFrequency: frequencyProfile.maxFrequency,
            transitionSmoothness: transitionStyle.smoothness,
            colorTemperatureOverride: colorTempMode.kelvin,
            bilateralMode: bilateralMode
        )
    }

    var snapshot: Snapshot {
        Snapshot(
            contentHint: contentHint,
            corpusSourceProfile: corpusSourceProfile,
            customInstructions: customInstructions,
            intensityMultiplier: intensityMultiplier,
            frequencyProfile: frequencyProfile,
            transitionStyle: transitionStyle,
            colorTempMode: colorTempMode,
            bilateralMode: bilateralMode,
            autoAnalyzeOnImport: autoAnalyzeOnImport
        )
    }

    func applyingUserOverrides(
        to baseConfig: SessionGenerator.GenerationConfig
    ) -> SessionGenerator.GenerationConfig {
        var config = baseConfig
        config.intensityMultiplier = intensityMultiplier
        config.minFrequency = frequencyProfile.minFrequency
        config.maxFrequency = frequencyProfile.maxFrequency
        config.transitionSmoothness = transitionStyle.smoothness
        if colorTempMode != .auto {
            config.colorTemperatureOverride = colorTempMode.kelvin
        }
        config.bilateralMode = bilateralMode
        return config
    }

    /// Additional context appended to the AI system prompt based on user preferences.
    var aiSystemAddendum: String {
        var parts: [String] = []
        if let hint = contentHint.aiHint {
            parts.append(hint)
        }
        if corpusSourceProfile == .eroticConditioning {
            parts.append("Use adult conditioning corpus cues when the transcript structurally supports erotic hypnosis, brainwashing, or trigger conditioning phases.")
        } else if corpusSourceProfile == .therapeutic {
            parts.append("Suppress adult conditioning source-pack cues unless the transcript explicitly requires that domain.")
        }
        if !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Additional user instructions: \(customInstructions)")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Private

    private enum Keys {
        static let contentHint       = "analysisPref_contentHint"
        static let customInstructions = "analysisPref_customInstructions"
        static let intensity         = "analysisPref_intensity"
        static let frequencyProfile  = "analysisPref_frequencyProfile"
        static let transitionStyle   = "analysisPref_transitionStyle"
        static let colorTemp         = "analysisPref_colorTemp"
        static let bilateral         = "analysisPref_bilateral"
        static let autoAnalyze       = "analysisPref_autoAnalyze"
    }

    private init() {
        let d = UserDefaults.standard
        contentHint = ContentHint(rawValue: d.string(forKey: Keys.contentHint) ?? "") ?? .none
        corpusSourceProfile = CorpusSourceProfile.storedSelection(defaults: d) ?? .general
        customInstructions = d.string(forKey: Keys.customInstructions) ?? ""
        intensityMultiplier = d.object(forKey: Keys.intensity) as? Double ?? 1.0
        frequencyProfile = FrequencyProfile(rawValue: d.string(forKey: Keys.frequencyProfile) ?? "") ?? .standard
        transitionStyle = TransitionStyle(rawValue: d.string(forKey: Keys.transitionStyle) ?? "") ?? .standard
        colorTempMode = ColorTempMode(rawValue: d.string(forKey: Keys.colorTemp) ?? "") ?? .auto
        bilateralMode = d.bool(forKey: Keys.bilateral)
        // Default autoAnalyze to true on first launch
        if d.object(forKey: Keys.autoAnalyze) == nil {
            autoAnalyzeOnImport = true
        } else {
            autoAnalyzeOnImport = d.bool(forKey: Keys.autoAnalyze)
        }
    }

    func resetToDefaults() {
        contentHint = .none
        corpusSourceProfile = .general
        customInstructions = ""
        intensityMultiplier = 1.0
        frequencyProfile = .standard
        transitionStyle = .standard
        colorTempMode = .auto
        bilateralMode = false
        autoAnalyzeOnImport = true
    }
}
