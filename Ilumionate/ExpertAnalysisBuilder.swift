//
//  ExpertAnalysisBuilder.swift
//  Ilumionate
//
//  Deterministic diagnostics for analyzer quality and label-review guidance.
//

import Foundation

nonisolated struct ExpertAnalysisBuilder: Sendable {

    func build(
        analysis: AnalysisResult,
        audioDuration: TimeInterval,
        transcription: AudioTranscriptionResult? = nil,
        prosody: ProsodicProfile? = nil,
        techniqueDetection: TechniqueDetectionResult? = nil,
        transcriptAnalysis: TranscriptAnalysis? = nil
    ) -> ExpertAnalysis {
        let duration = max(audioDuration, transcription?.duration ?? prosody?.totalDuration ?? 0)
        let phases = analysis.hypnosisMetadata?.phases.sorted { $0.startTime < $1.startTime } ?? []
        let isHypnosisLike = analysis.contentType.isHypnosisLike || !phases.isEmpty

        let coverage = phaseCoverage(phases: phases, duration: duration)
        let confidence = phaseConfidence(phases)
        let contentScore = contentTypeScore(analysis: analysis, phases: phases)
        let phaseScore = isHypnosisLike ? coverage : 1.0
        let prosodyScore = prosody == nil ? 0.45 : 1.0
        let transcriptScore = transcriptEvidenceScore(
            transcription: transcription,
            transcriptAnalysis: transcriptAnalysis
        )
        let techniqueScore = techniqueEvidenceScore(
            isHypnosisLike: isHypnosisLike,
            techniqueDetection: techniqueDetection,
            hypnosisMetadata: analysis.hypnosisMetadata
        )

        let weightedScore = contentScore * 0.18
            + phaseScore * 0.26
            + confidence * 0.20
            + prosodyScore * 0.14
            + transcriptScore * 0.14
            + techniqueScore * 0.08
        let qualityScore = clamp(weightedScore, lower: 0, upper: 1)
        let verdict = verdict(for: qualityScore, isHypnosisLike: isHypnosisLike, phases: phases)

        var findings = buildFindings(
            analysis: analysis,
            phases: phases,
            duration: duration,
            coverage: coverage,
            confidence: confidence,
            prosody: prosody,
            transcription: transcription,
            techniqueDetection: techniqueDetection,
            isHypnosisLike: isHypnosisLike
        )

        if findings.isEmpty {
            findings.append(.init(
                title: "Analyzer evidence is coherent",
                detail: "Content type, phase coverage, and timing evidence agree closely enough for generation.",
                severity: .info
            ))
        }

        let reviewMoments = buildReviewMoments(phases: phases, duration: duration)
        let actions = buildImprovementActions(
            findings: findings,
            isHypnosisLike: isHypnosisLike,
            phases: phases,
            coverage: coverage,
            prosody: prosody,
            transcription: transcription
        )

        return ExpertAnalysis(
            qualityScore: qualityScore,
            verdict: verdict,
            summary: summary(
                verdict: verdict,
                score: qualityScore,
                coverage: coverage,
                confidence: confidence,
                isHypnosisLike: isHypnosisLike,
                phaseCount: phases.count
            ),
            findings: findings,
            improvementActions: actions,
            reviewMoments: reviewMoments
        )
    }

    // MARK: - Scoring

    private func contentTypeScore(
        analysis: AnalysisResult,
        phases: [PhaseSegment]
    ) -> Double {
        if analysis.contentType.isHypnosisLike {
            return 1.0
        }
        if !phases.isEmpty {
            return analysis.contentType == .unknown ? 0.72 : 0.55
        }
        return analysis.contentType == .unknown ? 0.35 : 0.80
    }

    private func phaseCoverage(
        phases: [PhaseSegment],
        duration: TimeInterval
    ) -> Double {
        guard duration > 0, !phases.isEmpty else { return 0 }
        let covered = phases.reduce(0.0) { total, phase in
            total + max(0, min(duration, phase.endTime) - max(0, phase.startTime))
        }
        return clamp(covered / duration, lower: 0, upper: 1)
    }

    private func phaseConfidence(_ phases: [PhaseSegment]) -> Double {
        guard !phases.isEmpty else { return 0.40 }
        let total = phases.reduce(0.0) { $0 + $1.confidenceLevel.numericValue }
        return total / Double(phases.count)
    }

    private func transcriptEvidenceScore(
        transcription: AudioTranscriptionResult?,
        transcriptAnalysis: TranscriptAnalysis?
    ) -> Double {
        if let transcriptAnalysis, !transcriptAnalysis.sections.isEmpty {
            return 1.0
        }
        if let text = transcription?.fullText, text.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 {
            return 0.85
        }
        return 0.45
    }

    private func techniqueEvidenceScore(
        isHypnosisLike: Bool,
        techniqueDetection: TechniqueDetectionResult?,
        hypnosisMetadata: HypnosisMetadata?
    ) -> Double {
        guard isHypnosisLike else { return 0.85 }
        if techniqueDetection?.markers.isEmpty == false || techniqueDetection?.techniques.isEmpty == false {
            return 1.0
        }
        if hypnosisMetadata?.detectedTechniques.isEmpty == false || hypnosisMetadata?.languagePatterns.isEmpty == false {
            return 0.85
        }
        return 0.55
    }

    private func verdict(
        for score: Double,
        isHypnosisLike: Bool,
        phases: [PhaseSegment]
    ) -> ExpertAnalysis.Verdict {
        if isHypnosisLike && phases.isEmpty {
            return .needsRelabeling
        }
        if score >= 0.85 {
            return .productionReady
        }
        if score >= 0.65 {
            return .reviewRecommended
        }
        return .needsRelabeling
    }

    // MARK: - Findings

    private func buildFindings(
        analysis: AnalysisResult,
        phases: [PhaseSegment],
        duration: TimeInterval,
        coverage: Double,
        confidence: Double,
        prosody: ProsodicProfile?,
        transcription: AudioTranscriptionResult?,
        techniqueDetection: TechniqueDetectionResult?,
        isHypnosisLike: Bool
    ) -> [ExpertAnalysis.Finding] {
        var findings: [ExpertAnalysis.Finding] = []

        if isHypnosisLike && phases.isEmpty {
            findings.append(.init(
                title: "Missing hypnosis phase timeline",
                detail: "The content appears hypnosis-like but no usable phase segments were produced.",
                severity: .critical
            ))
        }

        if !analysis.contentType.isHypnosisLike && !phases.isEmpty {
            findings.append(.init(
                title: "Content type disagrees with phase evidence",
                detail: "Phase analysis found hypnosis structure while the broad classifier returned \(analysis.contentType.displayName).",
                severity: analysis.contentType == .unknown ? .warning : .critical
            ))
        }

        if isHypnosisLike && coverage < 0.80 {
            findings.append(.init(
                title: "Phase coverage is incomplete",
                detail: "Detected phases cover \(percent(coverage)) of the audio. Uncovered spans can create generic or unstable light-score regions.",
                severity: coverage < 0.55 ? .critical : .warning
            ))
        }

        let gaps = timelineGaps(phases: phases, duration: duration)
        if !gaps.isEmpty {
            findings.append(.init(
                title: "Timeline gaps need review",
                detail: "\(gaps.count) uncovered span\(gaps.count == 1 ? "" : "s") larger than four seconds were found between phase segments.",
                severity: gaps.count > 2 ? .warning : .info
            ))
        }

        let lowConfidence = phases.filter { $0.confidenceLevel == .low }
        if !lowConfidence.isEmpty {
            findings.append(.init(
                title: "Low-confidence phase labels",
                detail: "\(lowConfidence.count) phase segment\(lowConfidence.count == 1 ? "" : "s") should be reviewed or reinforced with better phrase evidence.",
                severity: lowConfidence.count >= max(2, phases.count / 3) ? .warning : .info
            ))
        } else if isHypnosisLike && confidence >= 0.75 {
            findings.append(.init(
                title: "Phase confidence is strong",
                detail: "Average phase confidence is \(percent(confidence)), which is enough to trust phase-guided light generation.",
                severity: .info
            ))
        }

        if prosody == nil {
            findings.append(.init(
                title: "Prosody evidence unavailable",
                detail: "The analyzer could not use speech rate, volume, pitch, or pause timing. Light scores will rely more heavily on transcript phases.",
                severity: .warning
            ))
        } else if let prosody, prosody.pauses.count > max(20, Int(duration / 12.0)) {
            findings.append(.init(
                title: "Dense pause map detected",
                detail: "Pause detection produced \(prosody.pauses.count) pause candidates. Long-form smoothing should throttle these before scoring.",
                severity: .warning
            ))
        }

        if transcription?.segments.isEmpty != false {
            findings.append(.init(
                title: "Transcript evidence is thin",
                detail: "No transcript segments were available for phrase-level phase validation.",
                severity: .warning
            ))
        }

        if isHypnosisLike,
           techniqueDetection?.markers.isEmpty != false,
           techniqueDetection?.techniques.isEmpty != false,
           analysis.hypnosisMetadata?.languagePatterns.isEmpty != false {
            findings.append(.init(
                title: "Few hypnotic technique markers",
                detail: "The phase model found structure, but there are limited technique or phrase markers explaining why.",
                severity: .info
            ))
        }

        return findings
    }

    private func buildReviewMoments(
        phases: [PhaseSegment],
        duration: TimeInterval
    ) -> [ExpertAnalysis.ReviewMoment] {
        var moments: [ExpertAnalysis.ReviewMoment] = []

        for phase in phases where phase.confidenceLevel == .low {
            moments.append(.init(
                time: phase.startTime,
                phase: phase.phase.labelingPhase,
                reason: "Low-confidence \(phase.phase.labelingPhase.displayName) segment"
            ))
        }

        for gap in timelineGaps(phases: phases, duration: duration).prefix(5) {
            moments.append(.init(
                time: gap.start,
                phase: nil,
                reason: "Uncovered analyzer gap: \(formatTime(gap.start))-\(formatTime(gap.end))"
            ))
        }

        return Array(moments.sorted { $0.time < $1.time }.prefix(8))
    }

    private func buildImprovementActions(
        findings: [ExpertAnalysis.Finding],
        isHypnosisLike: Bool,
        phases: [PhaseSegment],
        coverage: Double,
        prosody: ProsodicProfile?,
        transcription: AudioTranscriptionResult?
    ) -> [ExpertAnalysis.ImprovementAction] {
        var actions: [ExpertAnalysis.ImprovementAction] = []

        if isHypnosisLike && phases.isEmpty {
            actions.append(.init(
                priority: 1,
                title: "Add phase labels before tuning light scores",
                detail: "Create or import a labeled phase timeline for this file, then rerun analyzer optimization against it."
            ))
        }

        if coverage < 0.80 && !phases.isEmpty {
            actions.append(.init(
                priority: 1,
                title: "Review uncovered timeline spans",
                detail: "Label gaps around the listed review moments so the generator can stay phase-guided for the full file."
            ))
        }

        if phases.contains(where: { $0.confidenceLevel == .low }) {
            actions.append(.init(
                priority: 2,
                title: "Strengthen phase phrase evidence",
                detail: "Add distinctive transcript phrases from low-confidence segments to the phrase library or corpus examples."
            ))
        }

        if prosody == nil {
            actions.append(.init(
                priority: 2,
                title: "Inspect prosody extraction",
                detail: "Prosody was unavailable, so pause-response and intensity modulation cannot be validated for this file."
            ))
        }

        if transcription?.segments.isEmpty != false {
            actions.append(.init(
                priority: 2,
                title: "Regenerate transcript timing",
                detail: "Phrase classification improves when Whisper segments include reliable timestamps and confidence values."
            ))
        }

        if actions.isEmpty {
            actions.append(.init(
                priority: 3,
                title: "Use this file as a positive regression case",
                detail: "The analyzer evidence is coherent; keep this result in the corpus to protect future analyzer changes."
            ))
        }

        return actions.sorted { $0.priority < $1.priority }
    }

    // MARK: - Helpers

    private func timelineGaps(
        phases: [PhaseSegment],
        duration: TimeInterval
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        guard duration > 0, !phases.isEmpty else { return [] }

        var gaps: [(TimeInterval, TimeInterval)] = []
        var cursor: TimeInterval = 0
        for phase in phases.sorted(by: { $0.startTime < $1.startTime }) {
            let start = clamp(phase.startTime, lower: 0, upper: duration)
            let end = clamp(phase.endTime, lower: start, upper: duration)
            if start - cursor > 4.0 {
                gaps.append((cursor, start))
            }
            cursor = max(cursor, end)
        }

        if duration - cursor > 4.0 {
            gaps.append((cursor, duration))
        }

        return gaps
    }

    private func summary(
        verdict: ExpertAnalysis.Verdict,
        score: Double,
        coverage: Double,
        confidence: Double,
        isHypnosisLike: Bool,
        phaseCount: Int
    ) -> String {
        if isHypnosisLike {
            return "\(verdict.displayName): \(phaseCount) phase segments, \(percent(coverage)) timeline coverage, \(percent(confidence)) average phase confidence."
        }
        return "\(verdict.displayName): \(percent(score)) analyzer quality for non-hypnosis content."
    }

    private func percent(_ value: Double) -> String {
        "\(Int((clamp(value, lower: 0, upper: 1) * 100).rounded()))%"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}
