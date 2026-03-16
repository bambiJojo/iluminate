//
//  HypnosisPhaseKeywords.swift
//  Ilumionate
//
//  Keyword taxonomy for hypnosis phase detection.
//  Each entry maps a lowercase word or short phrase to a HypnosisMetadata.Phase
//  with a weight reflecting how strongly it signals that phase.
//  Longer phrases are matched first and carry higher base weights.
//
//  Based on: Erickson collected works, Bandler NLP/trance-formations,
//  Magic Words in Hypnosis, and Script Book (see .ref/ directory).
//

import Foundation

enum HypnosisPhaseKeywords {

    struct Keyword: Sendable {
        let phrase: String
        let phase: HypnosisMetadata.Phase
        let weight: Double
    }

    // MARK: - Full Taxonomy

    static let all: [Keyword] = multiWord + preTalkWords + inductionWords +
                                deepeningWords + therapyWords + suggestionsWords +
                                conditioningWords + emergenceWords

    // MARK: - Multi-Word Phrases (checked first — longest match wins)

    private static let multiWord: [Keyword] = [
        // Pre-Talk
        Keyword(phrase: "how are you",           phase: .preTalk,     weight: 2.0),
        Keyword(phrase: "let me explain",        phase: .preTalk,     weight: 2.5),
        Keyword(phrase: "before we begin",       phase: .preTalk,     weight: 3.0),
        Keyword(phrase: "make yourself",         phase: .preTalk,     weight: 2.0),
        Keyword(phrase: "find a comfortable",    phase: .preTalk,     weight: 2.5),
        Keyword(phrase: "get comfortable",       phase: .preTalk,     weight: 2.5),

        // Induction
        Keyword(phrase: "close your eyes",       phase: .induction,   weight: 3.0),
        Keyword(phrase: "eyes closed",           phase: .induction,   weight: 2.5),
        Keyword(phrase: "take a deep",           phase: .induction,   weight: 2.0),
        Keyword(phrase: "let go",                phase: .induction,   weight: 2.0),
        Keyword(phrase: "letting go",            phase: .induction,   weight: 2.0),
        Keyword(phrase: "count down",            phase: .induction,   weight: 3.0),
        Keyword(phrase: "counting down",         phase: .induction,   weight: 3.0),
        Keyword(phrase: "eyelids heavy",         phase: .induction,   weight: 3.0),
        Keyword(phrase: "eyelids are heavy",     phase: .induction,   weight: 3.0),

        // Deepening
        Keyword(phrase: "deeper and deeper",     phase: .deepening,   weight: 3.5),
        Keyword(phrase: "going deeper",          phase: .deepening,   weight: 3.0),
        Keyword(phrase: "even deeper",           phase: .deepening,   weight: 3.0),
        Keyword(phrase: "more and more",         phase: .deepening,   weight: 2.0),
        Keyword(phrase: "more relaxed",          phase: .deepening,   weight: 2.5),
        Keyword(phrase: "every breath",          phase: .deepening,   weight: 2.5),
        Keyword(phrase: "with every breath",     phase: .deepening,   weight: 3.0),
        Keyword(phrase: "ten times",             phase: .deepening,   weight: 2.0),
        Keyword(phrase: "hundred times",         phase: .deepening,   weight: 2.5),
        Keyword(phrase: "body scan",             phase: .deepening,   weight: 2.5),
        Keyword(phrase: "scan your body",        phase: .deepening,   weight: 2.5),
        Keyword(phrase: "feel yourself",         phase: .deepening,   weight: 2.0),
        Keyword(phrase: "nothing to do",         phase: .deepening,   weight: 2.0),
        Keyword(phrase: "nowhere to go",         phase: .deepening,   weight: 2.0),
        Keyword(phrase: "one hundred",           phase: .deepening,   weight: 1.8),
        Keyword(phrase: "staircase",             phase: .deepening,   weight: 2.5),
        Keyword(phrase: "going down",            phase: .deepening,   weight: 2.0),

        // Therapy (deep trance)
        Keyword(phrase: "in trance",             phase: .therapy,     weight: 3.0),
        Keyword(phrase: "not right now",         phase: .therapy,     weight: 2.0),
        Keyword(phrase: "nothing matters",       phase: .therapy,     weight: 2.5),
        Keyword(phrase: "completely still",      phase: .therapy,     weight: 2.0),
        Keyword(phrase: "deeply relaxed",        phase: .therapy,     weight: 3.0),  // raised: most common therapy anchor

        // Suggestions
        Keyword(phrase: "you will",              phase: .suggestions, weight: 3.0),
        Keyword(phrase: "from now on",           phase: .suggestions, weight: 3.5),
        Keyword(phrase: "every time",            phase: .suggestions, weight: 3.0),
        Keyword(phrase: "each time",             phase: .suggestions, weight: 3.0),
        Keyword(phrase: "from this moment",      phase: .suggestions, weight: 3.5),
        Keyword(phrase: "you find",              phase: .suggestions, weight: 2.0),
        Keyword(phrase: "you feel",              phase: .suggestions, weight: 2.0),
        Keyword(phrase: "your subconscious",     phase: .suggestions, weight: 3.0),
        Keyword(phrase: "inner mind",            phase: .suggestions, weight: 2.5),
        Keyword(phrase: "notice now",            phase: .suggestions, weight: 2.5),
        Keyword(phrase: "in a moment",           phase: .suggestions, weight: 1.5),
        Keyword(phrase: "you are becoming",      phase: .suggestions, weight: 3.0),
        Keyword(phrase: "you are now",           phase: .suggestions, weight: 2.5),

        // Conditioning / Post-Hypnotic
        Keyword(phrase: "post hypnotic",         phase: .conditioning, weight: 3.5),
        Keyword(phrase: "future pacing",         phase: .conditioning, weight: 3.0),
        Keyword(phrase: "carry with you",        phase: .conditioning, weight: 2.5),
        Keyword(phrase: "take with you",         phase: .conditioning, weight: 2.5),
        Keyword(phrase: "remember this",         phase: .conditioning, weight: 2.0),

        // Emergence
        Keyword(phrase: "open your eyes",        phase: .emergence,   weight: 3.5),
        Keyword(phrase: "wide awake",            phase: .emergence,   weight: 3.5),
        Keyword(phrase: "fully awake",           phase: .emergence,   weight: 3.5),
        Keyword(phrase: "coming back",           phase: .emergence,   weight: 3.0),
        Keyword(phrase: "come back",             phase: .emergence,   weight: 3.0),
        Keyword(phrase: "back in the room",      phase: .emergence,   weight: 3.5),
        Keyword(phrase: "when you wake",         phase: .emergence,   weight: 3.0),
        Keyword(phrase: "as you return",         phase: .emergence,   weight: 3.0),
        Keyword(phrase: "slowly now",            phase: .emergence,   weight: 1.5),
        Keyword(phrase: "gently now",            phase: .emergence,   weight: 1.5),
        Keyword(phrase: "feel good",             phase: .emergence,   weight: 2.0),
        Keyword(phrase: "great job",             phase: .emergence,   weight: 2.0),
        Keyword(phrase: "well done",             phase: .emergence,   weight: 2.5),
        Keyword(phrase: "how do you feel",       phase: .emergence,   weight: 2.5),
    ]

    // MARK: - Pre-Talk Single Words

    private static let preTalkWords: [Keyword] = [
        Keyword(phrase: "welcome",     phase: .preTalk, weight: 1.2),
        Keyword(phrase: "hello",       phase: .preTalk, weight: 0.8),
        Keyword(phrase: "introduce",   phase: .preTalk, weight: 1.0),
        Keyword(phrase: "explain",     phase: .preTalk, weight: 1.0),
        Keyword(phrase: "comfortable", phase: .preTalk, weight: 0.8),
        Keyword(phrase: "position",    phase: .preTalk, weight: 0.8),
        Keyword(phrase: "ready",       phase: .preTalk, weight: 0.8),
        Keyword(phrase: "begin",       phase: .preTalk, weight: 0.8),
        Keyword(phrase: "today",       phase: .preTalk, weight: 0.5),
        Keyword(phrase: "seated",      phase: .preTalk, weight: 0.6),
        Keyword(phrase: "lying",       phase: .preTalk, weight: 0.6),
        Keyword(phrase: "adjust",      phase: .preTalk, weight: 0.6),
    ]

    // MARK: - Induction Single Words

    private static let inductionWords: [Keyword] = [
        Keyword(phrase: "relax",       phase: .induction, weight: 1.8),
        Keyword(phrase: "relaxing",    phase: .induction, weight: 1.8),
        Keyword(phrase: "relaxed",     phase: .induction, weight: 1.5),
        Keyword(phrase: "breathe",     phase: .induction, weight: 1.5),
        Keyword(phrase: "breath",      phase: .induction, weight: 1.2),
        Keyword(phrase: "breathing",   phase: .induction, weight: 1.2),
        Keyword(phrase: "calm",        phase: .induction, weight: 1.5),
        Keyword(phrase: "peaceful",    phase: .induction, weight: 1.5),
        Keyword(phrase: "quiet",       phase: .induction, weight: 1.2),
        Keyword(phrase: "gentle",      phase: .induction, weight: 1.0),
        Keyword(phrase: "softly",      phase: .induction, weight: 1.0),
        Keyword(phrase: "slowly",      phase: .induction, weight: 1.0),
        Keyword(phrase: "settle",      phase: .induction, weight: 1.0),
        Keyword(phrase: "release",     phase: .induction, weight: 1.2),
        Keyword(phrase: "tension",     phase: .induction, weight: 1.0),
        Keyword(phrase: "exhale",      phase: .induction, weight: 1.5),
        Keyword(phrase: "inhale",      phase: .induction, weight: 1.5),
        Keyword(phrase: "shoulders",   phase: .induction, weight: 1.0),
        Keyword(phrase: "jaw",         phase: .induction, weight: 1.0),
        Keyword(phrase: "forehead",    phase: .induction, weight: 1.0),
        Keyword(phrase: "eyelids",     phase: .induction, weight: 1.5),
        Keyword(phrase: "soften",      phase: .induction, weight: 1.0),
        Keyword(phrase: "unwind",      phase: .induction, weight: 1.2),
        Keyword(phrase: "unwinding",   phase: .induction, weight: 1.2),
        Keyword(phrase: "heavy",       phase: .induction, weight: 1.2),
    ]

    // MARK: - Deepening Single Words

    private static let deepeningWords: [Keyword] = [
        Keyword(phrase: "deeper",      phase: .deepening, weight: 2.5),
        Keyword(phrase: "deep",        phase: .deepening, weight: 0.6),  // lowered: multi-word phrases carry the signal
        Keyword(phrase: "down",        phase: .deepening, weight: 1.5),
        Keyword(phrase: "drift",       phase: .deepening, weight: 2.0),
        Keyword(phrase: "float",       phase: .deepening, weight: 2.0),
        Keyword(phrase: "floating",    phase: .deepening, weight: 2.0),
        Keyword(phrase: "sinking",     phase: .deepening, weight: 2.0),
        Keyword(phrase: "falling",     phase: .deepening, weight: 1.5),
        Keyword(phrase: "descend",     phase: .deepening, weight: 2.0),
        Keyword(phrase: "descending",  phase: .deepening, weight: 2.0),
        Keyword(phrase: "deepen",      phase: .deepening, weight: 2.2),
        Keyword(phrase: "deepening",   phase: .deepening, weight: 2.2),
        Keyword(phrase: "profoundly",  phase: .deepening, weight: 2.0),
        Keyword(phrase: "weightless",  phase: .deepening, weight: 1.5),
        Keyword(phrase: "sleep",       phase: .deepening, weight: 1.8),
        Keyword(phrase: "trance",      phase: .deepening, weight: 2.0),
        Keyword(phrase: "melting",     phase: .deepening, weight: 2.0),
        Keyword(phrase: "dissolve",    phase: .deepening, weight: 2.0),
        Keyword(phrase: "waves",       phase: .deepening, weight: 1.2),
        Keyword(phrase: "warmth",      phase: .deepening, weight: 1.2),
        Keyword(phrase: "nowhere",     phase: .deepening, weight: 1.5),
        Keyword(phrase: "nothing",     phase: .deepening, weight: 1.2),
        Keyword(phrase: "double",      phase: .deepening, weight: 1.5),
    ]

    // MARK: - Therapy / Deep Trance Single Words

    private static let therapyWords: [Keyword] = [
        Keyword(phrase: "deeply",      phase: .therapy, weight: 2.0),
        Keyword(phrase: "completely",  phase: .therapy, weight: 1.8),
        Keyword(phrase: "absolute",    phase: .therapy, weight: 1.5),
        Keyword(phrase: "notice",      phase: .therapy, weight: 1.2),
        Keyword(phrase: "allow",       phase: .therapy, weight: 1.0),
        Keyword(phrase: "allowing",    phase: .therapy, weight: 1.0),
        Keyword(phrase: "effortlessly",phase: .therapy, weight: 1.5),
        Keyword(phrase: "naturally",   phase: .therapy, weight: 1.2),
        Keyword(phrase: "mind",        phase: .therapy, weight: 0.8),
        Keyword(phrase: "now",         phase: .therapy, weight: 0.8),
    ]

    // MARK: - Suggestions Single Words

    private static let suggestionsWords: [Keyword] = [
        Keyword(phrase: "subconscious",   phase: .suggestions, weight: 2.5),
        Keyword(phrase: "unconscious",    phase: .suggestions, weight: 2.5),
        Keyword(phrase: "imagine",        phase: .suggestions, weight: 2.0),
        Keyword(phrase: "believe",        phase: .suggestions, weight: 1.5),
        Keyword(phrase: "powerful",       phase: .suggestions, weight: 1.2),
        Keyword(phrase: "change",         phase: .suggestions, weight: 1.2),
        Keyword(phrase: "transform",      phase: .suggestions, weight: 1.5),
        Keyword(phrase: "suggestion",     phase: .suggestions, weight: 2.5),
        Keyword(phrase: "accept",         phase: .suggestions, weight: 1.2),
        Keyword(phrase: "absorb",         phase: .suggestions, weight: 1.2),
        Keyword(phrase: "program",        phase: .suggestions, weight: 1.5),
        Keyword(phrase: "imprint",        phase: .suggestions, weight: 2.0),
        Keyword(phrase: "healing",        phase: .suggestions, weight: 1.2),
        Keyword(phrase: "visualize",      phase: .suggestions, weight: 1.5),
        Keyword(phrase: "suggest",        phase: .suggestions, weight: 2.0),
        // "whenever" removed: post-hypnotic conditioning language, not suggestion delivery
        Keyword(phrase: "automatic",      phase: .suggestions, weight: 1.5),
        Keyword(phrase: "anchor",         phase: .suggestions, weight: 2.0),
        Keyword(phrase: "trigger",        phase: .suggestions, weight: 1.5),
    ]

    // MARK: - Post-Hypnotic Conditioning Single Words

    private static let conditioningWords: [Keyword] = [
        Keyword(phrase: "whenever",    phase: .conditioning, weight: 1.8),
        Keyword(phrase: "future",      phase: .conditioning, weight: 1.2),
        Keyword(phrase: "remember",    phase: .conditioning, weight: 1.2),
        Keyword(phrase: "install",     phase: .conditioning, weight: 1.5),
        Keyword(phrase: "pattern",     phase: .conditioning, weight: 1.2),
        Keyword(phrase: "automatic",   phase: .conditioning, weight: 1.5),
    ]

    // MARK: - Emergence Single Words

    private static let emergenceWords: [Keyword] = [
        Keyword(phrase: "aware",       phase: .emergence, weight: 2.0),
        Keyword(phrase: "awake",       phase: .emergence, weight: 2.5),
        Keyword(phrase: "alert",       phase: .emergence, weight: 2.0),
        Keyword(phrase: "refreshed",   phase: .emergence, weight: 2.5),
        Keyword(phrase: "energized",   phase: .emergence, weight: 2.5),
        Keyword(phrase: "returning",   phase: .emergence, weight: 2.0),
        Keyword(phrase: "return",      phase: .emergence, weight: 1.5),
        Keyword(phrase: "rising",      phase: .emergence, weight: 1.5),
        Keyword(phrase: "five",        phase: .emergence, weight: 1.2),
        Keyword(phrase: "four",        phase: .emergence, weight: 1.2),
        Keyword(phrase: "three",       phase: .emergence, weight: 1.2),
        Keyword(phrase: "two",         phase: .emergence, weight: 1.2),
        Keyword(phrase: "one",         phase: .emergence, weight: 1.2),
        Keyword(phrase: "counting",    phase: .emergence, weight: 1.5),
        Keyword(phrase: "waking",      phase: .emergence, weight: 2.0),
        Keyword(phrase: "reorient",    phase: .emergence, weight: 2.0),
        Keyword(phrase: "clarity",     phase: .emergence, weight: 1.2),
        Keyword(phrase: "stretch",     phase: .emergence, weight: 1.2),
        Keyword(phrase: "fingers",     phase: .emergence, weight: 1.2),
        Keyword(phrase: "toes",        phase: .emergence, weight: 1.2),
        Keyword(phrase: "wiggle",      phase: .emergence, weight: 1.5),
        Keyword(phrase: "blink",       phase: .emergence, weight: 1.5),
        Keyword(phrase: "wonderful",   phase: .emergence, weight: 1.8),
        Keyword(phrase: "excellent",   phase: .emergence, weight: 1.5),
    ]
}
