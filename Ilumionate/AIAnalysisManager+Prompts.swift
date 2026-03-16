//
//  AIAnalysisManager+Prompts.swift
//  Ilumionate
//
//  Prompt construction helpers for AIAnalysisManager.
//  Kept separate to stay within SwiftLint file_length limits.
//

import Foundation

// MARK: - Prompt Construction

extension AIAnalysisManager {

    /// Word count below which a transcript is considered too sparse to classify
    /// reliably (e.g. subliminal audio where speech is below audible threshold).
    private static let sparseTranscriptThreshold = 40

    /// Builds the analysis prompt for a transcribed audio file.
    /// - Parameter maxChunkSize: Characters per transcript sample section (default 600).
    ///   Pass a smaller value to reduce prompt size when retrying after context overflow.
    func buildTranscriptionPrompt(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        maxChunkSize: Int = 600
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
        prompt += "- Hypnosis: induction language, counting, deepening, eye-closure, emergence cues\n"
        prompt += "- Meditation: breath focus, body scan, present-moment, non-directive\n"
        prompt += "- Guided Imagery: narrative journey, place/scene descriptions, sensory detail\n"
        prompt += "- Affirmations: repeated positive statements, present-tense 'I am'/'I have'\n"
        prompt += "- Music: primarily acoustic, minimal or no spoken guidance\n\n"
        prompt += "For hypnosis or affirmations, generate a full trance phase timeline:\n"
        prompt += "pre_talk, induction, deepening, therapy, suggestions, post_hypnotic_conditioning, emergence\n\n"
        prompt += "Target frequency bands:\n"
        prompt += "- Hypnosis induction: 8–12 Hz descending to deep theta 4–6 Hz\n"
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
