//
//  AnalysisPromptBudgetTests.swift
//  IlumionateTests
//
//  The first analysis attempt overflowed the model's 4,096-token context on
//  every device run — 4,816 / 4,765 / 4,829 / 4,864 / 4,771 tokens across
//  transcripts spanning 1,179 to 6,387 words. The prompt is assembled from a
//  fixed template plus a fixed-size transcript sample, so it does not scale
//  with the transcript and the overflow is systematic rather than an edge case.
//
//  These pin the assembled prompt under a character budget, so the same drift
//  cannot recur silently the next time the guidance text grows. See ERRORS.md
//  ERR-007.
//

import Foundation
import Testing
@testable import Ilumionate

struct AnalysisPromptBudgetTests {

    /// Long enough that the transcript sample is saturated — the worst case for
    /// prompt size, and the shape every real file takes.
    private func longTranscription() -> AudioTranscriptionResult {
        let sentence = "Relax now and let the sound carry you deeper into stillness. "
        let text = String(repeating: sentence, count: 400)   // ~24,000 characters
        return AudioTranscriptionResult(
            fullText: text,
            segments: (0..<40).map { index in
                AudioTranscriptionSegment(
                    text: sentence,
                    timestamp: Double(index) * 20,
                    duration: 20,
                    confidence: 0.94
                )
            },
            duration: 1_800,
            detectedLanguage: "en"
        )
    }

    private func audioFile() -> AudioFile {
        AudioFile(
            filename: "Deep Relaxation Session.mp3",
            duration: 1_800,
            fileSize: 20_000_000
        )
    }

    @Test("The first-attempt prompt fits the model's context window")
    func firstAttemptPromptFitsContextWindow() async {
        let manager = AIAnalysisManager()

        let prompt = await manager.buildTranscriptionPrompt(
            transcription: longTranscription(),
            audioFile: audioFile()
        )

        #expect(
            prompt.count <= AIAnalysisManager.promptCharacterBudget,
            """
            First-attempt prompt is \(prompt.count) characters, over the \
            \(AIAnalysisManager.promptCharacterBudget) budget. It will be \
            rejected for exceeding the context window and cost a wasted \
            round trip before the retry.
            """
        )
    }

    @Test("A sparse transcript also fits")
    func sparsePromptFitsContextWindow() async {
        let manager = AIAnalysisManager()
        let sparse = AudioTranscriptionResult(
            fullText: "Sleep.",
            segments: [],
            duration: 1_800,
            detectedLanguage: "en"
        )

        let prompt = await manager.buildTranscriptionPrompt(
            transcription: sparse,
            audioFile: audioFile()
        )

        #expect(prompt.count <= AIAnalysisManager.promptCharacterBudget)
    }

}
