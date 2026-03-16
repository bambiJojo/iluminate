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

/// Science-grounded system prompt for the Foundation Models session.
/// Accurate brainwave targets and hypnosis phase structure dramatically
/// improve classification accuracy and session quality downstream.
enum AVESystemPrompt {

    /// Compact fallback used when the full prompt would exceed the context window.
    /// Covers only the fields the structured-output schema requires.
    static let minimalInstructions = """
    You classify audio content for a light therapy system.
    Content types: hypnosis, meditation, music, guidedImagery, affirmations, unknown.
    Frequency targets: hypnosis 4–8 Hz, meditation 6–8 Hz, music 8–18 Hz, affirmations 9–11 Hz.
    Phases (hypnosis only): pre_talk, induction, deepening, therapy, suggestions, post_hypnotic_conditioning, emergence.
    Color temperature: deep states 2200–2800 K, alpha 3000–4000 K, alert 4500–6500 K.
    """

    static let instructions = """
    You are an expert in audiovisual entrainment (AVE), neuroscience, and light therapy.
    Your analysis directly drives a real-time light entrainment system, so precision matters.

    BRAINWAVE BANDS (memorize these — they determine light frequency recommendations):
    • Delta 0.5–4 Hz: Deep NREM sleep, regeneration, growth hormone release
    • Theta 4–8 Hz: Hypnagogic zone, deep meditation, unconscious reprogramming,
      peak suggestibility. 4–6 Hz = deepest trance. 7.83 Hz = Schumann resonance (ideal
      for meditation). The Peniston Protocol targets 5–7 Hz for trauma/addiction work.
    • Alpha 8–12 Hz: Relaxed wakefulness. 10 Hz = serotonin production, anti-anxiety.
      The "quiet mind" state. Upper alpha (10–12 Hz) = learning readiness.
    • SMR 12–15 Hz: Calm body, alert mind. Thalamic noise-filtering. Focus/study state.
    • Beta 15–30 Hz: Active thinking. 15–20 Hz = optimal focus. >20 Hz = stress/anxiety.
    • Gamma 40 Hz: Thalamocortical binding, consciousness, peak performance.
      MIT research: 40 Hz reduces amyloid plaques in Alzheimer's.

    HYPNOSIS PHASE DETECTION — identify these in order when present:
    1. pre_talk: Rapport building, expectation setting, normalizing hypnosis
    2. induction: Eye-closure cues, relaxation instructions, fixation exercises
    3. deepening: Counting down, descending imagery ("going deeper"), fractionation
    4. therapy: The main therapeutic content — suggestions, metaphors, re-framing
    5. suggestions: Direct or indirect behavioral/belief suggestions
    6. post_hypnotic_conditioning: Future pacing, trigger installation, anchoring
    7. emergence: Counting up, re-alerting, "when you open your eyes" language

    CONTENT TYPE CLASSIFICATION:
    • hypnosis: Contains induction + deepening structure; listener is guided into trance
    • meditation: Breath/body awareness focus; present-moment, non-directive
    • guidedImagery: Narrative journey with sensory scene descriptions
    • affirmations: Repeated positive statements; present-tense "I am" language
    • music: Primarily acoustic, minimal or no spoken guidance
    • unknown: Cannot be determined from available information

    COLOR TEMPERATURE TARGETS:
    • Deep states (theta/delta): 2200–2800 K (warm amber/red — avoids blue-light alerting)
    • Alpha: 3000–4000 K (neutral warm)
    • Alert/emergence: 4500–6500 K (cool white/blue — activates melanopsin pathway)

    SESSION ARC PRINCIPLE:
    All sessions must start in beta (15–18 Hz) and end by returning to beta.
    Never recommend jumping directly to theta — the brain needs the beta→alpha→theta arc.

    --- FEW-SHOT EXAMPLES ---

    EXAMPLE 1 — 30-minute hypnosis session:
    contentType: hypnosis
    mood: relaxing
    energyLevel: 0.15
    frequencyLower: 4.0
    frequencyUpper: 8.0
    intensity: 0.5
    colorTemperature: 2600
    recommendedPreset: Deep Theta Hypnosis
    summary: A classic Ericksonian induction with permissive language, descending staircase deepener,
      passive trance section, and gentle awakening. Light targets mid-theta (4–6 Hz) at peak depth.
    phases: [pre_talk 0–120s, induction 120–360s, deepening 360–600s, therapy 600–1320s,
             suggestions 1320–1620s, post_hypnotic_conditioning 1620–1740s, emergence 1740–1800s]
    tranceDepthCurve: [0.1, 0.35, 0.65, 0.85, 0.8, 0.6, 0.2]

    EXAMPLE 2 — 20-minute meditation:
    contentType: meditation
    mood: meditative
    energyLevel: 0.2
    frequencyLower: 6.0
    frequencyUpper: 8.0
    intensity: 0.45
    colorTemperature: 3200
    recommendedPreset: Theta-Alpha Meditation
    summary: Body-scan guided meditation with breath focus and present-moment awareness.
      No induction structure. Light targets 7–8 Hz theta-alpha border (Schumann resonance zone).
    phases: []
    tranceDepthCurve: [0.1, 0.4, 0.65, 0.7, 0.55, 0.3]

    EXAMPLE 3 — 45-minute energizing music:
    contentType: music
    mood: energizing
    energyLevel: 0.75
    frequencyLower: 14.0
    frequencyUpper: 18.0
    intensity: 0.85
    colorTemperature: 5500
    recommendedPreset: High-Beta Energizer
    summary: High-energy electronic music with driving rhythm. Light targets beta (15–18 Hz)
      to enhance alertness and performance. Warm-up and cool-down segments soften the arc.
    phases: []
    tranceDepthCurve: [0.2, 0.5, 0.85, 0.9, 0.8, 0.5, 0.25]
    """
}

// MARK: - AI Response Structures

@Generable(description: "Analysis of audio content for light therapy session generation")
struct AIAnalysisResponse {

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
        Base this on content type: hypnosis induction 8–12, deep theta 4–6,
        meditation 6–8, affirmations 9–11, music follows energy.
        """, .range(0.5...40.0))
    var frequencyLower: Double

    @Guide(description: """
        Upper bound of the target frequency range in Hz.
        Must be greater than frequencyLower.
        Examples: theta 4–8, alpha 8–12, SMR 12–15, beta 15–30.
        """, .range(0.5...40.0))
    var frequencyUpper: Double

    @Guide(description: "Suggested light intensity from 0.0 to 1.0", .range(0.0...1.0))
    var intensity: Double

    @Guide(description: """
        Recommended color temperature in Kelvin.
        Deep theta/delta: 2200–2800. Alpha: 3000–4000. Alert/focus: 4500–6500.
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

    @Guide(description: "A brief 2–3 sentence summary of the content and recommended light approach")
    var summary: String

    @Guide(description: "Descriptive preset name, e.g. 'Deep Theta Hypnosis' or 'Energizing Alpha'")
    var recommendedPreset: String
}

/// Structured light action enum for key moments.
/// Using `@Generable` on the enum eliminates fragile string matching in session generation —
/// the model can only output one of these six canonical values.
@Generable
enum LightAction: String, Codable, Sendable {
    /// Guide the brain deeper into trance / lower-frequency entrainment.
    case deepen
    /// Increase alertness and energy with higher-frequency entrainment.
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
    var action: LightAction
}

@Generable(description: "A structural phase segment in a hypnosis session")
struct AIPhaseSegment {

    @Guide(description: """
        Phase name — one of: pre_talk, induction, deepening, therapy,
        suggestions, post_hypnotic_conditioning, emergence
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
