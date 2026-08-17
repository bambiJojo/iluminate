//
//  AnalysisPromptBudgetTests.swift
//  IlumionateTests
//
//  The first analysis attempt overflowed the model's 4,096-token context on
//  every device run. The prompt string itself was not the cause: the detailed
//  instructions and generated response schema dominated the complete request.
//  These tests guard both the compact prompt template and, where Foundation
//  Models exposes its tokenizer, the complete request. See ERRORS.md ERR-007.
//

import Foundation
import FoundationModels
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

    @Test("The compact prompt stays within its character budget")
    func primaryPromptFitsTemplateBudget() async {
        let manager = AIAnalysisManager()

        let prompt = await manager.buildTranscriptionPrompt(
            transcription: longTranscription(),
            audioFile: audioFile()
        )

        #expect(
            prompt.count <= AIAnalysisManager.promptCharacterBudget,
            """
            Primary prompt is \(prompt.count) characters, over the \
            \(AIAnalysisManager.promptCharacterBudget)-character template \
            budget. Recalibrate the complete request before increasing it.
            """
        )
    }

    @Test("A sparse prompt stays within its character budget")
    func sparsePromptFitsTemplateBudget() async {
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

    @Test("The complete primary request stays within its measured token budget")
    func primaryRequestFitsMeasuredTokenBudget() async throws {
        guard #available(iOS 26.4, macOS 26.4, *),
              SystemLanguageModel.default.availability == .available else { return }

        let manager = AIAnalysisManager()
        let prompt = await manager.buildTranscriptionPrompt(
            transcription: longTranscription(),
            audioFile: audioFile()
        )
        let model = SystemLanguageModel.default
        let entries: [Transcript.Entry] = [
            .instructions(
                Transcript.Instructions(
                    segments: [.text(.init(content: AVESystemPrompt.minimalInstructions))],
                    toolDefinitions: []
                )
            ),
            .prompt(
                Transcript.Prompt(
                    segments: [.text(.init(content: prompt))],
                    responseFormat: .init(type: AIAnalysisResponse.self)
                )
            )
        ]
        let requestTokens = try await model.tokenCount(for: entries)

        #expect(
            requestTokens <= AIAnalysisManager.primaryRequestTokenBudget,
            "Primary request is \(requestTokens) input tokens; budget is \(AIAnalysisManager.primaryRequestTokenBudget)."
        )
    }

}
