//
//  AudioAnalysisEnricher.swift
//  Ilumionate
//
//  Shared enrichment layer for audio-driven light scoring.
//  This keeps the foreground AnalysisPipeline and the background import queue
//  on the same path: phase analysis from the content analyzer is augmented with
//  raw-audio prosody, hypnotic technique timing, and transcript-derived rhythm.
//

import Foundation
import os

/// Adds timing-sensitive data required for accurate light-score generation.
///
/// `AIAnalysisManager` is responsible for content classification and phase
/// detection. This type adds the audio-signal and transcript metrics that make
/// the generated score track the creator's delivery instead of only the broad
/// content type or file duration.
nonisolated struct AudioAnalysisEnricher: Sendable {

    let prosodyAnalyzer: any ProsodyAnalyzingService
    let analyzerConfig: AnalyzerConfig

    init(
        prosodyAnalyzer: any ProsodyAnalyzingService = ProsodyAnalyzer(),
        analyzerConfig: AnalyzerConfig = AnalyzerConfigLoader.load()
    ) {
        self.prosodyAnalyzer = prosodyAnalyzer
        self.analyzerConfig = analyzerConfig
    }

    /// Extracts prosody from the raw audio signal. Failures are intentionally
    /// non-fatal so transcript-only generation still works.
    func extractProsody(
        audioFile: AudioFile,
        transcription: AudioTranscriptionResult
    ) async -> ProsodicProfile? {
        let service = prosodyAnalyzer
        let url = audioFile.url
        let segments = transcription.segments
        let config = ProsodyAnalyzer.Config(from: analyzerConfig.prosody)

        let task = Task.detached(priority: .userInitiated) { () -> ProsodicProfile? in
            do {
                return try service.analyze(url: url, segments: segments, config: config)
            } catch {
                Log.audio.info("⚠️ Prosody extraction failed: \(error.localizedDescription)")
                return nil
            }
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Merges prosody, technique detection, and transcript metrics into a base
    /// `AnalysisResult` returned by the content analyzer.
    func enrich(
        _ analysis: AnalysisResult,
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile,
        prosody: ProsodicProfile?
    ) -> AnalysisResult {
        let resolvedProsody = prosody ?? analysis.prosodicProfile
        let voiceCharacteristics: VoiceCharacteristics?
        if let resolvedProsody {
            voiceCharacteristics = buildVoiceCharacteristics(from: resolvedProsody)
        } else {
            voiceCharacteristics = analysis.voiceCharacteristics
        }

        let wordTimestamps = HypnosisPhaseAnalyzer()
            .approximateWordTimestamps(from: transcription.segments)

        let detector = TechniqueDetector(config: analyzerConfig.techniqueDetection)
        let duration = resolvedProsody?.totalDuration ?? transcription.duration
        let techniqueDetection = detector.detect(
            wordTimestamps: wordTimestamps,
            segments: transcription.segments,
            prosodic: resolvedProsody,
            duration: duration
        )
        let contentType = resolvedContentType(
            current: analysis.contentType,
            displayName: audioFile.displayName,
            techniqueDetection: techniqueDetection
        )

        let hypnosisMetadata: HypnosisMetadata?
        if let hypnosis = analysis.hypnosisMetadata, !hypnosis.phases.isEmpty {
            let markedPhases = HypnosisPhaseAnalyzer()
                .attachLinguisticMarkers(hypnosis.phases, markers: techniqueDetection.markers)
            let normalizedPhases = PhaseTimelineNormalizer().normalize(
                markedPhases,
                duration: audioFile.duration,
                contentType: analysis.contentType
            )
            hypnosisMetadata = HypnosisMetadata(
                phases: normalizedPhases,
                inductionStyle: hypnosis.inductionStyle,
                estimatedTranceDeph: hypnosis.estimatedTranceDeph,
                suggestionDensity: hypnosis.suggestionDensity,
                languagePatterns: hypnosis.languagePatterns,
                detectedTechniques: techniqueDetection.techniques
            )
        } else if contentType.isHypnosisLike, hasStrongHypnosisTechniqueEvidence(techniqueDetection) {
            let synthesizedPhases = synthesizeFallbackPhases(
                from: techniqueDetection,
                duration: max(audioFile.duration, duration)
            )
            hypnosisMetadata = HypnosisMetadata(
                phases: synthesizedPhases,
                inductionStyle: nil,
                estimatedTranceDeph: synthesizedPhases.isEmpty
                    ? estimatedDepth(from: techniqueDetection)
                    : estimateDepth(from: synthesizedPhases),
                suggestionDensity: suggestionDensity(
                    from: techniqueDetection,
                    duration: max(audioFile.duration, duration)
                ),
                languagePatterns: languagePatterns(from: techniqueDetection),
                detectedTechniques: techniqueDetection.techniques
            )
        } else {
            hypnosisMetadata = analysis.hypnosisMetadata
        }

        let transcriptAnalyzer = TranscriptFeatureAnalyzer()
        let transcriptAnalysis = transcriptAnalyzer.analyze(
            transcription: transcription,
            phases: hypnosisMetadata?.phases
        )

        let enrichedAnalysis = AnalysisResult(
            mood: analysis.mood,
            energyLevel: analysis.energyLevel,
            suggestedFrequencyRange: analysis.suggestedFrequencyRange,
            suggestedIntensity: analysis.suggestedIntensity,
            suggestedColorTemperature: analysis.suggestedColorTemperature,
            keyMoments: analysis.keyMoments,
            aiSummary: analysis.aiSummary,
            recommendedPreset: recommendedPreset(
                original: analysis.recommendedPreset,
                originalContentType: analysis.contentType,
                resolvedContentType: contentType
            ),
            contentType: contentType,
            hypnosisMetadata: hypnosisMetadata,
            temporalAnalysis: analysis.temporalAnalysis,
            voiceCharacteristics: voiceCharacteristics,
            classificationConfidence: analysis.classificationConfidence,
            prosodicProfile: resolvedProsody,
            techniqueDetection: techniqueDetection,
            transcriptAnalysis: transcriptAnalysis,
            discoveredMetadata: analysis.discoveredMetadata
        )

        let expertAnalysis = ExpertAnalysisBuilder().build(
            analysis: enrichedAnalysis,
            audioDuration: audioFile.duration,
            transcription: transcription,
            prosody: resolvedProsody,
            techniqueDetection: techniqueDetection,
            transcriptAnalysis: transcriptAnalysis
        )

        return AnalysisResult(
            mood: enrichedAnalysis.mood,
            energyLevel: enrichedAnalysis.energyLevel,
            suggestedFrequencyRange: enrichedAnalysis.suggestedFrequencyRange,
            suggestedIntensity: enrichedAnalysis.suggestedIntensity,
            suggestedColorTemperature: enrichedAnalysis.suggestedColorTemperature,
            keyMoments: enrichedAnalysis.keyMoments,
            aiSummary: enrichedAnalysis.aiSummary,
            recommendedPreset: enrichedAnalysis.recommendedPreset,
            contentType: enrichedAnalysis.contentType,
            hypnosisMetadata: enrichedAnalysis.hypnosisMetadata,
            temporalAnalysis: enrichedAnalysis.temporalAnalysis,
            voiceCharacteristics: enrichedAnalysis.voiceCharacteristics,
            classificationConfidence: enrichedAnalysis.classificationConfidence,
            expertAnalysis: expertAnalysis,
            prosodicProfile: enrichedAnalysis.prosodicProfile,
            techniqueDetection: enrichedAnalysis.techniqueDetection,
            transcriptAnalysis: enrichedAnalysis.transcriptAnalysis,
            discoveredMetadata: enrichedAnalysis.discoveredMetadata
        )
    }

    /// Convenience for callers that do not need to overlap prosody extraction
    /// with AI work.
    func enrich(
        _ analysis: AnalysisResult,
        transcription: AudioTranscriptionResult,
        audioFile: AudioFile
    ) async -> AnalysisResult {
        let prosody = await extractProsody(audioFile: audioFile, transcription: transcription)
        return enrich(
            analysis,
            transcription: transcription,
            audioFile: audioFile,
            prosody: prosody
        )
    }

    // MARK: - Voice Characteristics

    private func resolvedContentType(
        current: AudioContentType,
        displayName: String,
        techniqueDetection: TechniqueDetectionResult
    ) -> AudioContentType {
        guard current == .unknown else { return current }
        if let inferred = inferContentType(from: displayName) {
            return inferred
        }
        return hasStrongHypnosisTechniqueEvidence(techniqueDetection) ? .hypnosis : current
    }

    private func inferContentType(from displayName: String) -> AudioContentType? {
        let name = displayName.lowercased()
        if name.contains("erotic") || name.contains("sensual") || name.contains("pleasure") {
            return .eroticHypnosis
        }
        if name.contains("sleep") && (name.contains("hypno") || name.contains("trance")) {
            return .sleepHypnosis
        }
        if name.contains("sleep") || name.contains("insomnia") || name.contains("yoga nidra") {
            return .sleepHypnosis
        }
        if name.contains("hypno") || name.contains("trance") || name.contains("induction") {
            return .hypnosis
        }
        return nil
    }

    private func hasStrongHypnosisTechniqueEvidence(
        _ detection: TechniqueDetectionResult
    ) -> Bool {
        let hypnosisTechniques: Set<String> = [
            "deepening_command",
            "embedded_command",
            "countdown",
            "utilization",
            "anchoring",
            "trigger_installation",
            "fractionation",
            "confusion_technique",
            "amnesia_suggestion",
            "dissociation",
            "brainwashing",
            "emergence_sequence",
            "suggestibility_testing",
            "progressive_relaxation"
        ]
        let techniqueHits = detection.techniques.filter {
            hypnosisTechniques.contains($0.technique)
        }
        let markerStrength = detection.markers.map(\.strength).reduce(0, +)
        return techniqueHits.count >= 6 || markerStrength >= 5.0
    }

    private func estimatedDepth(
        from detection: TechniqueDetectionResult
    ) -> HypnosisMetadata.TranceDeph {
        let techniqueNames = Set(detection.techniques.map(\.technique))
        if techniqueNames.contains("brainwashing")
            || techniqueNames.contains("amnesia_suggestion")
            || techniqueNames.contains("trigger_installation") {
            return .somnambulism
        }
        if techniqueNames.contains("deepening_command")
            || techniqueNames.contains("fractionation") {
            return .deep
        }
        return .medium
    }

    private func suggestionDensity(
        from detection: TechniqueDetectionResult,
        duration: TimeInterval
    ) -> Double? {
        guard duration > 0 else { return nil }
        let suggestionLike: Set<String> = [
            "embedded_command",
            "anchoring",
            "trigger_installation",
            "amnesia_suggestion",
            "brainwashing",
            "direct_suggestion"
        ]
        let count = detection.techniques.filter {
            suggestionLike.contains($0.technique)
        }.count
        return Double(count) / max(duration / 60.0, 1.0)
    }

    private func languagePatterns(
        from detection: TechniqueDetectionResult
    ) -> [String] {
        Array(Set(detection.techniques.map(\.technique))).sorted()
    }

    private func synthesizeFallbackPhases(
        from detection: TechniqueDetectionResult,
        duration: TimeInterval
    ) -> [PhaseSegment] {
        guard duration > 0 else { return [] }

        let events = detection.techniques
            .map { (time: max(0, min(duration, $0.timestamp)), phase: phase(forTechnique: $0.technique)) }
            .filter { $0.phase != nil }
            .sorted { $0.time < $1.time }

        guard !events.isEmpty else { return defaultHypnosisArc(duration: duration) }

        let bucketLength = max(45.0, duration / 12.0)
        var buckets: [(start: TimeInterval, end: TimeInterval, phase: HypnosisMetadata.Phase, count: Int)] = []
        for event in events {
            guard let phase = event.phase else { continue }
            let bucketStart = floor(event.time / bucketLength) * bucketLength
            let bucketEnd = min(duration, bucketStart + bucketLength)
            if let index = buckets.firstIndex(where: { abs($0.start - bucketStart) < 0.001 && $0.phase == phase }) {
                buckets[index].count += 1
            } else {
                buckets.append((bucketStart, bucketEnd, phase, 1))
            }
        }

        let strongestByBucket = Dictionary(grouping: buckets, by: \.start)
            .values
            .compactMap { $0.max { lhs, rhs in lhs.count < rhs.count } }
            .sorted { $0.start < $1.start }

        let seededSegments = strongestByBucket.map { bucket in
            PhaseSegment(
                phase: bucket.phase,
                startTime: bucket.start,
                endTime: bucket.end,
                characteristics: "Synthesized from technique timing because phase classification returned no segments",
                tranceDepthEstimate: depthEstimate(for: bucket.phase),
                confidenceLevel: .low,
                confidenceRationale: "Fallback phase inferred from \(bucket.count) detected technique marker(s), not direct phase classification"
            )
        }

        let normalized = PhaseTimelineNormalizer().normalize(
            seededSegments,
            duration: duration,
            contentType: .hypnosis
        )
        return normalized.isEmpty ? defaultHypnosisArc(duration: duration) : normalized
    }

    private func phase(forTechnique technique: String) -> HypnosisMetadata.Phase? {
        switch technique {
        case "progressive_relaxation", "suggestibility_testing", "utilization":
            return .induction
        case "deepening_command", "countdown", "fractionation", "dissociation", "confusion_technique":
            return .deepening
        case "embedded_command", "direct_suggestion", "anchoring", "trigger_installation",
             "amnesia_suggestion", "brainwashing":
            return .suggestions
        case "emergence_sequence":
            return .emergence
        default:
            return nil
        }
    }

    private func defaultHypnosisArc(duration: TimeInterval) -> [PhaseSegment] {
        let boundaries: [(HypnosisMetadata.Phase, Double, Double)] = [
            (.induction, 0.00, 0.22),
            (.deepening, 0.22, 0.45),
            (.suggestions, 0.45, 0.85),
            (.emergence, 0.85, 1.00)
        ]
        return boundaries.map { phase, start, end in
            PhaseSegment(
                phase: phase,
                startTime: duration * start,
                endTime: duration * end,
                characteristics: "Conservative fallback hypnosis arc",
                tranceDepthEstimate: depthEstimate(for: phase),
                confidenceLevel: .low,
                confidenceRationale: "Fallback arc generated because hypnosis evidence was present but phase classification returned no segments"
            )
        }
    }

    private func depthEstimate(for phase: HypnosisMetadata.Phase) -> Double {
        switch phase {
        case .preTalk: return 0.15
        case .induction: return 0.35
        case .fractionation, .deepening, .confusion: return 0.65
        case .therapy, .suggestions, .eroticSuggestions, .conditioning, .brainwashing: return 0.80
        case .emergence: return 0.30
        case .transitional: return 0.45
        }
    }

    private func estimateDepth(from phases: [PhaseSegment]) -> HypnosisMetadata.TranceDeph {
        let maxDepth = phases.map(\.tranceDepthEstimate).max() ?? 0.5
        if maxDepth >= 0.85 { return .somnambulism }
        if maxDepth >= 0.65 { return .deep }
        if maxDepth >= 0.35 { return .medium }
        return .light
    }

    private func recommendedPreset(
        original: String,
        originalContentType: AudioContentType,
        resolvedContentType: AudioContentType
    ) -> String {
        guard originalContentType == .unknown,
              originalContentType != resolvedContentType else {
            return original
        }
        return "\(resolvedContentType.displayName) Session"
    }

    private func buildVoiceCharacteristics(
        from prosody: ProsodicProfile
    ) -> VoiceCharacteristics {
        let pauseDurations = prosody.pauses.map(\.duration)

        var tonal: [String] = []
        let avgPitch = prosody.averagePitch
        if avgPitch > 0 && avgPitch < 160 { tonal.append("low-pitched") }
        if avgPitch >= 160 && avgPitch < 220 { tonal.append("mid-range") }
        if avgPitch >= 220 { tonal.append("high-pitched") }

        let voicedPitchSamples = prosody.pitchCurve.filter { $0 > 0 }
        let pitchVariance = voicedPitchSamples
            .map { ($0 - avgPitch) * ($0 - avgPitch) }
            .reduce(0, +) / max(1, Double(voicedPitchSamples.count))
        if pitchVariance < 200 { tonal.append("monotone") }
        if pitchVariance > 1000 { tonal.append("expressive") }

        if prosody.averageSpeechRate < 100 { tonal.append("slow-paced") }
        if prosody.averageSpeechRate > 150 { tonal.append("rapid") }

        return VoiceCharacteristics(
            averagePace: prosody.averageSpeechRate,
            paceVariation: prosody.speechRateVariance,
            pausePatterns: pauseDurations,
            tonalQualities: tonal,
            volumePattern: inferVolumePattern(from: prosody.volumeCurve)
        )
    }

    private func inferVolumePattern(from curve: [Double]) -> String {
        guard curve.count >= 4 else { return "steady" }
        let quarterLen = curve.count / 4
        let firstQ = curve.prefix(quarterLen).reduce(0, +) / Double(quarterLen)
        let lastQ = curve.suffix(quarterLen).reduce(0, +) / Double(quarterLen)
        let diff = lastQ - firstQ
        if abs(diff) < 0.05 { return "steady" }
        if diff < -0.15 { return "gradually quieter" }
        if diff > 0.15 { return "gradually louder" }
        return "dynamic"
    }
}
