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
import os
import FoundationModels

// MARK: - AI Analysis Manager Actor

/// Actor-isolated AI analysis manager for thread-safe operations
actor AIAnalysisManager {

    // MARK: - State

    /// Type-erased cancellation keeps Foundation Models types out of storage,
    /// so the actor itself can exist on iOS 18 while its AI work remains iOS 26-only.
    private var cancelCurrentTask: (@Sendable () -> Void)?

    // MARK: - Progress Info

    struct ProgressInfo: Sendable {
        let progress: Double
        let message: String
    }

    // MARK: - Model Availability

    func checkModelAvailability() async -> AIModelAvailability {
        guard #available(iOS 26.0, macOS 26.0, *) else {
            Log.analysis.info("Foundation Models unavailable before iOS 26")
            return .unavailable
        }
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            Log.analysis.info("✅ Foundation Models available")
            return .available
        case .unavailable(let reason):
            Log.analysis.info("❌ Foundation Models unavailable: \(String(describing: reason))")
            return .unavailable
        }
    }

    // MARK: - Analysis Methods

    func analyzeContent(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AnalysisResult {
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await analyzeContentWithFoundationModels(
                transcription: transcription,
                audioFile: audioFile,
                onProgress: onProgress
            )
        }
        return try await analyzeContentWithBuiltInModels(
            transcription: transcription,
            audioFile: audioFile,
            onProgress: onProgress
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func analyzeContentWithFoundationModels(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AnalysisResult {
        await onProgress(ProgressInfo(progress: 0.05, message: "Setting up AI session..."))

        let addendum = await MainActor.run { AnalysisPreferences.shared.aiSystemAddendum }
        // The detailed instructions plus the structured response schema consume
        // the context window before generation begins (4,562 input tokens in a
        // saturated local measurement). The compact pair below is the request
        // that already proved successful as the old retry (3,029 tokens).
        let finalInstructions = addendum.isEmpty
            ? AVESystemPrompt.minimalInstructions
            : AVESystemPrompt.minimalInstructions + "\n\n" + addendum

        let lmSession = LanguageModelSession(instructions: finalInstructions)

        await onProgress(ProgressInfo(progress: 0.15, message: "Building analysis prompt..."))

        let prompt = buildTranscriptionPrompt(transcription: transcription, audioFile: audioFile)
        let introductionMetadata = AudioIntroductionMetadataExtractor.metadata(
            from: transcription.fullText,
            filename: audioFile.filename
        )
        let bundledMetadata = KnownAudioCatalog.shared.verifiedMetadata(for: audioFile)
        async let externalMetadata = bundledMetadata == nil
            ? AudioCatalogMetadataVerifier.verifiedMetadata(
                for: introductionMetadata,
                duration: audioFile.duration
            )
            : nil

        // Build word timestamps once — shared by both phase analyzers. Some
        // imported transcripts carry full text without timed segments, so give
        // the phase pipeline a synthetic full-duration segment in that case.
        let phaseTranscription = phaseReadyTranscription(transcription)
        let wordTimestamps = HypnosisPhaseAnalyzer()
            .approximateWordTimestamps(from: phaseTranscription.segments)

        await onProgress(ProgressInfo(progress: 0.25, message: "Detecting hypnosis phases..."))

        // Phase detection and the broad AI classification are independent —
        // neither consumes the other's output — so they run concurrently.
        // The classification is a single model call; the chunked phase pass
        // dominates, so classification finishes essentially for free.
        async let aiResponseAsync = fetchAIResponse(
            session: lmSession, prompt: prompt,
            transcription: transcription,
            audioFile: audioFile,
            hasCustomInstructions: addendum.isEmpty == false
        )

        let detectedPhases: [PhaseSegment]? = try await runPhaseAnalysis(
            wordTimestamps: wordTimestamps,
            transcription: phaseTranscription,
            onProgress: onProgress
        )

        await onProgress(ProgressInfo(progress: 0.80, message: "Classifying content..."))

        let aiOutcome = try await aiResponseAsync
        guard case .generated(let aiResponse) = aiOutcome else {
            return makeKeywordFallbackResult(
                audioFile: audioFile,
                detectedPhases: detectedPhases,
                verifiedMetadata: bundledMetadata,
                diagnosis: aiOutcome.diagnosis
            )
        }

        await onProgress(ProgressInfo(progress: 0.92, message: "Verifying track information..."))

        let confirmedMetadata: AudioTrackMetadata?
        if let bundledMetadata {
            confirmedMetadata = bundledMetadata
        } else {
            confirmedMetadata = await externalMetadata
        }
        let result = convertToAnalysisResult(
            aiResponse: aiResponse,
            audioFile: audioFile,
            detectedPhases: detectedPhases,
            introductionMetadata: introductionMetadata,
            verifiedMetadata: confirmedMetadata
        )
        logCompletedAnalysis(result)
        return result
    }

    /// What the on-device model produced, or why it did not.
    ///
    /// The reason used to be logged and dropped, so the keyword fallback that
    /// followed could say only *that* it had run, never *why* — which matters
    /// most when the cause is a passing one worth trying again.
    @available(iOS 26.0, macOS 26.0, *)
    enum AIResponseOutcome {
        case generated(AIAnalysisResponse)
        case unavailable(AIGenerationDiagnosis.Kind)

        var diagnosis: AIGenerationDiagnosis.Kind? {
            switch self {
            case .generated: nil
            case .unavailable(let kind): kind
            }
        }
    }

    /// Runs the AI classification with one automatic retry when a fresh compact
    /// session can plausibly help. A context overflow is retried only when that
    /// retry can remove custom instructions; repeating the same compact request
    /// would spend another model round-trip on the same deterministic failure.
    /// Stores a type-erased cancellation closure so cancellation remains supported.
    @available(iOS 26.0, macOS 26.0, *)
    private func fetchAIResponse(
        session: LanguageModelSession,
        prompt: String,
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        hasCustomInstructions: Bool
    ) async throws -> AIResponseOutcome {
        let task = Task<AIAnalysisResponse, Error> {
            do {
                return try await session.respond(
                    to: prompt, generating: AIAnalysisResponse.self
                ).content
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Log the error itself, not just its type: every Foundation
                // Models failure surfaces as `GenerationError`, so the type alone
                // cannot distinguish a context overflow from a guardrail refusal
                // from missing assets — which are three unrelated fixes.
                let diagnosis = AIGenerationDiagnosis.classify(error)
                Log.analysis.info("⚠️ AI attempt 1 failed (\(diagnosis.rawValue)). Reason: \(String(describing: error))")

                // Recorded against the session that was actually refused, so
                // the attachment carries the offending prompt. A guardrail
                // refusal cannot be retried or configured away, so this file is
                // the only remaining evidence of why a given track downgraded.
                if diagnosis == .guardrail {
                    GuardrailFeedbackRecorder.record(
                        session: session,
                        filename: audioFile.filename,
                        explanation: "Analysing a user-supplied audio transcript for pacing and structure; refused as unsafe content."
                    )
                }

                // A refusal, a missing model, or a safety host that cannot be
                // queried will fail identically in a fresh session. A context
                // overflow can improve only when there is an addendum to drop.
                guard diagnosis.isRetryable else { throw error }
                if diagnosis == .contextWindow, hasCustomInstructions == false {
                    throw error
                }
                if hasCustomInstructions {
                    Log.analysis.info("↻ Retrying compact request without custom instructions")
                } else {
                    Log.analysis.info("↻ Retrying compact request in a fresh session")
                }
            }
            // Retry in a fresh compact session; errors propagate out of the Task.
            let fallback = LanguageModelSession(instructions: AVESystemPrompt.minimalInstructions)
            let shortPrompt = buildTranscriptionPrompt(
                transcription: transcription,
                audioFile: audioFile,
                maxChunkSize: Self.transcriptSampleCharacterCount
            )
            return try await fallback.respond(
                to: shortPrompt, generating: AIAnalysisResponse.self
            ).content
        }
        cancelCurrentTask = { task.cancel() }
        // Captured before awaiting the result: by the time a long request
        // returns the app may have changed state, and the question is what the
        // state was when the model was *asked*.
        let activationState = await MainActor.run { PlatformApplication.activationState }
        do {
            let response = try await task.value
            cancelCurrentTask = nil
            await AIAttemptLog.shared.record(AIAttemptRecord(
                filename: audioFile.filename,
                activationState: activationState,
                diagnosis: nil,
                at: Date()
            ))
            return .generated(response)
        } catch is CancellationError {
            cancelCurrentTask = nil
            throw CancellationError()
        } catch {
            let diagnosis = AIGenerationDiagnosis.classify(error)
            await AIAttemptLog.shared.record(AIAttemptRecord(
                filename: audioFile.filename,
                activationState: activationState,
                diagnosis: diagnosis,
                at: Date()
            ))
            Log.analysis.info("❌ AI generation gave up (\(diagnosis.rawValue)) — using keyword fallback. Reason: \(String(describing: error))")
            if diagnosis.isTransient {
                Log.analysis.info("↺ Transient — analysing this file again later should succeed")
            }
            await UsageAnalytics.shared.aiGenerationFallback(reason: diagnosis)
            cancelCurrentTask = nil
            return .unavailable(diagnosis)
        }
    }

    private func logCompletedAnalysis(_ result: AnalysisResult) {
        // This fires for both paths. Announcing "AI Analysis completed" two
        // lines under "🔑 Keyword fallback" credits the model for work it was
        // refused the chance to do — the same dishonesty the badge fix in
        // ERR-006 removed from the UI.
        if result.usedKeywordFallback {
            Log.analysis.info("✅ Analysis completed (keyword fallback — AI did not run)")
        } else {
            Log.analysis.info("✅ AI Analysis completed")
        }
        Log.analysis.info("📊 Content type: \(result.contentType.rawValue), Mood: \(result.mood.rawValue)")
        Log.analysis.info("🔬 Frequency range: \(result.suggestedFrequencyRange)")
        Log.analysis.info("🎯 Key moments: \(result.keyMoments.count)")
        if let meta = result.hypnosisMetadata {
            Log.analysis.info("🧠 Hypnosis phases: \(meta.phases.count)")
        }
    }

    private func phaseReadyTranscription(
        _ transcription: AudioTranscriptionResult
    ) -> AudioTranscriptionResult {
        guard transcription.segments.isEmpty, transcription.fullText.isEmpty == false else {
            return transcription
        }
        return AudioTranscriptionResult(
            fullText: transcription.fullText,
            segments: [
                AudioTranscriptionSegment(
                    text: transcription.fullText,
                    timestamp: 0,
                    duration: transcription.duration,
                    confidence: 1.0
                )
            ],
            duration: transcription.duration,
            detectedLanguage: transcription.locale
        )
    }

    func analyzeWithoutTranscription(
        audioFile: AudioFile,
        audioFeatures: AudioFeatures,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AnalysisResult {
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await analyzeWithoutTranscriptionWithFoundationModels(
                audioFile: audioFile,
                audioFeatures: audioFeatures,
                onProgress: onProgress
            )
        }

        await onProgress(ProgressInfo(progress: 0.5, message: "Using built-in audio analysis..."))
        await recordUnsupportedOSFallback()
        let result = makeKeywordFallbackResult(
            audioFile: audioFile,
            detectedPhases: nil,
            diagnosis: .unsupportedOS
        )
        await onProgress(ProgressInfo(progress: 1, message: "Analysis complete"))
        return result
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func analyzeWithoutTranscriptionWithFoundationModels(
        audioFile: AudioFile,
        audioFeatures: AudioFeatures,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AnalysisResult {
        await onProgress(ProgressInfo(progress: 0.1, message: "Setting up audio analysis..."))

        let lmSession = LanguageModelSession(instructions: AVESystemPrompt.instructions)

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
                Log.analysis.info("⚠️ AI generation error in no-transcription path — retrying with minimal prompt")
                let fallbackSession = LanguageModelSession(instructions: AVESystemPrompt.minimalInstructions)
                let response = try await fallbackSession.respond(to: prompt, generating: AIAnalysisResponse.self)
                return response.content
            }
        }
        cancelCurrentTask = { task.cancel() }

        let aiResponse = try await task.value
        cancelCurrentTask = nil

        let result = convertToAnalysisResult(aiResponse: aiResponse, audioFile: audioFile)
        return result
    }

    func cancelAnalysis() async {
        cancelCurrentTask?()
        cancelCurrentTask = nil
    }

    // MARK: - Phase Analysis

    /// Runs the phase detection pipeline: tries ChunkedPhaseAnalyzer (Apple Intelligence)
    /// first, then falls back to the keyword-based HypnosisPhaseAnalyzer.
    /// Reports per-chunk progress via `onProgress` in the range 0.25 → 0.65 so the
    /// UI doesn't freeze during long recordings.
    private func runPhaseAnalysis(
        wordTimestamps: [WordTimestamp],
        transcription: AudioTranscriptionResult,
        onProgress: @escaping @Sendable (ProgressInfo) async -> Void
    ) async throws -> [PhaseSegment]? {
        try Task.checkCancellation()
        let keywordAnalyzer = HypnosisPhaseAnalyzer()
        let textTechniqueEvidence = TechniqueDetector().detect(
            wordTimestamps: wordTimestamps,
            segments: transcription.segments,
            prosodic: nil,
            duration: transcription.duration
        )

        // Scale ChunkedPhaseAnalyzer's 0–1 fraction into the 0.25–0.65 window.
        let chunkProgressHandler: @Sendable (Double) async -> Void = { fraction in
            await onProgress(ProgressInfo(
                progress: 0.25 + fraction * 0.40,
                message: "Detecting hypnosis phases…"
            ))
        }

        // The keyword pipeline is pure CPU work on the same inputs; run it
        // concurrently with the chunked model pass so it is already finished
        // when the two timelines are compared (and instantly available as
        // fallback when the chunked pass returns nothing).
        async let keywordPhasesAsync = keywordAnalyzer.analyze(
            wordTimestamps: wordTimestamps,
            transcription: transcription,
            techniqueDetection: textTechniqueEvidence
        )

        if #available(iOS 26.0, macOS 26.0, *) {
            if let aiPhases = await ChunkedPhaseAnalyzer.analyze(
                wordTimestamps: wordTimestamps,
                duration: transcription.duration,
                onProgress: chunkProgressHandler
            ), !aiPhases.isEmpty {
                try Task.checkCancellation()
                await onProgress(ProgressInfo(progress: 0.65, message: "Comparing phase models…"))

                let keywordPhases = await keywordPhasesAsync
                let selection = keywordAnalyzer.selectPreferredPhases(
                    keywordPhases: keywordPhases,
                    chunkedPhases: aiPhases,
                    transcription: transcription,
                    techniqueDetection: textTechniqueEvidence
                )

                if selection.usedChunkedAnalyzer {
                    Log.analysis.info("🧠 ChunkedPhaseAnalyzer selected: \(selection.phases.count) phase segments")
                } else {
                    Log.analysis.info("🔑 Keyword analyzer selected over chunked output: \(selection.phases.count) phase segments")
                }
                return keywordAnalyzer.attachLinguisticMarkers(
                    selection.phases,
                    markers: textTechniqueEvidence.markers
                )
            }
        }

        // Keyword fallback is instant — jump straight to the end of phase detection.
        await onProgress(ProgressInfo(progress: 0.65, message: "Using keyword phase analysis…"))
        try Task.checkCancellation()

        let keywordPhases = await keywordPhasesAsync
        try Task.checkCancellation()
        if !keywordPhases.isEmpty {
            Log.analysis.info("🔑 Keyword fallback: \(keywordPhases.count) phase segments")
            return keywordAnalyzer.attachLinguisticMarkers(
                keywordPhases,
                markers: textTechniqueEvidence.markers
            )
        }

        return nil
    }

    private func analyzeContentWithBuiltInModels(
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        onProgress: @Sendable @escaping (ProgressInfo) async -> Void
    ) async throws -> AnalysisResult {
        await onProgress(ProgressInfo(progress: 0.10, message: "Preparing built-in analysis..."))
        await recordUnsupportedOSFallback()
        let phaseTranscription = phaseReadyTranscription(transcription)
        let wordTimestamps = HypnosisPhaseAnalyzer()
            .approximateWordTimestamps(from: phaseTranscription.segments)
        let detectedPhases = try await runPhaseAnalysis(
            wordTimestamps: wordTimestamps,
            transcription: phaseTranscription,
            onProgress: onProgress
        )
        let bundledMetadata = KnownAudioCatalog.shared.verifiedMetadata(for: audioFile)
        let introductionMetadata = AudioIntroductionMetadataExtractor.metadata(
            from: transcription.fullText,
            filename: audioFile.filename
        )
        let verifiedMetadata = bundledMetadata ?? introductionMetadata
        let result = makeKeywordFallbackResult(
            audioFile: audioFile,
            detectedPhases: detectedPhases,
            verifiedMetadata: verifiedMetadata,
            diagnosis: .unsupportedOS
        )
        await onProgress(ProgressInfo(progress: 1, message: "Analysis complete"))
        return result
    }

    /// Report the one fallback that never produces an AI attempt to fail.
    ///
    /// Every other keyword fallback is emitted from the generation `catch`,
    /// because something was tried and refused. Below iOS 26 nothing is tried,
    /// so that catch is never reached and this fallback was invisible in
    /// telemetry — the exact blind spot `aiGenerationFallback` exists to close.
    /// Without it the funnel cannot separate "AI broke" from "AI was never
    /// available on this OS", which is now the larger population.
    private func recordUnsupportedOSFallback() async {
        Log.analysis.info("⌁ Foundation Models needs iOS 26 — using built-in analysis")
        await UsageAnalytics.shared.aiGenerationFallback(reason: .unsupportedOS)
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
    @available(iOS 26.0, macOS 26.0, *)
    func convertToAnalysisResult(
        aiResponse: AIAnalysisResponse,
        audioFile: AudioFile,
        detectedPhases: [PhaseSegment]? = nil,
        introductionMetadata: AudioTrackMetadata? = nil,
        verifiedMetadata: AudioTrackMetadata? = nil
    ) -> AnalysisResult {
        let duration = audioFile.duration
        let mood = AnalysisResult.Mood(rawValue: aiResponse.mood.lowercased()) ?? .neutral
        let aiContentType = parseContentType(aiResponse.contentType)
        let contentType = resolveContentType(
            aiContentType: aiContentType,
            displayName: audioFile.displayName,
            detectedPhases: detectedPhases,
            duration: duration
        )
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
                action: moment.action.lightAction
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

        let result = AnalysisResult(
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
            temporalAnalysis: temporalAnalysis,
            discoveredMetadata: AudioTrackMetadata(
                generatedTitle: aiResponse.suggestedTitle,
                creator: aiResponse.suggestedCreator,
                themes: aiResponse.themes,
                confidence: aiResponse.metadataConfidence
            )
            .mergingIntroduction(introductionMetadata)
            .mergingVerified(verifiedMetadata)
        )

        let expertAnalysis = ExpertAnalysisBuilder().build(
            analysis: result,
            audioDuration: duration
        )

        return AnalysisResult(
            mood: result.mood,
            energyLevel: result.energyLevel,
            suggestedFrequencyRange: result.suggestedFrequencyRange,
            suggestedIntensity: result.suggestedIntensity,
            suggestedColorTemperature: result.suggestedColorTemperature,
            keyMoments: result.keyMoments,
            aiSummary: result.aiSummary,
            recommendedPreset: result.recommendedPreset,
            contentType: result.contentType,
            hypnosisMetadata: result.hypnosisMetadata,
            temporalAnalysis: result.temporalAnalysis,
            voiceCharacteristics: result.voiceCharacteristics,
            classificationConfidence: result.classificationConfidence,
            expertAnalysis: expertAnalysis,
            prosodicProfile: result.prosodicProfile,
            techniqueDetection: result.techniqueDetection,
            transcriptAnalysis: result.transcriptAnalysis,
            discoveredMetadata: result.discoveredMetadata
        )
    }

    func parseContentType(_ raw: String) -> AnalysisResult.ContentType {
        AudioContentType.parse(raw)
    }

    /// Resolves the route used for light-score generation. LumeLabel treats a
    /// coherent phase timeline as first-class evidence; the app should do the
    /// same when broad AI classification is uncertain or overly generic.
    func resolveContentType(
        aiContentType: AnalysisResult.ContentType,
        displayName: String,
        detectedPhases: [PhaseSegment]?,
        duration: TimeInterval
    ) -> AnalysisResult.ContentType {
        let filenameType = aiContentType == .unknown ? inferContentType(from: displayName) : nil
        let resolved = aiContentType == .unknown
            ? filenameType ?? .unknown
            : aiContentType

        guard !resolved.isHypnosisLike else { return resolved }
        guard resolved != .music, resolved != .brainwave else { return resolved }
        guard hasMeaningfulHypnosisPhaseEvidence(detectedPhases, duration: duration) else {
            return resolved
        }

        return .hypnosis
    }

    func hasMeaningfulHypnosisPhaseEvidence(
        _ phases: [PhaseSegment]?,
        duration: TimeInterval
    ) -> Bool {
        guard duration > 0, let phases else { return false }

        let structural = phases
            .filter { $0.endTime > $0.startTime }
            .map { segment -> PhaseSegment in
                let start = max(0, min(duration, segment.startTime))
                let end = max(start, min(duration, segment.endTime))
                return PhaseSegment(
                    id: segment.id,
                    phase: segment.phase.labelingPhase,
                    startTime: start,
                    endTime: end,
                    characteristics: segment.characteristics,
                    tranceDepthEstimate: segment.tranceDepthEstimate,
                    linguisticMarkers: segment.linguisticMarkers,
                    confidenceLevel: segment.confidenceLevel,
                    confidenceRationale: segment.confidenceRationale,
                    transitionTarget: segment.transitionTarget
                )
            }
            .filter { $0.endTime - $0.startTime >= 8.0 }

        guard structural.count >= 2 else { return false }

        let coveredDuration = structural.reduce(0.0) { $0 + max(0, $1.endTime - $1.startTime) }
        let coverage = coveredDuration / duration
        let phasesPresent = Set(structural.map(\.phase))
        let hasTranceWork = phasesPresent.contains(.deepening)
            || phasesPresent.contains(.suggestions)
            || phasesPresent.contains(.brainwashing)
        let hasArcEvidence = phasesPresent.contains(.induction) && hasTranceWork
        let hasConfidentEvidence = structural.contains { $0.confidenceLevel != .low }

        return hasArcEvidence
            && hasConfidentEvidence
            && (coveredDuration >= min(120.0, duration * 0.20) || coverage >= 0.35)
    }

    /// Keyword-based content type inference from a display name (filename without extension).
    /// Used as a last resort when the AI returns "unknown" due to sparse/empty transcripts.
    func inferContentType(from displayName: String) -> AnalysisResult.ContentType? {
        let name = displayName.lowercased()

        // Check specific subtypes before generic hypnosis
        if name.contains("erotic") || name.contains("sensual") || name.contains("pleasure") {
            return .eroticHypnosis
        }
        if name.contains("sleep") && (name.contains("hypno") || name.contains("trance")) {
            return .sleepHypnosis
        }
        if name.contains("sleep") || name.contains("insomnia") || name.contains("yoga nidra") || name.contains("nap") {
            return .sleepHypnosis
        }
        if name.contains("binaural") || name.contains("isochronal") || name.contains("brainwave") ||
           name.contains("solfeggio") || name.contains("hz") {
            return .brainwave
        }
        if name.contains("asmr") || name.contains("whisper") || name.contains("tingles") {
            return .asmr
        }
        if name.contains("hypno") || name.contains("trance") || name.contains("induction") ||
           name.contains("delta") || name.contains("deepening") ||
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
    @available(iOS 26.0, macOS 26.0, *)
    func resolveHypnosisMetadata(
        contentType: AnalysisResult.ContentType,
        aiPhases: [AIPhaseSegment],
        detectedPhases: [PhaseSegment]?
    ) -> HypnosisMetadata? {
        if contentType.isHypnosisLike, let phases = detectedPhases, !phases.isEmpty {
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
        detectedPhases: [PhaseSegment]?,
        verifiedMetadata: AudioTrackMetadata? = nil,
        diagnosis: AIGenerationDiagnosis.Kind? = nil
    ) -> AnalysisResult {
        let contentType = inferContentType(from: audioFile.displayName)
            ?? (hasMeaningfulHypnosisPhaseEvidence(detectedPhases, duration: audioFile.duration) ? .hypnosis : .unknown)
        let duration = audioFile.duration
        let freqRange: ClosedRange<Double>
        let intensity: Double
        let colorTemp: Double
        let mood: AnalysisResult.Mood
        switch contentType {
        case .hypnosis:
            freqRange = 4.0...8.0;   intensity = 0.50; colorTemp = 2600; mood = .relaxing
        case .meditation:
            freqRange = 6.0...8.0;   intensity = 0.45; colorTemp = 3200; mood = .meditative
        case .affirmations:
            freqRange = 9.0...11.0;  intensity = 0.55; colorTemp = 3500; mood = .uplifting
        case .guidedImagery:
            freqRange = 7.0...10.0;  intensity = 0.50; colorTemp = 3000; mood = .relaxing
        case .music:
            freqRange = 12.0...18.0; intensity = 0.75; colorTemp = 5000; mood = .energizing
        case .eroticHypnosis:
            freqRange = 2.0...6.0;   intensity = 0.45; colorTemp = 2400; mood = .relaxing
        case .brainwave:
            freqRange = 1.0...40.0;  intensity = 0.50; colorTemp = 4000; mood = .meditative
        case .asmr:
            freqRange = 7.0...9.0;   intensity = 0.35; colorTemp = 3200; mood = .relaxing
        case .sleepHypnosis:
            freqRange = 0.5...4.0;   intensity = 0.35; colorTemp = 2200; mood = .relaxing
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
        if contentType.isHypnosisLike, let phases = detectedPhases, !phases.isEmpty {
            hypnosisMetadata = HypnosisMetadata(
                phases: phases, inductionStyle: nil,
                estimatedTranceDeph: estimateTranceDephFromPhases(phases),
                suggestionDensity: nil, languagePatterns: [], detectedTechniques: []
            )
        } else {
            hypnosisMetadata = nil
        }
        let presetName = contentType == .unknown ? "Alpha Relaxation" : "\(contentType.displayName) Session"
        let result = AnalysisResult(
            mood: mood,
            energyLevel: contentType == .music ? 0.75 : 0.2,
            suggestedFrequencyRange: freqRange,
            suggestedIntensity: intensity,
            suggestedColorTemperature: colorTemp,
            keyMoments: keyMoments,
            aiSummary: diagnosis.map(AIGenerationDiagnosis.fallbackSummary(for:))
                ?? AIGenerationDiagnosis.keywordFallbackSummary,
            recommendedPreset: presetName,
            contentType: contentType,
            hypnosisMetadata: hypnosisMetadata,
            discoveredMetadata: verifiedMetadata,
            // Recorded so a later pass can ask whether this is worth
            // re-analysing without matching the prose in `aiSummary`.
            aiFallbackKind: diagnosis
        )

        let expertAnalysis = ExpertAnalysisBuilder().build(
            analysis: result,
            audioDuration: audioFile.duration
        )

        return AnalysisResult(
            mood: result.mood,
            energyLevel: result.energyLevel,
            suggestedFrequencyRange: result.suggestedFrequencyRange,
            suggestedIntensity: result.suggestedIntensity,
            suggestedColorTemperature: result.suggestedColorTemperature,
            keyMoments: result.keyMoments,
            aiSummary: result.aiSummary,
            recommendedPreset: result.recommendedPreset,
            contentType: result.contentType,
            hypnosisMetadata: result.hypnosisMetadata,
            temporalAnalysis: result.temporalAnalysis,
            voiceCharacteristics: result.voiceCharacteristics,
            classificationConfidence: result.classificationConfidence,
            expertAnalysis: expertAnalysis,
            prosodicProfile: result.prosodicProfile,
            techniqueDetection: result.techniqueDetection,
            transcriptAnalysis: result.transcriptAnalysis,
            discoveredMetadata: result.discoveredMetadata,
            // Field-by-field rebuild: anything omitted here is silently lost,
            // and losing this one turns a retryable file into a settled one.
            aiFallbackKind: result.aiFallbackKind
        )
    }

}
