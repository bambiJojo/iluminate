//
//  AIAnalysisManager+Prompts.swift
//  Ilumionate
//
//  Prompt construction helpers for AIAnalysisManager.
//  Kept separate to stay within SwiftLint file_length limits.
//

import Foundation
import os

// MARK: - Prompt Construction

extension AIAnalysisManager {

    /// Word count below which a transcript is considered too sparse to classify
    /// reliably (e.g. subliminal audio where speech is below audible threshold).
    private static let sparseTranscriptThreshold = 40

    /// Characters sampled from each of the transcript's four positions.
    ///
    /// This used to be 600. Combined with the detailed system instructions and
    /// response schema, that produced a 4,562-token request before the model had
    /// room to answer. The compact request was already the successful retry.
    static let transcriptSampleCharacterCount = 120

    /// A ceiling on the assembled prompt *string*, as a regression guard.
    ///
    /// Not the model's context limit, and deliberately not presented as one.
    /// Measured on 2026-08-11: the compact prompt and minimal instructions make
    /// a 3,029-token request including the structured response schema. This
    /// guard catches template growth, while the Foundation Models token-count
    /// regression test covers the complete request on supported test hosts.
    /// See ERRORS.md ERR-007.
    static let promptCharacterBudget = 6_000

    /// Measured input ceiling for the complete compact request. This is not a
    /// declaration of the model's context size; it preserves the headroom that
    /// made the former retry succeed and catches growth in the response schema.
    static let primaryRequestTokenBudget = 3_300

    /// Builds the analysis prompt for a transcribed audio file.
    /// - Parameter maxChunkSize: Characters per transcript sample section (default 120).
    ///   Pass a smaller value to reduce prompt size when retrying after context overflow.
    func buildTranscriptionPrompt(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        maxChunkSize: Int = AIAnalysisManager.transcriptSampleCharacterCount
    ) -> String {
        let wordCount = transcription.fullText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count

        let avgConfidence = transcription.segments.isEmpty
            ? 0.0
            : transcription.segments.map { $0.confidence }.reduce(0, +) / Double(transcription.segments.count)
        let confidenceStr = (avgConfidence * 100).formatted(.number.precision(.fractionLength(1)))
        let durationStr = formatDuration(audioFile.duration)
        let isSparse = wordCount < Self.sparseTranscriptThreshold

        var prompt = "Analyze this audio content for light therapy session generation:\n\n"
        prompt += "Audio Information:\n"
        prompt += "- Filename: \(audioFile.displayName)\n"
        prompt += "- Duration: \(durationStr)\n"
        prompt += "- Word Count: \(wordCount)\n"
        prompt += "- Transcription Confidence: \(confidenceStr)%\n"
        prompt += "- Language: \(transcription.locale)\n\n"

        let introduction = String(transcription.fullText.prefix(1_500))
        if !introduction.isEmpty {
            prompt += "Opening Introduction (highest-priority metadata evidence):\n"
            prompt += "\(introduction)\n\n"
            prompt += "Metadata guidance:\n"
            prompt += "- Openings often say 'hello, this is [creator]' followed by 'this is' or 'welcome to [title]'\n"
            prompt += "- Use an explicitly announced creator and title over guesses from the broader content\n"
            prompt += "- Allow for minor transcription spelling errors by comparing the spoken title with the filename\n"
            prompt += "- Never infer a creator when no name is announced or otherwise supplied\n\n"
        }

        if isSparse {
            prompt += "⚠️ SPARSE TRANSCRIPT: Only \(wordCount) words detected. "
            prompt += "This is likely subliminal or near-silent audio. "
            prompt += "Use the FILENAME and DURATION as your primary classification signals. "
            prompt += "Never return 'unknown' — infer the most probable content type.\n\n"
            prompt += "Filename classification hints:\n"
            prompt += "- 'subliminal', 'affirmation', 'suggestion' → affirmations or hypnosis\n"
            prompt += "- 'sleep', 'delta', 'deep', 'trance' → hypnosis (deep theta target)\n"
            prompt += "- 'meditation', 'mindful', 'breath', 'calm', 'relax' → meditation\n"
            prompt += "- 'brain', 'smooth', 'frequency', 'wave' → hypnosis or meditation\n"
            prompt += "- 'focus', 'energy', 'boost', 'alpha' → affirmations or music\n\n"
        } else {
            let sampledText = AIAnalysisManager.sampleTranscript(transcription.fullText, chunkSize: maxChunkSize)
            prompt += "Transcript Sample (beginning / 50% / 75% / end):\n\(sampledText)\n\n"
        }

        prompt += "Classification guidance:\n"
        prompt += "- Hypnosis: pre-talk education or suggestibility tests, then induction language like breathing, eye-closure, arm-drop/hand-focus, countdowns, deepening, post-hypnotic triggers, and emergence cues\n"
        prompt += "- Erotic Hypnosis: hypnosis structure with sensual, arousal, dominance, or pleasure-oriented suggestions\n"
        prompt += "- Sleep Hypnosis: drowsiness cues, sleep imagery, insomnia relief, descent into delta, often no wake-up ending\n"
        prompt += "- Brainwave: binaural, isochronic, solfeggio, or explicit Hz/entrainment framing\n"
        prompt += "- ASMR: whispering, trigger words, tingles, close-mic sensory soothing with minimal direct instruction\n"
        prompt += "- Meditation: breath focus, body scan, present-moment, non-directive\n"
        prompt += "- Guided Imagery: narrative journey, place/scene descriptions, sensory detail\n"
        prompt += "- Affirmations: repeated positive statements, present-tense 'I am'/'I have'\n"
        prompt += "- Music: primarily acoustic, minimal or no spoken guidance\n\n"
        prompt += "Hypnosis structure cues from script manuals:\n"
        prompt += "- Pre-talk often includes explaining hypnosis, bypassing the critical mind, common everyday trance examples, and suggestibility testing\n"
        prompt += "- Induction often uses circular breathing, three deep breaths, eye closure, body relaxation/body awareness, hand focus, arm drop, or fixation on a spot\n"
        prompt += "- Deepening often uses staircase imagery, descending numbers, 'deeper and deeper', or 'sound of my voice' guidance\n"
        prompt += "- Fractionation and confusion are techniques/modifiers inside induction, deepening, or suggestion work; do not output them as phase names\n"
        prompt += "- Ericksonian therapy sections may shift into stories, metaphors, utilization language, yes-set phrasing like 'that's right', indirect reframes, or invitations to respond in the subject's own way\n"
        prompt += "- Conditioning often uses explicit post-hypnotic suggestions, anchors, trigger words, 'when I say', 'next time you hear', eyes-open trance, or breath matching\n"
        prompt += "- Emergence often uses counting up to five, 'wide awake and aware', 'clear headed', reorientation, and physical re-engagement\n\n"
        prompt += "For hypnosis, erotic hypnosis, sleep hypnosis, or affirmations, generate a full trance phase timeline when the session has clear phases:\n"
        prompt += "pre_talk, induction, deepening, therapy, suggestions, erotic_suggestions, brainwashing, post_hypnotic_conditioning, emergence\n\n"
        prompt += "Target frequency bands:\n"
        prompt += "- Hypnosis induction: 8–12 Hz descending to deep theta 4–6 Hz\n"
        prompt += "- Erotic Hypnosis: 2–6 Hz with warm, immersive pacing\n"
        prompt += "- Sleep Hypnosis: 0.5–4 Hz, very low intensity, warm colors, typically no emergence ramp\n"
        prompt += "- Brainwave: honor the stated entrainment band or carrier frequency when present\n"
        prompt += "- ASMR: subtle 7–9 Hz alpha/theta edge with low visual intensity\n"
        prompt += "- Meditation: 6–8 Hz (theta-alpha, 7.83 Hz Schumann ideal)\n"
        prompt += "- Affirmations: 9–11 Hz (upper alpha, peak suggestibility)\n"
        prompt += "- Music: match energy — high: 12–18 Hz, calm: 8–12 Hz\n\n"
        prompt += "Provide 6–10 key moments spanning the full session arc."

        return prompt
    }

    func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }
}
