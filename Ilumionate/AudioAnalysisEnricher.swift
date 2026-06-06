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
struct AudioAnalysisEnricher: Sendable {

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
        } else {
            hypnosisMetadata = analysis.hypnosisMetadata
        }

        let transcriptAnalyzer = TranscriptFeatureAnalyzer()
        let transcriptAnalysis = transcriptAnalyzer.analyze(
            transcription: transcription,
            phases: hypnosisMetadata?.phases
        )

        return AnalysisResult(
            mood: analysis.mood,
            energyLevel: analysis.energyLevel,
            suggestedFrequencyRange: analysis.suggestedFrequencyRange,
            suggestedIntensity: analysis.suggestedIntensity,
            suggestedColorTemperature: analysis.suggestedColorTemperature,
            keyMoments: analysis.keyMoments,
            aiSummary: analysis.aiSummary,
            recommendedPreset: analysis.recommendedPreset,
            contentType: analysis.contentType,
            hypnosisMetadata: hypnosisMetadata,
            temporalAnalysis: analysis.temporalAnalysis,
            voiceCharacteristics: voiceCharacteristics,
            classificationConfidence: analysis.classificationConfidence,
            prosodicProfile: resolvedProsody,
            techniqueDetection: techniqueDetection,
            transcriptAnalysis: transcriptAnalysis
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
