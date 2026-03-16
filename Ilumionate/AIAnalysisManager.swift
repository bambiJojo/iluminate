//
//  AIAnalysisManager.swift
//  Ilumionate
//
//  AI-powered audio content analysis for light therapy session generation.
//  The quality of session generation depends entirely on the accuracy and
//  richness of the data returned here — contentType routing, phase detection,
//  and key moment density all directly drive SessionGenerator strategy selection.
//

import Foundation
import FoundationModels

// MARK: - AI Analysis Manager Actor

/// Actor-isolated AI analysis manager for thread-safe operations
actor AIAnalysisManager {

    // MARK: - State

    private let model = SystemLanguageModel.default
    private var session: LanguageModelSession?
    private var currentTask: Task<AIAnalysisResponse, Error>?

    // MARK: - Progress Info

    struct ProgressInfo: Sendable {
        let progress: Double
        let message: String
    }

    // MARK: - Model Availability

    func checkModelAvailability() async -> SystemLanguageModel.Availability {
        let availability = model.availability
        switch availability {
        case .available:
            print("✅ Foundation Models available")
        case .unavailable(let reason):
            print("❌ Foundation Models unavailable: \(reason)")
        }
        return availability
    }

    // MARK: - Analysis Methods

    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AnalysisResult {
        await onProgress(ProgressInfo(progress: 0.1, message: "Setting up AI session..."))

        let addendum = await MainActor.run { AnalysisPreferences.shared.aiSystemAddendum }
        let finalInstructions = addendum.isEmpty
            ? AVESystemPrompt.instructions
            : AVESystemPrompt.instructions + "\n\n" + addendum

        let lmSession = LanguageModelSession(instructions: finalInstructions)
        session = lmSession

        await onProgress(ProgressInfo(progress: 0.25, message: "Building analysis prompt..."))

        let prompt = buildTranscriptionPrompt(transcription: transcription, audioFile: audioFile)

        // Build word timestamps once — shared by both phase analyzers
        let wordTimestamps = HypnosisPhaseAnalyzer()
            .approximateWordTimestamps(from: transcription.segments)

        await onProgress(ProgressInfo(progress: 0.4, message: "Analyzing phases and content in parallel..."))

        // Phase detection runs first — it's synchronous (keyword pipeline) or uses a
        // separate Foundation Models session (ChunkedPhaseAnalyzer), so it doesn't
        // block the main AI classification call.
        let detectedPhases: [PhaseSegment]? = await runPhaseAnalysis(
            wordTimestamps: wordTimestamps,
            segments: transcription.segments,
            duration: audioFile.duration,
            onProgress: onProgress
        )

        guard let aiResponse = await fetchAIResponse(
            session: lmSession, prompt: prompt,
            transcription: transcription, audioFile: audioFile
        ) else {
            return makeKeywordFallbackResult(audioFile: audioFile, detectedPhases: detectedPhases)
        }

        await onProgress(ProgressInfo(progress: 0.9, message: "Processing recommendations..."))

        let result = convertToAnalysisResult(
            aiResponse: aiResponse, audioFile: audioFile, detectedPhases: detectedPhases
        )
        logCompletedAnalysis(result)
        return result
    }

    /// Runs the AI classification with one automatic retry on any error.
    /// Sets `currentTask` so cancellation remains supported. Returns `nil`
    /// when both attempts fail, signalling the caller to use keyword fallback.
    private func fetchAIResponse(
        session: LanguageModelSession,
        prompt: String,
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async -> AIAnalysisResponse? {
        let task = Task<AIAnalysisResponse, Error> {
            do {
                return try await session.respond(
                    to: prompt, generating: AIAnalysisResponse.self
                ).content
            } catch {
                print("⚠️ AI attempt 1 failed (\(type(of: error))) — retrying with minimal prompt")
            }
            // Retry with compact prompt; errors here propagate out of the Task.
            let fallback = LanguageModelSession(instructions: AVESystemPrompt.minimalInstructions)
            let shortPrompt = buildTranscriptionPrompt(
                transcription: transcription, audioFile: audioFile, maxChunkSize: 120
            )
            return try await fallback.respond(
                to: shortPrompt, generating: AIAnalysisResponse.self
            ).content
        }
        currentTask = task
        do {
            let response = try await task.value
            currentTask = nil
            return response
        } catch {
            print("❌ All AI attempts exhausted (\(type(of: error))) — using keyword fallback")
            currentTask = nil
            return nil
        }
    }

    private func logCompletedAnalysis(_ result: AnalysisResult) {
        print("✅ AI Analysis completed")
        print("📊 Content type: \(result.contentType.rawValue), Mood: \(result.mood.rawValue)")
        print("🔬 Frequency range: \(result.suggestedFrequencyRange)")
        print("🎯 Key moments: \(result.keyMoments.count)")
        if let meta = result.hypnosisMetadata {
            print("🧠 Hypnosis phases: \(meta.phases.count)")
        }
    }

    func analyzeWithoutTranscription(
        audioFile: AudioFile,
        audioFeatures: AudioFeatures,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AnalysisResult {
        await onProgress(ProgressInfo(progress: 0.1, message: "Setting up audio analysis..."))

        let lmSession = LanguageModelSession(instructions: AVESystemPrompt.instructions)
        session = lmSession

        let energyPercent = (audioFeatures.averageEnergy * 100).formatted(.number.precision(.fractionLength(1)))
        let durationStr = formatDuration(audioFile.duration)

        let prompt = """
        Analyze this audio file for light therapy session generation.

        Audio Characteristics:
        - Duration: \(durationStr)
        - Average Tempo: \(audioFeatures.averageTempo.formatted(.number.precision(.fractionLength(0)))) BPM
        - Average Energy: \(energyPercent)%
        - Dynamic Range: \(audioFeatures.dynamicRange)

        With no transcript available, infer content type from tempo and energy:
        - Very low tempo (<60 BPM) + low energy → likely meditation, hypnosis, or spoken word
        - Medium tempo (60–100 BPM) + varied energy → likely guided imagery or music
        - High tempo (>100 BPM) + high energy → likely music

        Classify the content type and recommend light therapy parameters accordingly.
        For the frequency range, target the appropriate brainwave band for the content type.
        """

        await onProgress(ProgressInfo(progress: 0.5, message: "Analyzing audio features..."))

        let task = Task {
            do {
                let response = try await lmSession.respond(to: prompt, generating: AIAnalysisResponse.self)
                return response.content
            } catch is LanguageModelSession.GenerationError {
                print("⚠️ AI generation error in no-transcription path — retrying with minimal prompt")
                let fallbackSession = LanguageModelSession(instructions: AVESystemPrompt.minimalInstructions)
                let response = try await fallbackSession.respond(to: prompt, generating: AIAnalysisResponse.self)
                return response.content
            }
        }
        currentTask = task

        let aiResponse = try await task.value
        currentTask = nil

        let result = convertToAnalysisResult(aiResponse: aiResponse, audioFile: audioFile)
        return result
    }

    func cancelAnalysis() async {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Phase Analysis

    /// Runs the phase detection pipeline: tries ChunkedPhaseAnalyzer (Apple Intelligence)
    /// first, then falls back to the keyword-based HypnosisPhaseAnalyzer.
    /// Reports per-chunk progress via `onProgress` in the range 0.40 → 0.70 so the
    /// UI doesn't freeze during long recordings.
    private func runPhaseAnalysis(
        wordTimestamps: [WordTimestamp],
        segments: [AudioTranscriptionSegment],
        duration: TimeInterval,
        onProgress: @escaping @Sendable (ProgressInfo) async -> Void
    ) async -> [PhaseSegment]? {
        // Scale ChunkedPhaseAnalyzer's 0–1 fraction into the 0.40–0.70 window
        let chunkProgressHandler: @Sendable (Double) async -> Void = { fraction in
            await onProgress(ProgressInfo(
                progress: 0.40 + fraction * 0.30,
                message: "Detecting hypnosis phases…"
            ))
        }

        if let aiPhases = await ChunkedPhaseAnalyzer.analyze(
            wordTimestamps: wordTimestamps,
            duration: duration,
            onProgress: chunkProgressHandler
        ), !aiPhases.isEmpty {
            print("🧠 ChunkedPhaseAnalyzer: \(aiPhases.count) phase segments")
            return aiPhases
        }

        // Keyword fallback is instant — jump straight to 0.70
        await onProgress(ProgressInfo(progress: 0.70, message: "Using keyword phase analysis…"))

        let keywordPhases = HypnosisPhaseAnalyzer().analyze(
            segments: segments,
            duration: duration
        )
        if !keywordPhases.isEmpty {
            print("🔑 Keyword fallback: \(keywordPhases.count) phase segments")
            return keywordPhases
        }

        return nil
    }
}

// MARK: - Transcript Sampling (internal for testability)

extension AIAnalysisManager {

    /// Samples a long transcript at four positions: 0%, 50%, 75%, and 100%.
    /// Returns the full text verbatim when it is 800 characters or fewer.
    /// - Parameter chunkSize: Max characters per section (default 600).
    static func sampleTranscript(_ fullText: String, chunkSize: Int = 600) -> String {
        guard fullText.count > 800 else { return fullText }

        let len = fullText.count

        func slice(from offset: Int) -> String {
            let start = fullText.index(fullText.startIndex, offsetBy: min(offset, len))
            let remaining = fullText.distance(from: start, to: fullText.endIndex)
            let end = fullText.index(start, offsetBy: min(chunkSize, remaining))
            return String(fullText[start..<end])
        }

        let opening   = slice(from: 0)
        let midpoint  = slice(from: len / 2)
        let latePoint = slice(from: len * 3 / 4)
        let closing   = String(fullText.suffix(chunkSize))

        return """
            --- Opening ---
            \(opening)

            --- Middle (50%) ---
            \(midpoint)

            --- Late (75%) ---
            \(latePoint)

            --- End ---
            \(closing)
            """
    }
}

// MARK: - Response Conversion

private extension AIAnalysisManager {

    /// Converts the AI-generated response into an `AnalysisResult` with full
    /// content type routing, hypnosis metadata, and temporal analysis populated.
    ///
    /// - Parameter detectedPhases: Phase segments from `ChunkedPhaseAnalyzer` or the
    ///   keyword pipeline. When non-nil, these high-resolution segments are preferred
    ///   over `aiResponse.phases` for building `HypnosisMetadata`.
    func convertToAnalysisResult(
        aiResponse: AIAnalysisResponse,
        audioFile: AudioFile,
        detectedPhases: [PhaseSegment]? = nil
    ) -> AnalysisResult {
        let duration = audioFile.duration
        let mood = AnalysisResult.Mood(rawValue: aiResponse.mood.lowercased()) ?? .neutral
        let aiContentType = parseContentType(aiResponse.contentType)
        // If AI returned "unknown", try to infer from the filename before giving up
        let contentType = aiContentType == .unknown
            ? inferContentType(from: audioFile.displayName) ?? .unknown
            : aiContentType
        let frequencyRange: ClosedRange<Double> = {
            let lower = aiResponse.frequencyLower
            let upper = aiResponse.frequencyUpper
            guard lower < upper else { return 8.0...12.0 } // fallback if model inverts bounds
            return lower...upper
        }()

        let keyMoments = aiResponse.keyMoments.map { moment in
            KeyMoment(
                time: moment.timestamp,
                description: moment.description,
                action: moment.action
            )
        }

        // Prefer the high-resolution phase pipeline result over the AI's coarse estimate
        let hypnosisMetadata = resolveHypnosisMetadata(
            contentType: contentType,
            aiPhases: aiResponse.phases,
            detectedPhases: detectedPhases
        )

        // Build temporal analysis from the trance depth curve if provided
        let temporalAnalysis = buildTemporalAnalysis(
            curve: aiResponse.tranceDepthCurve,
            duration: duration
        )

        return AnalysisResult(
            mood: mood,
            energyLevel: aiResponse.energyLevel,
            suggestedFrequencyRange: frequencyRange,
            suggestedIntensity: aiResponse.intensity,
            suggestedColorTemperature: aiResponse.colorTemperature,
            keyMoments: keyMoments,
            aiSummary: aiResponse.summary,
            recommendedPreset: aiResponse.recommendedPreset,
            contentType: contentType,
            hypnosisMetadata: hypnosisMetadata,
            temporalAnalysis: temporalAnalysis
        )
    }

    func parseContentType(_ raw: String) -> AnalysisResult.ContentType {
        switch raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "hypnosis":                          return .hypnosis
        case "meditation":                        return .meditation
        case "music":                             return .music
        case "guidedimagery", "guided_imagery",
             "guided imagery":                    return .guidedImagery
        case "affirmations":                      return .affirmations
        default:                                  return .unknown
        }
    }

    /// Keyword-based content type inference from a display name (filename without extension).
    /// Used as a last resort when the AI returns "unknown" due to sparse/empty transcripts.
    func inferContentType(from displayName: String) -> AnalysisResult.ContentType? {
        let name = displayName.lowercased()
        if name.contains("hypno") || name.contains("trance") || name.contains("induction") ||
           name.contains("sleep") || name.contains("delta") || name.contains("deepening") ||
           name.contains("brain") || name.contains("smooth") {
            return .hypnosis
        }
        if name.contains("medit") || name.contains("mindful") || name.contains("breath") ||
           name.contains("calm") || name.contains("relax") || name.contains("zen") {
            return .meditation
        }
        if name.contains("subliminal") || name.contains("affirm") || name.contains("suggest") ||
           name.contains("mantra") || name.contains("positive") {
            return .affirmations
        }
        if name.contains("guided") || name.contains("visual") || name.contains("journey") {
            return .guidedImagery
        }
        return nil
    }

    /// Chooses the hypnosis metadata source: high-resolution pipeline phases take
    /// priority over the AI's coarse per-session estimate.
    func resolveHypnosisMetadata(
        contentType: AnalysisResult.ContentType,
        aiPhases: [AIPhaseSegment],
        detectedPhases: [PhaseSegment]?
    ) -> HypnosisMetadata? {
        if contentType == .hypnosis, let phases = detectedPhases, !phases.isEmpty {
            return HypnosisMetadata(
                phases: phases, inductionStyle: nil,
                estimatedTranceDeph: estimateTranceDephFromPhases(phases),
                suggestionDensity: nil, languagePatterns: [], detectedTechniques: []
            )
        }
        return buildHypnosisMetadata(contentType: contentType, phases: aiPhases)
    }

    /// Builds a usable `AnalysisResult` from keyword/filename inference when both AI
    /// attempts fail. Ensures every file always gets a generated light session.
    func makeKeywordFallbackResult(
        audioFile: AudioFile,
        detectedPhases: [PhaseSegment]?
    ) -> AnalysisResult {
        let contentType = inferContentType(from: audioFile.displayName) ?? .unknown
        let duration = audioFile.duration
        let freqRange: ClosedRange<Double>
        let intensity: Double
        let colorTemp: Double
        let mood: AnalysisResult.Mood
        switch contentType {
        case .hypnosis:
            freqRange = 4.0...8.0;  intensity = 0.50; colorTemp = 2600; mood = .relaxing
        case .meditation:
            freqRange = 6.0...8.0;  intensity = 0.45; colorTemp = 3200; mood = .meditative
        case .affirmations:
            freqRange = 9.0...11.0; intensity = 0.55; colorTemp = 3500; mood = .uplifting
        case .guidedImagery:
            freqRange = 7.0...10.0; intensity = 0.50; colorTemp = 3000; mood = .relaxing
        case .music:
            freqRange = 12.0...18.0; intensity = 0.75; colorTemp = 5000; mood = .energizing
        case .unknown:
            freqRange = 8.0...12.0;  intensity = 0.50; colorTemp = 3500; mood = .neutral
        }
        let momentCount = max(4, min(8, Int(duration / 120.0) + 2))
        let interval = duration / Double(momentCount + 1)
        let actions: [LightAction] = [.warm, .deepen, .reduceIntensity, .cool, .energize, .deepen, .warm, .energize]
        let keyMoments = (0..<momentCount).map { idx in
            KeyMoment(time: interval * Double(idx + 1),
                      description: "Session segment \(idx + 1)",
                      action: actions[idx % actions.count])
        }
        let hypnosisMetadata: HypnosisMetadata?
        if contentType == .hypnosis, let phases = detectedPhases, !phases.isEmpty {
            hypnosisMetadata = HypnosisMetadata(
                phases: phases, inductionStyle: nil,
                estimatedTranceDeph: estimateTranceDephFromPhases(phases),
                suggestionDensity: nil, languagePatterns: [], detectedTechniques: []
            )
        } else {
            hypnosisMetadata = nil
        }
        let presetName = contentType == .unknown ? "Alpha Relaxation" : "\(contentType.rawValue.capitalized) Session"
        return AnalysisResult(
            mood: mood,
            energyLevel: contentType == .music ? 0.75 : 0.2,
            suggestedFrequencyRange: freqRange,
            suggestedIntensity: intensity,
            suggestedColorTemperature: colorTemp,
            keyMoments: keyMoments,
            aiSummary: "Analysis via keyword classification (AI generation failed).",
            recommendedPreset: presetName,
            contentType: contentType,
            hypnosisMetadata: hypnosisMetadata
        )
    }

}
