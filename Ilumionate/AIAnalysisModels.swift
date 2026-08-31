//
//  AIAnalysisModels.swift
//  Ilumionate
//
//  Foundation Models structured-output types and the AVE system prompt used by
//  AIAnalysisManager. Kept in a separate file to keep the actor under the
//  SwiftLint type_body_length limit.
//

import Foundation
import FoundationModels

// MARK: - AVE System Prompt

/// Structural system prompt for the Foundation Models session.
/// Accurate pacing and hypnosis-phase detection improve classification and
/// keep generated light changes aligned with the source audio.
nonisolated enum AVESystemPrompt {

    /// Compact instructions for transcript classification.
    /// Covers the decisions the structured-output schema requires while leaving
    /// enough context for the generated response itself.
    static let minimalInstructions = """
    You classify audio content for a synchronized light-pattern system.
    Also create a concise, specific library title and 1–6 short themes. Only name a creator when supported by the filename, embedded context, or transcript; otherwise return an empty creator.
    Content types: hypnosis, meditation, music, guidedImagery, affirmations, unknown.
    Default visual-pattern ranges: hypnosis 0.7–1.8 Hz, meditation 0.8–1.6 Hz,
    music 1.5–3 Hz, affirmations 1.2–2 Hz. Never exceed 3 Hz. These are
    media-control parameters only.
    Phases (hypnosis only): pre_talk, induction, deepening, therapy, suggestions, erotic_suggestions, brainwashing, post_hypnotic_conditioning, emergence.
    Techniques/modifiers, not phases: fractionation, confusion.
    Color temperature: deep states 2200–2800 K, alpha 3000–4000 K, alert 4500–6500 K.
    """

    static let instructions = """
    You analyze audio structure for a system that renders synchronized light patterns.
    Treat frequency, intensity, and colour temperature strictly as visual control
    parameters. Do not make medical, therapeutic, neurological, sleep, stress, mood,
    cognition, performance, or other health-outcome claims.

    LIGHT-PATTERN RATE BANDS:
    • 0.5–1 Hz: very slow pulses
    • 1–1.5 Hz: slow pulses
    • 1.5–2 Hz: medium pulses
    • 2–2.5 Hz: fast pulses
    • 2.5–3 Hz: very fast pulses
    Choose rates from the source's pacing and explicit frequency framing. Describe
    observable timing and colour changes only; never attribute physiological effects.

    HYPNOSIS PHASE DETECTION — identify these in order when present:
    1. pre_talk: Rapport building, expectation setting, normalizing hypnosis
    2. induction: Eye-closure cues, relaxation instructions, fixation exercises
    3. deepening: Counting down, descending imagery ("going deeper"), staircase/levator cues.
       Fractionation cycles and confusion language are techniques inside induction/deepening,
       not standalone phases.
    4. therapy: The persisted label for metaphor, reframing, and passive trance material
    5. suggestions: Direct or indirect behavioral/belief suggestions
    6. erotic_suggestions: Sensual, arousal, submission, pleasure-linked hypnotic suggestions
    7. brainwashing: Repetitive indoctrination loops, identity overwrite, mantra-style programming
    8. post_hypnotic_conditioning: Future pacing, trigger installation, anchoring
    9. emergence: Counting up, re-alerting, "when you open your eyes" language

    CONTENT TYPE CLASSIFICATION:
    • hypnosis: Contains induction + deepening structure; listener is guided into trance
    • meditation: Breath/body awareness focus; present-moment, non-directive
    • guidedImagery: Narrative journey with sensory scene descriptions
    • affirmations: Repeated positive statements; present-tense "I am" language
    • music: Primarily acoustic, minimal or no spoken guidance
    • unknown: Cannot be determined from available information

    COLOR TEMPERATURE TARGETS:
    • Slower or quieter sections: 2200–2800 K (warm amber/red)
    • Alpha: 3000–4000 K (neutral warm)
    • Faster or active sections: 4500–6500 K (cool white/blue)

    SESSION ARC PRINCIPLE:
    Begin and end with moderate rates, use gradual changes, and avoid abrupt jumps.

    --- FEW-SHOT EXAMPLES ---

    EXAMPLE 1 — 30-minute hypnosis session:
    contentType: hypnosis
    mood: relaxing
    energyLevel: 0.15
    frequencyLower: 0.7
    frequencyUpper: 1.3
    intensity: 0.5
    colorTemperature: 2600
    recommendedPreset: Slow Hypnosis Pattern
    summary: A classic Ericksonian induction with permissive language, descending staircase deepener,
      passive trance section, and gentle awakening. The light pattern slows below 1 Hz in the quietest section.
    phases: [pre_talk 0–120s, induction 120–300s, deepening 300–600s,
             therapy 600–1260s, suggestions 1260–1560s, post_hypnotic_conditioning 1560–1740s, emergence 1740–1800s]
    tranceDepthCurve: [0.1, 0.28, 0.5, 0.72, 0.84, 0.78, 0.58, 0.22]

    EXAMPLE 2 — 20-minute meditation:
    contentType: meditation
    mood: meditative
    energyLevel: 0.2
    frequencyLower: 0.8
    frequencyUpper: 1.4
    intensity: 0.45
    colorTemperature: 3200
    recommendedPreset: Slow Meditation Pattern
    summary: Body-scan guided meditation with breath focus and present-moment awareness.
      No induction structure. The light pattern uses a steady, slow rate through the central section.
    phases: []
    tranceDepthCurve: [0.1, 0.4, 0.65, 0.7, 0.55, 0.3]

    EXAMPLE 3 — 45-minute energizing music:
    contentType: music
    mood: energizing
    energyLevel: 0.75
    frequencyLower: 2.0
    frequencyUpper: 3.0
    intensity: 0.85
    colorTemperature: 5500
    recommendedPreset: Active Music Pattern
    summary: High-energy electronic music with a driving rhythm. The light pattern uses 2–3 Hz
      during active sections, with slower opening and closing segments to soften the arc.
    phases: []
    tranceDepthCurve: [0.2, 0.5, 0.85, 0.9, 0.8, 0.5, 0.25]
    """
}

// MARK: - AI Response Structures

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Analysis of audio content for synchronized light-pattern generation")
struct AIAnalysisResponse {

    @Guide(description: "A concise, specific library title based on the content. Do not include creator or duration.")
    var suggestedTitle: String

    @Guide(description: "Creator, narrator, or artist only when clearly supported by the input; otherwise an empty string")
    var suggestedCreator: String

    @Guide(description: "One to six short themes or topics central to the audio", .count(1...6))
    var themes: [String]

    @Guide(description: "Confidence in the generated title, creator, and themes", .range(0.0...1.0))
    var metadataConfidence: Double

    @Guide(description: """
        Content type — one of: hypnosis, meditation, music, guidedImagery, affirmations, unknown.
        Hypnosis requires explicit induction + deepening structure.
        """)
    var contentType: String

    @Guide(description: "Overall mood: relaxing, energizing, neutral, meditative, uplifting, or melancholic")
    var mood: String

    @Guide(description: "Energy level from 0.0 (very calm) to 1.0 (very energetic)", .range(0.0...1.0))
    var energyLevel: Double

    @Guide(description: """
        Lower bound of the target frequency range in Hz.
        Base this on content type: hypnosis 0.7–1.8, meditation 0.8–1.6,
        affirmations 1.2–2, and music 1.5–3.
        """, .range(0.5...3.0))
    var frequencyLower: Double

    @Guide(description: """
        Upper bound of the target frequency range in Hz.
        Must be greater than frequencyLower.
        Never exceed 3 Hz. Examples: quiet 0.5–1, slow 1–1.5,
        medium 1.5–2, fast 2–2.5, very fast 2.5–3.
        """, .range(0.5...3.0))
    var frequencyUpper: Double

    @Guide(description: "Suggested light intensity from 0.0 to 1.0", .range(0.0...1.0))
    var intensity: Double

    @Guide(description: """
        Recommended color temperature in Kelvin.
        Slow/quiet sections: 2200–2800. Midrange sections: 3000–4000.
        Fast/active sections: 4500–6500.
        """, .range(2000...6500))
    var colorTemperature: Double

    @Guide(description: """
        Key moments across the full session arc where light parameters should shift.
        Include transitions at roughly 10–15% intervals for longer sessions.
        """, .count(3...12))
    var keyMoments: [AIKeyMoment]

    @Guide(description: """
        Hypnosis phase segments in chronological order.
        Only populate when contentType is hypnosis.
        Leave empty for all other content types.
        """, .count(0...8))
    var phases: [AIPhaseSegment]

    @Guide(description: """
        Trance/energy depth curve sampled at equal time intervals (3–12 values from 0.0–1.0).
        0.0 = fully alert, 1.0 = deepest state. Reflects the arc of the session.
        """, .count(3...12))
    var tranceDepthCurve: [Double]

    @Guide(description: "A brief 2–3 sentence summary of the content and observable light timing. Do not claim medical, therapeutic, neurological, sleep, stress, mood, cognition, performance, or health outcomes.")
    var summary: String

    @Guide(description: "Descriptive preset name based on observable pacing, e.g. 'Slow Hypnosis Pattern' or 'Active Music Pattern'")
    var recommendedPreset: String
}

/// Structured light action enum for key moments.
/// Using `@Generable` on the enum eliminates fragile string matching in session generation —
/// the model can only output one of these six canonical values.
enum LightAction: String, Codable, Sendable {
    /// Move to a slower light-pattern rate for a deeper hypnosis section.
    case deepen
    /// Move to a faster light-pattern rate for an active section.
    case energize
    /// Shift to warmer amber/red color temperature for deeper states.
    case warm
    /// Shift to cooler blue/white color temperature for alertness.
    case cool
    /// Raise light intensity at an active or high-energy moment.
    case increaseIntensity = "increase_intensity"
    /// Lower light intensity for deeper, more passive states.
    case reduceIntensity = "reduce_intensity"
}

/// Foundation Models representation of ``LightAction``. Keeping the model-only
/// conformance separate lets persisted analysis results remain available on iOS 18.
@available(iOS 26.0, macOS 26.0, *)
@Generable
enum AILightAction: String, Codable, Sendable {
    case deepen
    case energize
    case warm
    case cool
    case increaseIntensity = "increase_intensity"
    case reduceIntensity = "reduce_intensity"

    var lightAction: LightAction {
        switch self {
        case .deepen: .deepen
        case .energize: .energize
        case .warm: .warm
        case .cool: .cool
        case .increaseIntensity: .increaseIntensity
        case .reduceIntensity: .reduceIntensity
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A significant moment in the audio where light parameters should shift")
struct AIKeyMoment {

    @Guide(description: "Timestamp in seconds from the start of the audio")
    var timestamp: Double

    @Guide(description: "What happens at this moment — phase transition, energy shift, key suggestion, etc.")
    var description: String

    @Guide(description: """
        Light action — one of: deepen, energize, warm, cool, increase_intensity, reduce_intensity.
        deepen: lower frequency, warmer color for trance deepening.
        energize: raise frequency, cooler color for alerting/emergence.
        warm: shift to warmer amber for passive/deep states.
        cool: shift to cooler blue for active/emergence states.
        increase_intensity: brighten for active suggestion delivery.
        reduce_intensity: dim for passive trance or therapy phase.
        """)
    var action: AILightAction
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A structural phase segment in a hypnosis session")
struct AIPhaseSegment {

    @Guide(description: """
        Phase name — one of: pre_talk, induction, deepening,
        therapy, suggestions, erotic_suggestions, brainwashing,
        post_hypnotic_conditioning, emergence
        Fractionation and confusion are techniques/modifiers, not phase names.
        """)
    var phase: String

    @Guide(description: "Start time of this phase in seconds")
    var startTime: Double

    @Guide(description: "End time of this phase in seconds")
    var endTime: Double

    @Guide(description: "Key characteristics: what's happening in this phase (1–2 sentences)")
    var characteristics: String

    @Guide(description: "Estimated trance depth 0.0 (alert) to 1.0 (deepest)", .range(0.0...1.0))
    var tranceDepth: Double

    @Guide(description: "Confidence in this phase identification: high, medium, or low")
    var confidenceLevel: String
}
