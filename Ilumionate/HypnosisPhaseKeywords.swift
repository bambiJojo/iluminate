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

nonisolated enum HypnosisPhaseKeywords {

    struct Keyword: Sendable {
        let phrase: String
        let phase: HypnosisMetadata.Phase
        let weight: Double
    }

    // MARK: - Full Taxonomy

    static let all: [Keyword] = multiWord + orientationInductionWords + inductionWords +
                                fractionationWords + deepeningWords + confusionWords +
                                therapyWords + suggestionsWords + eroticSuggestionsWords +
                                brainwashingWords + conditioningWords + emergenceWords

    // MARK: - Multi-Word Phrases (checked first — longest match wins)

    private static let multiWord: [Keyword] = [
        // Orientation-style induction
        Keyword(phrase: "how are you",           phase: .induction,   weight: 2.0),
        Keyword(phrase: "let me explain",        phase: .induction,   weight: 2.5),
        Keyword(phrase: "before we begin",       phase: .induction,   weight: 3.0),
        Keyword(phrase: "make yourself",         phase: .induction,   weight: 2.0),
        Keyword(phrase: "find a comfortable",    phase: .induction,   weight: 2.5),
        Keyword(phrase: "get comfortable",       phase: .induction,   weight: 2.5),
        Keyword(phrase: "what is hypnosis",      phase: .induction,   weight: 3.8),
        Keyword(phrase: "suggestibility test",   phase: .induction,   weight: 3.8),
        Keyword(phrase: "critical mind",         phase: .induction,   weight: 3.2),
        Keyword(phrase: "critical factor",       phase: .induction,   weight: 3.2),
        Keyword(phrase: "common occurrence",     phase: .induction,   weight: 2.8),
        Keyword(phrase: "watching a movie",      phase: .induction,   weight: 2.8),
        Keyword(phrase: "driving somewhere",     phase: .induction,   weight: 2.8),
        Keyword(phrase: "bypass of the critical", phase: .induction,  weight: 4.0),
        Keyword(phrase: "subconscious guided you", phase: .induction, weight: 3.0),
        Keyword(phrase: "analytical or non analytical", phase: .induction, weight: 3.8),

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
        Keyword(phrase: "circular breathing",    phase: .induction,   weight: 3.6),
        Keyword(phrase: "eye closure",           phase: .induction,   weight: 3.6),
        Keyword(phrase: "three deep breaths",    phase: .induction,   weight: 3.4),
        Keyword(phrase: "body awareness",        phase: .induction,   weight: 3.2),
        Keyword(phrase: "body relaxation",       phase: .induction,   weight: 3.2),
        Keyword(phrase: "ultimate body relaxation", phase: .induction, weight: 3.8),
        Keyword(phrase: "arm drop",              phase: .induction,   weight: 3.3),
        Keyword(phrase: "hand focus",            phase: .induction,   weight: 3.1),
        Keyword(phrase: "hand breathing",        phase: .induction,   weight: 3.1),
        Keyword(phrase: "velvety breathing",     phase: .induction,   weight: 3.4),
        Keyword(phrase: "focus on a spot",       phase: .induction,   weight: 3.2),
        Keyword(phrase: "fix your eyes",         phase: .induction,   weight: 3.0),
        Keyword(phrase: "spot on the ceiling",   phase: .induction,   weight: 3.0),

        // Fractionation technique cues route to the structural deepening phase.
        Keyword(phrase: "open your eyes",        phase: .deepening, weight: 2.8),
        Keyword(phrase: "open and close",        phase: .deepening, weight: 3.0),
        Keyword(phrase: "close them again",      phase: .deepening, weight: 3.0),
        Keyword(phrase: "drop back down",        phase: .deepening, weight: 3.4),
        Keyword(phrase: "go back down",          phase: .deepening, weight: 3.2),
        Keyword(phrase: "deeper each time",      phase: .deepening, weight: 3.6),
        Keyword(phrase: "every time you open",   phase: .deepening, weight: 3.2),
        Keyword(phrase: "every time you close",  phase: .deepening, weight: 3.2),

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
        Keyword(phrase: "beautiful staircase",   phase: .deepening,   weight: 3.4),
        Keyword(phrase: "in your minds eye",     phase: .deepening,   weight: 3.0),
        Keyword(phrase: "in your mind's eye",    phase: .deepening,   weight: 3.0),
        Keyword(phrase: "step by step",          phase: .deepening,   weight: 2.8),
        Keyword(phrase: "ten to one",            phase: .deepening,   weight: 2.8),
        Keyword(phrase: "deeper asleep",         phase: .deepening,   weight: 3.2),
        Keyword(phrase: "sound of my voice",     phase: .deepening,   weight: 2.6),

        // Therapy (deep trance)
        Keyword(phrase: "in trance",             phase: .therapy,     weight: 3.0),
        Keyword(phrase: "not right now",         phase: .therapy,     weight: 2.0),
        Keyword(phrase: "nothing matters",       phase: .therapy,     weight: 2.5),
        Keyword(phrase: "completely still",      phase: .therapy,     weight: 2.0),
        Keyword(phrase: "deeply relaxed",        phase: .therapy,     weight: 3.0),  // raised: most common therapy anchor
        Keyword(phrase: "let me tell you a story", phase: .therapy,   weight: 3.6),
        Keyword(phrase: "i want to tell you a story", phase: .therapy, weight: 3.6),
        Keyword(phrase: "there was once",        phase: .therapy,     weight: 3.2),
        Keyword(phrase: "once upon a time",      phase: .therapy,     weight: 3.0),
        Keyword(phrase: "a metaphor for",        phase: .therapy,     weight: 3.4),
        Keyword(phrase: "your unconscious mind", phase: .therapy,     weight: 3.2),
        Keyword(phrase: "in your own way",       phase: .therapy,     weight: 2.8),
        Keyword(phrase: "inner resources",       phase: .therapy,     weight: 3.0),
        Keyword(phrase: "use that feeling",      phase: .therapy,     weight: 2.8),
        Keyword(phrase: "whatever happens",      phase: .therapy,     weight: 2.4),
        Keyword(phrase: "thats right",           phase: .therapy,     weight: 2.6),
        Keyword(phrase: "that's right",          phase: .therapy,     weight: 2.6),

        // Confusion technique cues route to the surrounding structural deepening phase.
        Keyword(phrase: "you may wonder",        phase: .deepening,   weight: 3.0),
        Keyword(phrase: "while you are wondering", phase: .deepening, weight: 3.4),
        Keyword(phrase: "the more you try",      phase: .deepening,   weight: 3.2),
        Keyword(phrase: "the less you need",     phase: .deepening,   weight: 3.2),
        Keyword(phrase: "and as you don't",      phase: .deepening,   weight: 3.0),
        Keyword(phrase: "before you know",       phase: .deepening,   weight: 2.8),
        Keyword(phrase: "whether you do or don't", phase: .deepening, weight: 3.4),

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

        // Erotic suggestions
        Keyword(phrase: "feel that pleasure",    phase: .eroticSuggestions, weight: 3.5),
        Keyword(phrase: "wave of pleasure",      phase: .eroticSuggestions, weight: 3.6),
        Keyword(phrase: "each touch",            phase: .eroticSuggestions, weight: 3.0),
        Keyword(phrase: "arousal grows",         phase: .eroticSuggestions, weight: 3.5),
        Keyword(phrase: "body craving",          phase: .eroticSuggestions, weight: 3.4),
        Keyword(phrase: "sink into pleasure",    phase: .eroticSuggestions, weight: 3.6),
        Keyword(phrase: "obedience feels good",  phase: .eroticSuggestions, weight: 3.6),

        // Brainwashing
        Keyword(phrase: "deeper into obedience", phase: .brainwashing, weight: 3.8),
        Keyword(phrase: "accept this truth",     phase: .brainwashing, weight: 3.6),
        Keyword(phrase: "this is your purpose",  phase: .brainwashing, weight: 3.8),
        Keyword(phrase: "you are programmed",    phase: .brainwashing, weight: 3.8),
        Keyword(phrase: "repeat after me",       phase: .brainwashing, weight: 3.6),
        Keyword(phrase: "obey automatically",    phase: .brainwashing, weight: 3.8),
        Keyword(phrase: "mindless obedience",    phase: .brainwashing, weight: 4.0),

        // Conditioning / Post-Hypnotic
        Keyword(phrase: "post hypnotic",         phase: .conditioning, weight: 3.5),
        Keyword(phrase: "future pacing",         phase: .conditioning, weight: 3.0),
        Keyword(phrase: "carry with you",        phase: .conditioning, weight: 2.5),
        Keyword(phrase: "take with you",         phase: .conditioning, weight: 2.5),
        Keyword(phrase: "remember this",         phase: .conditioning, weight: 2.0),
        Keyword(phrase: "post hypnotic suggestion", phase: .conditioning, weight: 3.9),
        Keyword(phrase: "post hypnotic suggestions", phase: .conditioning, weight: 3.9),
        Keyword(phrase: "post hypnotic trigger", phase: .conditioning, weight: 4.0),
        Keyword(phrase: "voice serves as an anchor", phase: .conditioning, weight: 3.6),
        Keyword(phrase: "soothing anchor",       phase: .conditioning, weight: 3.2),
        Keyword(phrase: "trigger to your subconscious", phase: .conditioning, weight: 3.8),
        Keyword(phrase: "trigger for trance",    phase: .conditioning, weight: 3.6),
        Keyword(phrase: "next time you hear",    phase: .conditioning, weight: 3.8),
        Keyword(phrase: "when i say",            phase: .conditioning, weight: 3.4),
        Keyword(phrase: "hear the word",         phase: .conditioning, weight: 3.2),
        Keyword(phrase: "eyes open trance",      phase: .conditioning, weight: 3.6),
        Keyword(phrase: "breath matching",       phase: .conditioning, weight: 3.2),

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
        Keyword(phrase: "as i count to five",    phase: .emergence,   weight: 4.0),
        Keyword(phrase: "count to five",         phase: .emergence,   weight: 3.6),
        Keyword(phrase: "wide awake and aware",  phase: .emergence,   weight: 4.0),
        Keyword(phrase: "clear headed",          phase: .emergence,   weight: 3.6),
        Keyword(phrase: "wonderfully relaxed",   phase: .emergence,   weight: 3.2),
    ]

    // MARK: - Orientation Induction Single Words

    private static let orientationInductionWords: [Keyword] = [
        Keyword(phrase: "welcome",     phase: .induction, weight: 1.2),
        Keyword(phrase: "hello",       phase: .induction, weight: 0.8),
        Keyword(phrase: "introduce",   phase: .induction, weight: 1.0),
        Keyword(phrase: "explain",     phase: .induction, weight: 1.0),
        Keyword(phrase: "comfortable", phase: .induction, weight: 0.8),
        Keyword(phrase: "position",    phase: .induction, weight: 0.8),
        Keyword(phrase: "ready",       phase: .induction, weight: 0.8),
        Keyword(phrase: "begin",       phase: .induction, weight: 0.8),
        Keyword(phrase: "today",       phase: .induction, weight: 0.5),
        Keyword(phrase: "seated",      phase: .induction, weight: 0.6),
        Keyword(phrase: "lying",       phase: .induction, weight: 0.6),
        Keyword(phrase: "adjust",      phase: .induction, weight: 0.6),
        Keyword(phrase: "suggestibility", phase: .induction, weight: 1.8),
        Keyword(phrase: "critical",    phase: .induction, weight: 1.2),
        Keyword(phrase: "subconscious", phase: .induction, weight: 1.0),
        Keyword(phrase: "analytical",  phase: .induction, weight: 1.2),
        Keyword(phrase: "movie",       phase: .induction, weight: 0.8),
        Keyword(phrase: "driving",     phase: .induction, weight: 0.8),
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
        Keyword(phrase: "closure",     phase: .induction, weight: 1.2),
        Keyword(phrase: "fixation",    phase: .induction, weight: 1.5),
        Keyword(phrase: "awareness",   phase: .induction, weight: 1.0),
    ]

    // MARK: - Fractionation Technique Single Words

    private static let fractionationWords: [Keyword] = [
        Keyword(phrase: "fractionation", phase: .deepening, weight: 3.0),
        Keyword(phrase: "fractionize",   phase: .deepening, weight: 2.4),
        Keyword(phrase: "fractionise",   phase: .deepening, weight: 2.4),
        Keyword(phrase: "reopen",        phase: .deepening, weight: 2.0),
        Keyword(phrase: "reclose",       phase: .deepening, weight: 2.0),
        Keyword(phrase: "reopenings",    phase: .deepening, weight: 2.0),
        Keyword(phrase: "blink",         phase: .deepening, weight: 1.2),
        Keyword(phrase: "reopen your",   phase: .deepening, weight: 2.0),
    ]

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

    // MARK: - Confusion Technique Single Words

    private static let confusionWords: [Keyword] = [
        Keyword(phrase: "confused",       phase: .deepening, weight: 2.4),
        Keyword(phrase: "confusing",      phase: .deepening, weight: 2.2),
        Keyword(phrase: "paradox",        phase: .deepening, weight: 2.0),
        Keyword(phrase: "wondering",      phase: .deepening, weight: 1.8),
        Keyword(phrase: "uncertain",      phase: .deepening, weight: 1.6),
        Keyword(phrase: "maybe",          phase: .deepening, weight: 0.8),
        Keyword(phrase: "perhaps",        phase: .deepening, weight: 0.8),
        Keyword(phrase: "whether",        phase: .deepening, weight: 1.0),
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
        Keyword(phrase: "metaphor",    phase: .therapy, weight: 2.2),
        Keyword(phrase: "parable",     phase: .therapy, weight: 2.2),
        Keyword(phrase: "story",       phase: .therapy, weight: 1.6),
        Keyword(phrase: "utilization", phase: .therapy, weight: 2.0),
        Keyword(phrase: "utilize",     phase: .therapy, weight: 1.8),
        Keyword(phrase: "unconscious", phase: .therapy, weight: 1.8),
        Keyword(phrase: "reframe",     phase: .therapy, weight: 1.8),
        Keyword(phrase: "resourceful", phase: .therapy, weight: 1.5),
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

    // MARK: - Erotic Suggestions Single Words

    private static let eroticSuggestionsWords: [Keyword] = [
        Keyword(phrase: "pleasure",     phase: .eroticSuggestions, weight: 2.6),
        Keyword(phrase: "sensual",      phase: .eroticSuggestions, weight: 2.4),
        Keyword(phrase: "arousal",      phase: .eroticSuggestions, weight: 2.8),
        Keyword(phrase: "desire",       phase: .eroticSuggestions, weight: 2.2),
        Keyword(phrase: "lust",         phase: .eroticSuggestions, weight: 2.2),
        Keyword(phrase: "touch",        phase: .eroticSuggestions, weight: 1.8),
        Keyword(phrase: "obedience",    phase: .eroticSuggestions, weight: 1.6),
        Keyword(phrase: "submission",   phase: .eroticSuggestions, weight: 2.0),
        Keyword(phrase: "tease",        phase: .eroticSuggestions, weight: 2.0),
        Keyword(phrase: "orgasmic",     phase: .eroticSuggestions, weight: 2.8),
    ]

    // MARK: - Brainwashing Single Words

    private static let brainwashingWords: [Keyword] = [
        Keyword(phrase: "programmed",   phase: .brainwashing, weight: 2.8),
        Keyword(phrase: "conditioning", phase: .brainwashing, weight: 1.6),
        Keyword(phrase: "indoctrinate", phase: .brainwashing, weight: 3.0),
        Keyword(phrase: "indoctrination", phase: .brainwashing, weight: 3.0),
        Keyword(phrase: "brainwash",    phase: .brainwashing, weight: 3.2),
        Keyword(phrase: "brainwashing", phase: .brainwashing, weight: 3.2),
        Keyword(phrase: "obey",         phase: .brainwashing, weight: 2.4),
        Keyword(phrase: "mantra",       phase: .brainwashing, weight: 2.2),
        Keyword(phrase: "repeat",       phase: .brainwashing, weight: 1.8),
        Keyword(phrase: "erase",        phase: .brainwashing, weight: 1.8),
        Keyword(phrase: "rewrite",      phase: .brainwashing, weight: 2.2),
        Keyword(phrase: "overwrite",    phase: .brainwashing, weight: 2.6),
    ]

    // MARK: - Post-Hypnotic Conditioning Single Words

    private static let conditioningWords: [Keyword] = [
        Keyword(phrase: "whenever",    phase: .conditioning, weight: 1.8),
        Keyword(phrase: "future",      phase: .conditioning, weight: 1.2),
        Keyword(phrase: "remember",    phase: .conditioning, weight: 1.2),
        Keyword(phrase: "install",     phase: .conditioning, weight: 1.5),
        Keyword(phrase: "pattern",     phase: .conditioning, weight: 1.2),
        Keyword(phrase: "automatic",   phase: .conditioning, weight: 1.5),
        Keyword(phrase: "anchor",      phase: .conditioning, weight: 2.0),
        Keyword(phrase: "trigger",     phase: .conditioning, weight: 2.0),
        Keyword(phrase: "next",        phase: .conditioning, weight: 1.2),
        Keyword(phrase: "matching",    phase: .conditioning, weight: 1.0),
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
        Keyword(phrase: "headed",      phase: .emergence, weight: 1.2),
        Keyword(phrase: "stretch",     phase: .emergence, weight: 1.2),
        Keyword(phrase: "fingers",     phase: .emergence, weight: 1.2),
        Keyword(phrase: "toes",        phase: .emergence, weight: 1.2),
        Keyword(phrase: "wiggle",      phase: .emergence, weight: 1.5),
        Keyword(phrase: "blink",       phase: .emergence, weight: 1.5),
        Keyword(phrase: "wonderful",   phase: .emergence, weight: 1.8),
        Keyword(phrase: "excellent",   phase: .emergence, weight: 1.5),
    ]
}
