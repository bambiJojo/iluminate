//
//  HypnosisPhaseAnalyzer.swift
//  Ilumionate
//
//  Keyword-based hypnosis phase detector.
//  Acts as fallback when Apple Intelligence is unavailable, and as a
//  pre-processing stage that the ChunkedPhaseAnalyzer can calibrate against.
//
//  Pipeline:
//   1. Convert WhisperKit transcript segments to approximate word timestamps.
//   2. Build a per-second hit map by scanning words against the keyword taxonomy.
//   3. Resolve each second to its best-scoring phase using a ±5s context window.
//   4. Normalize legacy phase labels while preserving supported phase returns.
//   5. Majority-vote smooth the timeline to eliminate single-word spikes.
//   6. Collapse short runs (<45s) to remove boundary oscillation.
//   7. Consolidate into PhaseSegment spans.
//

import Foundation


// MARK: - Analyzer

/// Keyword-based hypnosis phase analyzer.
/// All methods are pure — the same input always produces the same output.
nonisolated struct HypnosisPhaseAnalyzer: Sendable {

    struct PhaseEvidenceBreakdown: Identifiable, Sendable {
        var id: HypnosisMetadata.Phase { phase }

        let phase: HypnosisMetadata.Phase
        let totalScore: Double
        let transcriptScore: Double
        let phraseLibraryScore: Double
        let waymarkerScore: Double
        let positionScore: Double
        let transitionScore: Double
        let matchedPhrases: [String]
    }

    struct PhaseEvidenceWindow: Identifiable, Sendable {
        let id: UUID
        let startTime: TimeInterval
        let endTime: TimeInterval
        let phase: HypnosisMetadata.Phase
        let confidence: Double
        let confidenceLevel: HypnosisMetadata.ConfidenceLevel
        let rationale: String
        let evidence: [PhaseEvidenceBreakdown]
        let topPhrases: [TranscriptPhraseStatistic]
        let topWaymarkers: [HypnosisWaymarkerMatch]
    }

    struct PhaseSuggestionTimeline: Sendable {
        let windows: [PhaseEvidenceWindow]
        let segments: [PhaseSegment]

        var averageConfidence: Double {
            guard !windows.isEmpty else { return 0 }
            return windows.reduce(0.0) { $0 + $1.confidence } / Double(windows.count)
        }
    }

    let config: AnalyzerConfig.KeywordPipeline
    let hybridSelection: AnalyzerConfig.HybridSelection
    let corpusLearning: AnalyzerConfig.CorpusLearning
    let boundaryRefinement: AnalyzerConfig.BoundaryRefinement
    private let corpusKnowledge: CorpusPhaseKnowledge
    private let keywordTokensByPhase: [HypnosisMetadata.Phase: Set<String>]
    private let keywordPhrasesByPhase: [HypnosisMetadata.Phase: Set<String>]

    /// Convenience entry point: loads the resolved config and optionally overrides
    /// just the keyword pipeline. Delegates to the canonical initializer so the
    /// property-assignment list lives in exactly one place.
    init(
        config: AnalyzerConfig.KeywordPipeline? = nil,
        corpusKnowledge: CorpusPhaseKnowledge? = nil
    ) {
        self.init(
            config: AnalyzerConfigLoader.load(),
            keywordPipelineOverride: config,
            corpusKnowledge: corpusKnowledge
        )
    }

    /// Canonical initializer — single source of truth for property assignment.
    init(
        config: AnalyzerConfig,
        keywordPipelineOverride: AnalyzerConfig.KeywordPipeline? = nil,
        corpusKnowledge: CorpusPhaseKnowledge? = nil
    ) {
        self.config = keywordPipelineOverride ?? config.keywordPipeline
        self.hybridSelection = config.hybridSelection
        self.corpusLearning = config.corpusLearning
        self.boundaryRefinement = config.boundaryRefinement
        let knowledge = corpusKnowledge ?? CorpusPhaseKnowledgeCache.shared.knowledge()
        self.corpusKnowledge = knowledge
        self.keywordTokensByPhase = Dictionary(uniqueKeysWithValues: HypnosisMetadata.Phase.allCases.map { phase in
            (
                phase,
                Self.makeKeywordTokens(
                    for: phase,
                    knowledge: knowledge,
                    corpusLearning: config.corpusLearning
                )
            )
        })
        self.keywordPhrasesByPhase = Dictionary(uniqueKeysWithValues: HypnosisMetadata.Phase.allCases.map { phase in
            (
                phase,
                Self.makeKeywordPhrases(
                    for: phase,
                    knowledge: knowledge,
                    corpusLearning: config.corpusLearning
                )
            )
        })
    }

    // MARK: - Public Entry Point

    /// Converts WhisperKit segments into approximate word timestamps, then
    /// runs the full keyword pipeline to produce `PhaseSegment` spans.
    func analyze(
        segments: [AudioTranscriptionSegment],
        duration: Double
    ) -> [PhaseSegment] {
        let wordTimestamps = approximateWordTimestamps(from: segments)
        guard !wordTimestamps.isEmpty else { return [] }

        return analyze(
            wordTimestamps: wordTimestamps,
            transcription: makeTranscription(segments: segments, duration: duration),
            techniqueDetection: nil
        )
    }

    func analyze(
        wordTimestamps: [WordTimestamp],
        duration: Double,
        techniqueDetection: TechniqueDetectionResult? = nil
    ) -> [PhaseSegment] {
        guard !wordTimestamps.isEmpty, Task.isCancelled == false else { return [] }

        let bucketCount = max(1, Int(ceil(duration)))
        var hitMap = buildHitMap(wordTimestamps: wordTimestamps, bucketCount: bucketCount)
        let techniqueEvidence = techniqueEvidenceMap(
            from: techniqueDetection,
            bucketCount: bucketCount
        )
        mergeTechniqueEvidence(techniqueEvidence, into: &hitMap)
        guard Task.isCancelled == false else { return [] }
        var timeline = resolveTimeline(hitMap: hitMap, bucketCount: bucketCount)

        // Denoise before canonicalizing phase labels. Sustained returns to an earlier
        // structural phase are valid (for example suggestions → deepening), while
        // smoothing and short-run collapse remove transient classification spikes.
        timeline = majorityVoteSmooth(timeline: timeline, windowSize: config.smoothingWindowSize)
        timeline = collapseShortRuns(
            timeline,
            minRun: max(config.minimumPhaseDurationSeconds, Int(duration * config.collapseThresholdFraction))
        )
        guard Task.isCancelled == false else { return [] }
        timeline = enforcePhaseOrdering(timeline: timeline)

        let phaseSegments = consolidatePhaseSegments(timeline: timeline, duration: duration)
        return repairOpeningActivePhase(
            phaseSegments,
            wordTimestamps: wordTimestamps,
            duration: duration
        )
    }

    func analyze(
        wordTimestamps: [WordTimestamp],
        transcription: AudioTranscriptionResult,
        techniqueDetection: TechniqueDetectionResult? = nil
    ) -> [PhaseSegment] {
        let phaseSegments = analyze(
            wordTimestamps: wordTimestamps,
            duration: transcription.duration,
            techniqueDetection: techniqueDetection
        )
        guard !phaseSegments.isEmpty else {
            return suggestPhaseTimeline(for: transcription).segments
        }
        return adaptPredictedPhases(
            phaseSegments,
            transcription: transcription
        )
    }

    /// Converts WhisperKit segments directly to a PhaseSegment array,
    /// using the full pipeline. Public entry point for callers that
    /// already have AudioTranscriptionResult.
    func analyzeTranscription(
        _ transcription: AudioTranscriptionResult
    ) -> [PhaseSegment] {
        let preparedTranscription: AudioTranscriptionResult
        if transcription.segments.isEmpty, transcription.fullText.isEmpty == false {
            preparedTranscription = AudioTranscriptionResult(
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
        } else {
            preparedTranscription = transcription
        }

        let wordTimestamps = approximateWordTimestamps(from: preparedTranscription.segments)
        return analyze(
            wordTimestamps: wordTimestamps,
            transcription: preparedTranscription
        )
    }

    func suggestPhaseTimeline(
        for transcription: AudioTranscriptionResult
    ) -> PhaseSuggestionTimeline {
        let transcriptAnalyzer = TranscriptFeatureAnalyzer()
        let transcriptAnalysis = transcriptAnalyzer.analyze(transcription: transcription)
        return suggestPhaseTimeline(
            for: transcription,
            transcriptAnalysis: transcriptAnalysis,
            transcriptAnalyzer: transcriptAnalyzer
        )
    }

    func adaptPredictedPhases(
        _ phaseSegments: [PhaseSegment],
        transcription: AudioTranscriptionResult
    ) -> [PhaseSegment] {
        guard !phaseSegments.isEmpty else { return [] }

        let transcriptAnalyzer = TranscriptFeatureAnalyzer()
        let transcriptAnalysis = transcriptAnalyzer.analyze(
            transcription: transcription,
            phases: phaseSegments
        )
        let relabeledSegments = enforcePhaseOrdering(
            phaseSegments: refinePhaseAssignments(phaseSegments, transcriptAnalysis: transcriptAnalysis)
        )
        let boundaryAdjustedSegments = refinePhaseBoundaries(
            relabeledSegments,
            transcription: transcription,
            transcriptAnalyzer: transcriptAnalyzer
        )
        let proposalTimeline = suggestPhaseTimeline(
            for: transcription,
            transcriptAnalysis: transcriptAnalysis,
            transcriptAnalyzer: transcriptAnalyzer
        )
        let selected = selectBestAdaptedSegments(
            primarySegments: boundaryAdjustedSegments,
            proposalSegments: proposalTimeline.segments,
            transcription: transcription,
            transcriptAnalyzer: transcriptAnalyzer
        )
        let repairedSegments = repairUnsupportedPhaseAssignments(
            selected.segments,
            transcription: transcription,
            transcriptAnalyzer: transcriptAnalyzer
        )
        let terminalRepairedSegments = restoreTerminalEmergenceCue(
            repairedSegments,
            transcription: transcription
        )
        let orderedSegments = preventSuggestionRegressionAfterConditioning(
            terminalRepairedSegments
        )
        let stabilizedSegments = stabilizeAdaptedPhaseRuns(
            orderedSegments,
            baselineSegments: phaseSegments,
            duration: transcription.duration
        )
        let repairedAnalysis = transcriptAnalyzer.analyze(
            transcription: transcription,
            phases: stabilizedSegments
        )
        return enrichSegmentsWithTranscriptConfidence(
            stabilizedSegments,
            transcriptAnalysis: repairedAnalysis
        )
    }

    func qualityScore(
        for phaseSegments: [PhaseSegment],
        transcription: AudioTranscriptionResult
    ) -> Double {
        guard !phaseSegments.isEmpty else { return 0 }
        let transcriptAnalysis = TranscriptFeatureAnalyzer().analyze(
            transcription: transcription,
            phases: phaseSegments
        )
        return intrinsicQualityScore(for: phaseSegments, transcriptAnalysis: transcriptAnalysis)
    }

    func selectPreferredPhases(
        keywordPhases: [PhaseSegment],
        chunkedPhases: [PhaseSegment]?,
        transcription: AudioTranscriptionResult,
        techniqueDetection: TechniqueDetectionResult? = nil
    ) -> (phases: [PhaseSegment], usedChunkedAnalyzer: Bool) {
        let adaptedChunked = chunkedPhases.map { adaptPredictedPhases($0, transcription: transcription) } ?? []

        guard !adaptedChunked.isEmpty else {
            return (keywordPhases, false)
        }
        guard !keywordPhases.isEmpty else {
            return (adaptedChunked, true)
        }

        let keywordScore = sourceSelectionQualityScore(
            for: keywordPhases,
            transcription: transcription
        )
        let chunkedScore = sourceSelectionQualityScore(
            for: adaptedChunked,
            transcription: transcription
        )
        let techniqueEvidence = techniqueEvidenceMap(
            from: techniqueDetection,
            bucketCount: max(1, Int(ceil(transcription.duration)))
        )
        let keywordTechniqueAlignment = techniqueAlignmentScore(
            for: keywordPhases,
            techniqueEvidence: techniqueEvidence,
            duration: transcription.duration
        )
        let chunkedTechniqueAlignment = techniqueAlignmentScore(
            for: adaptedChunked,
            techniqueEvidence: techniqueEvidence,
            duration: transcription.duration
        )
        let keywordSelectionScore = keywordScore + (keywordTechniqueAlignment * hybridSelection.techniqueAlignmentWeight)
        let chunkedSelectionScore = chunkedScore + (chunkedTechniqueAlignment * hybridSelection.techniqueAlignmentWeight)
        let keywordDistinctPhases = Set(keywordPhases.map(\.phase)).count
        let chunkedDistinctPhases = Set(adaptedChunked.map(\.phase)).count

        let chunkedWinsClearly = chunkedSelectionScore >= keywordSelectionScore + hybridSelection.chunkedClearWinMargin
        let chunkedWinsNarrowlyWithBetterCoverage =
            chunkedSelectionScore >= keywordSelectionScore + hybridSelection.chunkedCoverageWinMargin
            && chunkedDistinctPhases > keywordDistinctPhases
        let keywordLooksCollapsed =
            keywordDistinctPhases < 2 &&
            chunkedDistinctPhases >= 2 &&
            chunkedSelectionScore >= keywordSelectionScore - hybridSelection.keywordCollapsedMargin

        if let ensembled = ensemblePhases(
            keywordPhases: keywordPhases,
            chunkedPhases: adaptedChunked,
            transcription: transcription,
            keywordScore: keywordSelectionScore,
            chunkedScore: chunkedSelectionScore,
            techniqueEvidence: techniqueEvidence
        ) {
            let ensembleScore = sourceSelectionQualityScore(
                for: ensembled,
                transcription: transcription
            )
            let ensembleTechniqueAlignment = techniqueAlignmentScore(
                for: ensembled,
                techniqueEvidence: techniqueEvidence,
                duration: transcription.duration
            )
            let finalEnsembleScore = ensembleScore + (ensembleTechniqueAlignment * hybridSelection.techniqueAlignmentWeight)
            let bestSingleScore = max(keywordSelectionScore, chunkedSelectionScore)
            let sourceDisagreement = 1.0 - timelineAgreementRatio(
                lhs: keywordPhases,
                rhs: adaptedChunked,
                duration: transcription.duration
            )
            let ensembleIsCompetitive = finalEnsembleScore >= bestSingleScore - hybridSelection.ensembleCompetitiveMargin
            let ensembleAddressesMeaningfulDisagreement = sourceDisagreement >= hybridSelection.ensembleDisagreementThreshold

            if ensembleIsCompetitive || ensembleAddressesMeaningfulDisagreement {
                let keywordMatch = timelineAgreementRatio(
                    lhs: ensembled,
                    rhs: keywordPhases,
                    duration: transcription.duration
                )
                let chunkedMatch = timelineAgreementRatio(
                    lhs: ensembled,
                    rhs: adaptedChunked,
                    duration: transcription.duration
                )
                return (ensembled, chunkedMatch >= keywordMatch + hybridSelection.ensembleChunkedSourceLead)
            }
        }

        if chunkedWinsClearly || chunkedWinsNarrowlyWithBetterCoverage || keywordLooksCollapsed {
            return (adaptedChunked, true)
        }

        return (keywordPhases, false)
    }

    private func ensemblePhases(
        keywordPhases: [PhaseSegment],
        chunkedPhases: [PhaseSegment],
        transcription: AudioTranscriptionResult,
        keywordScore: Double,
        chunkedScore: Double,
        techniqueEvidence: [[HypnosisMetadata.Phase: Double]]
    ) -> [PhaseSegment]? {
        let bucketCount = max(1, Int(ceil(transcription.duration)))
        let keywordTimeline = phaseTimeline(from: keywordPhases, bucketCount: bucketCount)
        let chunkedTimeline = phaseTimeline(from: chunkedPhases, bucketCount: bucketCount)
        let transcriptAnalysis = ensembleTranscriptAnalysis(
            transcription: transcription,
            keywordPhases: keywordPhases,
            chunkedPhases: chunkedPhases
        )
        let keywordVoteWeight = sourceVoteWeight(for: keywordScore)
        let chunkedVoteWeight = sourceVoteWeight(for: chunkedScore)

        var ensembledTimeline = [HypnosisMetadata.Phase?](repeating: nil, count: bucketCount)

        for secondIndex in 0..<bucketCount {
            let candidates = Set([
                keywordTimeline[secondIndex],
                chunkedTimeline[secondIndex]
            ].compactMap { $0 })

            guard !candidates.isEmpty else { continue }

            let time = min(Double(secondIndex) + 0.5, transcription.duration)
            let transcriptSection = transcriptAnalysis.section(at: time)
            let previousPhase = secondIndex > 0 ? ensembledTimeline[secondIndex - 1] : nil

            let bestPhase = candidates.max { lhs, rhs in
                let lhsScore = ensembleCandidateScore(
                    phase: lhs,
                    time: time,
                    transcriptSection: transcriptSection,
                    previousPhase: previousPhase,
                    keywordPhase: keywordTimeline[secondIndex],
                    chunkedPhase: chunkedTimeline[secondIndex],
                    techniqueSupport: clamp(
                        techniqueEvidence[secondIndex][lhs] ?? 0.0,
                        lower: 0.0,
                        upper: 1.2
                    ),
                    keywordVoteWeight: keywordVoteWeight,
                    chunkedVoteWeight: chunkedVoteWeight
                )
                let rhsScore = ensembleCandidateScore(
                    phase: rhs,
                    time: time,
                    transcriptSection: transcriptSection,
                    previousPhase: previousPhase,
                    keywordPhase: keywordTimeline[secondIndex],
                    chunkedPhase: chunkedTimeline[secondIndex],
                    techniqueSupport: clamp(
                        techniqueEvidence[secondIndex][rhs] ?? 0.0,
                        lower: 0.0,
                        upper: 1.2
                    ),
                    keywordVoteWeight: keywordVoteWeight,
                    chunkedVoteWeight: chunkedVoteWeight
                )
                return lhsScore < rhsScore
            }

            ensembledTimeline[secondIndex] = bestPhase
        }

        ensembledTimeline = enforcePhaseOrdering(timeline: ensembledTimeline)
        ensembledTimeline = majorityVoteSmooth(timeline: ensembledTimeline, windowSize: config.smoothingWindowSize)
        ensembledTimeline = collapseShortRuns(
            ensembledTimeline,
            minRun: max(config.minimumPhaseDurationSeconds, Int(transcription.duration * config.collapseThresholdFraction))
        )

        let segments = consolidatePhaseSegments(timeline: ensembledTimeline, duration: transcription.duration)
        guard Set(segments.map(\.phase)).count >= 2 else { return nil }

        return adaptPredictedPhases(segments, transcription: transcription)
    }

    private func ensembleTranscriptAnalysis(
        transcription: AudioTranscriptionResult,
        keywordPhases: [PhaseSegment],
        chunkedPhases: [PhaseSegment]
    ) -> TranscriptAnalysis {
        let boundaries = Set(
            [0.0, transcription.duration]
                + keywordPhases.flatMap { [$0.startTime, $0.endTime] }
                + chunkedPhases.flatMap { [$0.startTime, $0.endTime] }
        )
        .sorted()

        let seeds = zip(boundaries, boundaries.dropFirst()).compactMap { startTime, endTime -> PhaseSegment? in
            guard endTime > startTime else { return nil }
            return PhaseSegment(
                phase: .transitional,
                startTime: startTime,
                endTime: endTime,
                characteristics: "Consensus Window",
                tranceDepthEstimate: HypnosisMetadata.Phase.transitional.tranceDepthEstimate
            )
        }

        return TranscriptFeatureAnalyzer().analyze(
            transcription: transcription,
            phases: seeds
        )
    }

    private func ensembleCandidateScore(
        phase: HypnosisMetadata.Phase,
        time: TimeInterval,
        transcriptSection: TranscriptSectionMetrics?,
        previousPhase: HypnosisMetadata.Phase?,
        keywordPhase: HypnosisMetadata.Phase?,
        chunkedPhase: HypnosisMetadata.Phase?,
        techniqueSupport: Double,
        keywordVoteWeight: Double,
        chunkedVoteWeight: Double
    ) -> Double {
        var score = transcriptSection.map { transcriptSupportScore(for: phase, section: $0) * hybridSelection.transcriptSupportWeight } ?? 0.2

        if keywordPhase == phase {
            score += keywordVoteWeight
        }
        if chunkedPhase == phase {
            score += chunkedVoteWeight
        }
        if keywordPhase == phase, chunkedPhase == phase {
            score += hybridSelection.consensusBonus
        }
        score += techniqueSupport * hybridSelection.techniqueSupportWeight

        if let previousPhase {
            if previousPhase == phase {
                score += hybridSelection.continuityBonus
            } else if
                let previousIndex = Self.orderedPhases.firstIndex(of: previousPhase),
                let currentIndex = Self.orderedPhases.firstIndex(of: phase),
                currentIndex < previousIndex {
                score -= hybridSelection.backwardJumpPenalty
            } else {
                score += transitionPrior(from: previousPhase, to: phase) * hybridSelection.transitionPriorWeight
            }
        }

        return score
    }

    private func sourceVoteWeight(for sourceQuality: Double) -> Double {
        clamp(
            (sourceQuality * hybridSelection.keywordVoteScale) + hybridSelection.keywordVoteBias,
            lower: 0.15,
            upper: 0.60
        )
    }

    private func phaseTimeline(
        from phases: [PhaseSegment],
        bucketCount: Int
    ) -> [HypnosisMetadata.Phase?] {
        var timeline = [HypnosisMetadata.Phase?](repeating: nil, count: bucketCount)
        for segment in phases {
            let start = max(0, min(Int(segment.startTime), bucketCount - 1))
            let end = max(start + 1, min(Int(ceil(segment.endTime)), bucketCount))
            for index in start..<end {
                timeline[index] = segment.phase
            }
        }
        return timeline
    }

    private func timelineAgreementRatio(
        lhs: [PhaseSegment],
        rhs: [PhaseSegment],
        duration: TimeInterval
    ) -> Double {
        let bucketCount = max(1, Int(ceil(duration)))
        let lhsTimeline = phaseTimeline(from: lhs, bucketCount: bucketCount)
        let rhsTimeline = phaseTimeline(from: rhs, bucketCount: bucketCount)
        let agreementCount = zip(lhsTimeline, rhsTimeline).reduce(0) { partial, pair in
            partial + (pair.0 == pair.1 ? 1 : 0)
        }
        return Double(agreementCount) / Double(bucketCount)
    }

    private func techniqueEvidenceMap(
        from techniqueDetection: TechniqueDetectionResult?,
        bucketCount: Int
    ) -> [[HypnosisMetadata.Phase: Double]] {
        var evidence = [[HypnosisMetadata.Phase: Double]](
            repeating: [:],
            count: bucketCount
        )
        guard let techniqueDetection else { return evidence }

        for marker in techniqueDetection.markers {
            let hints = phaseHints(for: marker.type)
            guard !hints.isEmpty else { continue }

            let center = max(0, min(Int(marker.timestamp), bucketCount - 1))
            let radius = techniqueSpreadRadius(for: marker.type)
            let lower = max(0, center - radius)
            let upper = min(bucketCount - 1, center + radius)

            for bucket in lower...upper {
                let recency = 1.0 - (Double(abs(bucket - center)) / Double(radius + 1))
                for (phase, weight) in hints {
                    evidence[bucket][phase, default: 0.0] += weight * marker.strength * recency
                }
            }
        }

        return evidence
    }

    private func mergeTechniqueEvidence(
        _ techniqueEvidence: [[HypnosisMetadata.Phase: Double]],
        into hitMap: inout [[HypnosisMetadata.Phase: Double]]
    ) {
        guard hitMap.count == techniqueEvidence.count else { return }
        for index in hitMap.indices {
            for (phase, score) in techniqueEvidence[index] {
                hitMap[index][phase, default: 0.0] += score
            }
        }
    }

    private func techniqueAlignmentScore(
        for phaseSegments: [PhaseSegment],
        techniqueEvidence: [[HypnosisMetadata.Phase: Double]],
        duration: TimeInterval
    ) -> Double {
        guard !phaseSegments.isEmpty else { return 0.0 }
        let totalEvidence = techniqueEvidence.reduce(0.0) { partial, bucket in
            partial + bucket.values.reduce(0.0, +)
        }
        guard totalEvidence > 0 else { return 0.0 }

        let bucketCount = max(1, Int(ceil(duration)))
        let timeline = phaseTimeline(from: phaseSegments, bucketCount: bucketCount)
        let alignedEvidence = zip(timeline, techniqueEvidence).reduce(0.0) { partial, pair in
            guard let phase = pair.0 else { return partial }
            return partial + (pair.1[phase] ?? 0.0)
        }

        return clamp(alignedEvidence / totalEvidence, lower: 0.0, upper: 1.0)
    }

    private func phaseHints(
        for markerType: LinguisticMarker.MarkerType
    ) -> [(HypnosisMetadata.Phase, Double)] {
        switch markerType {
        case .normalization, .expectationSetting, .rapportBuilding, .suggestibilityTesting:
            return [(.induction, 2.4)]

        case .eyeFixation, .breathingFocus, .progressiveRelaxation, .sensoryNarrowing, .pacingExperience:
            return [(.induction, 2.4)]

        case .countingDown, .descendingImagery, .heavinessContrast, .timeDistortion:
            return [(.deepening, 2.6)]
        case .fractionation:
            return [(.deepening, 3.0), (.induction, 0.8)]

        case .directSuggestion, .egoStrengthening:
            return [(.suggestions, 2.2)]
        case .indirectSuggestion:
            return [(.therapy, 1.6), (.suggestions, 1.0)]
        case .metaphoricalStory, .reframing, .partsBased, .utilizationOfResponse:
            return [(.therapy, 2.2)]
        case .embeddedCommand:
            return [(.suggestions, 2.0), (.conditioning, 0.8)]

        case .futurePacing, .anchoringResponse, .triggerInstallation, .causeEffectFraming:
            return [(.conditioning, 2.7)]

        case .countingUp, .eyeOpening, .physicalReengagement, .temporalOrientation:
            return [(.emergence, 2.8)]

        case .pacingAndLeading, .ambiguousLanguage, .conversationalTrance:
            return [(.therapy, 1.6), (.induction, 0.8)]

        case .confusionTechnique, .doubleBinding:
            return [(.deepening, 1.7), (.suggestions, 0.9), (.induction, 0.5)]
        case .amnesiaSuggestion, .dissociation, .ageRegression, .hallucination:
            return [(.suggestions, 1.5), (.therapy, 0.8)]
        case .brainwashing:
            return [(.brainwashing, 2.8)]
        }
    }

    private func techniqueSpreadRadius(
        for markerType: LinguisticMarker.MarkerType
    ) -> Int {
        switch markerType {
        case .normalization, .expectationSetting, .rapportBuilding, .suggestibilityTesting:
            return 14
        case .eyeFixation, .breathingFocus, .progressiveRelaxation, .sensoryNarrowing, .pacingExperience:
            return 10
        case .countingDown, .descendingImagery, .fractionation, .heavinessContrast, .timeDistortion:
            return 12
        case .futurePacing, .anchoringResponse, .triggerInstallation, .causeEffectFraming:
            return 12
        case .countingUp, .eyeOpening, .physicalReengagement, .temporalOrientation:
            return 10
        case .brainwashing:
            return 16
        default:
            return 8
        }
    }

    // MARK: - Word Timestamp Approximation

    /// Distributes words across each WhisperKit segment's time span.
    /// WhisperKit returns phrase-level segments; we approximate per-word
    /// timing by dividing the segment duration equally among its words.
    func approximateWordTimestamps(
        from segments: [AudioTranscriptionSegment]
    ) -> [WordTimestamp] {
        Self.approximateWordTimestamps(from: segments)
    }

    nonisolated static func approximateWordTimestamps(
        from segments: [AudioTranscriptionSegment]
    ) -> [WordTimestamp] {
        var wordTimestamps: [WordTimestamp] = []
        wordTimestamps.reserveCapacity(segments.count * 8)

        for segment in segments {
            let words = segment.text
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            guard !words.isEmpty else { continue }

            let wordDuration = segment.duration / Double(words.count)
            for (wordIndex, word) in words.enumerated() {
                let startTime = segment.timestamp + Double(wordIndex) * wordDuration
                wordTimestamps.append(WordTimestamp(
                    word: word,
                    startTime: startTime,
                    duration: wordDuration
                ))
            }
        }

        return wordTimestamps
    }

    // MARK: - Hit Map Construction

    /// Scans all word timestamps against the keyword taxonomy and produces a
    /// bucket array where each element maps phase → accumulated score.
    /// Config weights override the built-in taxonomy weights when present.
    func buildHitMap(
        wordTimestamps: [WordTimestamp],
        bucketCount: Int
    ) -> [[HypnosisMetadata.Phase: Double]] {
        var hitMap = [[HypnosisMetadata.Phase: Double]](
            repeating: [:],
            count: bucketCount
        )
        // Apply config weight overrides on top of the built-in taxonomy.
        // Build an override lookup: phrase → (phase, weight)
        var configOverrides: [String: (HypnosisMetadata.Phase, Double)] = [:]
        for phase in HypnosisMetadata.Phase.allCases {
            for (phrase, weight) in effectiveWeightsForPhase(phase) {
                setConfigOverride(
                    phrase: phrase,
                    phase: hitMapTargetPhase(for: phase),
                    weight: weight,
                    in: &configOverrides
                )
            }
        }

        let sortedKeywords = HypnosisPhaseKeywords.all
            .sorted { $0.phrase.count > $1.phrase.count }  // longest phrase first

        for wordIndex in 0..<wordTimestamps.count {
            if wordIndex.isMultiple(of: 256), Task.isCancelled { return hitMap }
            let bucket = max(0, min(Int(wordTimestamps[wordIndex].startTime), bucketCount - 1))
            var matched = false

            // Try multi-word phrases (up to 4 words starting at this position)
            let maxPhrase = min(4, wordTimestamps.count - wordIndex)
            for phraseLen in stride(from: maxPhrase, through: 1, by: -1) {
                let phrase = wordTimestamps[wordIndex..<(wordIndex + phraseLen)]
                    .map { $0.word.lowercased() }
                    .joined(separator: " ")
                if let (phase, weight) = configOverrides[phrase] {
                    hitMap[bucket][phase, default: 0.0] += weight * Double(phraseLen)
                    matched = true
                    break
                } else if let keyword = sortedKeywords.first(where: { $0.phrase == phrase }) {
                    hitMap[bucket][keyword.phase, default: 0.0] += keyword.weight * Double(phraseLen)
                    matched = true
                    break
                }
            }

            // Single-word fallback
            if !matched {
                let singleWord = wordTimestamps[wordIndex].word.lowercased()
                if let (phase, weight) = configOverrides[singleWord] {
                    hitMap[bucket][phase, default: 0.0] += weight
                } else if let keyword = sortedKeywords.first(where: { $0.phrase == singleWord }) {
                    hitMap[bucket][keyword.phase, default: 0.0] += keyword.weight
                }
            }
        }

        return hitMap
    }

    private func effectiveWeightsForPhase(_ phase: HypnosisMetadata.Phase) -> [String: Double] {
        let aliases: [HypnosisMetadata.Phase] = {
            switch phase {
            case .preTalk:
                return [.induction, .preTalk]
            case .fractionation, .deepening, .confusion, .transitional:
                return [.deepening, .fractionation, .confusion, .transitional]
            default:
                return [phase]
            }
        }()
        var weights: [String: Double]
        switch phase {
        case .preTalk:
            weights = config.weightsForPhase(.induction)
        case .fractionation, .deepening, .confusion, .transitional:
            weights = config.weightsForPhase(.deepening)
        default:
            weights = configuredWeights(for: phase)
        }
        for alias in aliases {
            for (keyword, learnedWeight) in corpusKnowledge.keywordWeights[alias] ?? [:] {
                let sourceMultiplier = sourceMultiplier(
                    for: keyword,
                    phase: alias,
                    in: corpusKnowledge.keywordSourcePacks
                )
                guard sourceMultiplier > 0 else { continue }
                weights[keyword] = max(
                    weights[keyword] ?? 0,
                    learnedWeight * corpusLearning.learnedKeywordWeightMultiplier * sourceMultiplier
                )
            }
            for (phrase, learnedWeight) in corpusKnowledge.phraseWeights[alias] ?? [:] {
                let sourceMultiplier = sourceMultiplier(
                    for: phrase,
                    phase: alias,
                    in: corpusKnowledge.phraseSourcePacks
                )
                guard sourceMultiplier > 0 else { continue }
                weights[phrase] = max(
                    weights[phrase] ?? 0,
                    learnedWeight * corpusLearning.learnedPhraseWeightMultiplier * sourceMultiplier
                )
            }
        }
        return weights
    }

    private func setConfigOverride(
        phrase: String,
        phase: HypnosisMetadata.Phase,
        weight: Double,
        in configOverrides: inout [String: (HypnosisMetadata.Phase, Double)]
    ) {
        guard let existing = configOverrides[phrase] else {
            configOverrides[phrase] = (phase, weight)
            return
        }

        if existing.0 == phase {
            configOverrides[phrase] = (phase, max(existing.1, weight))
        } else if weight > existing.1 {
            configOverrides[phrase] = (phase, weight)
        }
    }

    private func sourceMultiplier(
        for term: String,
        phase: HypnosisMetadata.Phase,
        in sourcePacks: [HypnosisMetadata.Phase: [String: Set<String>]]
    ) -> Double {
        corpusLearning.sourceMultiplier(
            for: sourcePacks[phase]?[term] ?? Set<String>(),
            phase: phase
        )
    }

    private func configuredWeights(for phase: HypnosisMetadata.Phase) -> [String: Double] {
        var weights = config.weights[phase.rawValue] ?? [:]
        for legacyKey in legacyConfigKeys(for: phase) {
            for (keyword, weight) in config.weights[legacyKey] ?? [:] {
                weights[keyword] = max(weights[keyword] ?? 0.0, weight)
            }
        }
        return weights
    }

    private func legacyConfigKeys(for phase: HypnosisMetadata.Phase) -> [String] {
        switch phase {
        case .therapy:
            return ["therapy"]
        default:
            return []
        }
    }

    private func hitMapTargetPhase(for phase: HypnosisMetadata.Phase) -> HypnosisMetadata.Phase {
        switch phase {
        case .preTalk:
            return .induction
        case .fractionation, .confusion, .transitional:
            return .deepening
        default:
            return phase
        }
    }

    // MARK: - Timeline Resolution

    /// Assigns the best-scoring phase to each second, using a recency-biased context window.
    func resolveTimeline(
        hitMap: [[HypnosisMetadata.Phase: Double]],
        bucketCount: Int
    ) -> [HypnosisMetadata.Phase?] {
        let contextRadius = config.contextWindowSeconds
        var timeline = [HypnosisMetadata.Phase?](repeating: nil, count: bucketCount)

        for secondIndex in 0..<bucketCount {
            if secondIndex.isMultiple(of: 256), Task.isCancelled { return timeline }
            var scores = [HypnosisMetadata.Phase: Double]()
            let lo = max(0, secondIndex - contextRadius)
            let hi = min(bucketCount - 1, secondIndex + contextRadius)

            for nearIndex in lo...hi {
                let recency = 1.0 - Double(abs(nearIndex - secondIndex)) / Double(contextRadius + 1)
                for (phase, score) in hitMap[nearIndex] {
                    let positionWeight = phasePositionWeight(
                        for: phase,
                        secondIndex: secondIndex,
                        bucketCount: bucketCount
                    )
                    scores[phase, default: 0.0] += score * recency * positionWeight
                }
            }

            if let best = scores.max(by: { $0.value < $1.value }), best.value > 0 {
                timeline[secondIndex] = best.key
            }
        }

        return timeline
    }

    func phasePositionWeight(
        for phase: HypnosisMetadata.Phase,
        secondIndex: Int,
        bucketCount: Int
    ) -> Double {
        guard bucketCount > 0 else { return 1.0 }

        let positionPct = (Double(secondIndex) + 0.5) / Double(bucketCount) * 100.0
        let anchoredRange = Self.positionAnchorRange(for: phase)
        let distance: Double

        if positionPct < anchoredRange.lowerBound {
            distance = anchoredRange.lowerBound - positionPct
        } else if positionPct > anchoredRange.upperBound {
            distance = positionPct - anchoredRange.upperBound
        } else {
            distance = 0.0
        }

        let normalizedDistance = min(distance / 35.0, 1.0)
        let maximumPenalty: Double
        switch phase {
        case .brainwashing, .eroticSuggestions, .conditioning, .emergence:
            maximumPenalty = 0.94
        default:
            maximumPenalty = 0.78
        }
        return 1.0 - (normalizedDistance * maximumPenalty)
    }

    // MARK: - Phase Ordering

    private static let orderedPhases: [HypnosisMetadata.Phase] = HypnosisMetadata.Phase.orderedHypnosisPhases
    private static let phasePositionAnchors: [HypnosisMetadata.Phase: ClosedRange<Double>] = [
        .preTalk: 0.0...12.0,
        .induction: 0.0...24.0,
        .fractionation: 8.0...30.0,
        .deepening: 12.0...45.0,
        .confusion: 22.0...60.0,
        .therapy: 28.0...72.0,
        .suggestions: 42.0...86.0,
        .eroticSuggestions: 48.0...86.0,
        .brainwashing: 55.0...92.0,
        .conditioning: 68.0...100.0,
        .emergence: 84.0...100.0,
        .transitional: 0.0...100.0
    ]

    /// Canonicalizes technique/legacy labels without suppressing sustained returns
    /// to an earlier structural phase. Short invalid oscillations are handled by the
    /// smoothing and minimum-run passes that precede this method.
    func enforcePhaseOrdering(
        timeline: [HypnosisMetadata.Phase?]
    ) -> [HypnosisMetadata.Phase?] {
        timeline.map { $0?.labelingPhase }
    }

    func enforcePhaseOrdering(
        phaseSegments: [PhaseSegment]
    ) -> [PhaseSegment] {
        guard !phaseSegments.isEmpty else { return [] }

        let normalized = phaseSegments.map { segment -> PhaseSegment in
            let canonicalPhase = segment.phase.labelingPhase
            guard canonicalPhase != segment.phase else { return segment }
            return PhaseSegment(
                id: segment.id,
                phase: canonicalPhase,
                startTime: segment.startTime,
                endTime: segment.endTime,
                characteristics: canonicalPhase.displayName,
                tranceDepthEstimate: canonicalPhase.tranceDepthEstimate,
                linguisticMarkers: segment.linguisticMarkers,
                confidenceLevel: segment.confidenceLevel,
                confidenceRationale: segment.confidenceRationale,
                transitionTarget: segment.transitionTarget
            )
        }

        return mergeAdjacentPhaseSegments(normalized)
    }

    private static func positionAnchorRange(
        for phase: HypnosisMetadata.Phase
    ) -> ClosedRange<Double> {
        phasePositionAnchors[phase] ?? (0.0...100.0)
    }

    // MARK: - Smoothing

    /// Majority-vote sliding window — most frequent phase in the window wins.
    func majorityVoteSmooth(
        timeline: [HypnosisMetadata.Phase?],
        windowSize: Int
    ) -> [HypnosisMetadata.Phase?] {
        guard windowSize > 1 else { return timeline }
        var smoothed = timeline

        for secondIndex in 0..<timeline.count {
            let lo = max(0, secondIndex - windowSize / 2)
            let hi = min(timeline.count - 1, secondIndex + windowSize / 2)

            var counts = [HypnosisMetadata.Phase: Int]()
            for nearIndex in lo...hi {
                if let phase = timeline[nearIndex] {
                    counts[phase, default: 0] += 1
                }
            }

            if let winner = counts.max(by: { $0.value < $1.value }) {
                smoothed[secondIndex] = winner.key
            }
        }

        // Forward-fill any remaining nil gaps
        var lastKnown: HypnosisMetadata.Phase? = nil
        for secondIndex in 0..<smoothed.count {
            if let phase = smoothed[secondIndex] {
                lastKnown = phase
            } else if let known = lastKnown {
                smoothed[secondIndex] = known
            }
        }

        return smoothed
    }

    /// Merges runs shorter than `minRun` seconds into their neighbour.
    /// Eliminates sub-15s boundary oscillation common at phase transitions.
    func collapseShortRuns(
        _ timeline: [HypnosisMetadata.Phase?],
        minRun: Int
    ) -> [HypnosisMetadata.Phase?] {
        guard !timeline.isEmpty else { return timeline }

        struct Run { var phase: HypnosisMetadata.Phase?; var start: Int; var end: Int }

        var runs: [Run] = []
        var currentPhase = timeline[0]
        var runStart = 0

        for timeIndex in 1..<timeline.count {
            if timeline[timeIndex] != currentPhase {
                runs.append(Run(phase: currentPhase, start: runStart, end: timeIndex))
                currentPhase = timeline[timeIndex]
                runStart = timeIndex
            }
        }
        runs.append(Run(phase: currentPhase, start: runStart, end: timeline.count))

        // Absorb short runs into their forward neighbour iteratively
        var changed = true
        while changed {
            changed = false
            var runIndex = 0
            while runIndex < runs.count {
                let runLen = runs[runIndex].end - runs[runIndex].start
                guard runLen < minRun else { runIndex += 1; continue }

                let absorb: HypnosisMetadata.Phase?
                if runIndex + 1 < runs.count {
                    absorb = runs[runIndex + 1].phase
                } else if runIndex > 0 {
                    absorb = runs[runIndex - 1].phase
                } else {
                    runIndex += 1; continue
                }
                runs[runIndex].phase = absorb

                // Merge adjacent identical phases
                var mergeIndex = 0
                while mergeIndex < runs.count - 1 {
                    if runs[mergeIndex].phase == runs[mergeIndex + 1].phase {
                        runs[mergeIndex].end = runs[mergeIndex + 1].end
                        runs.remove(at: mergeIndex + 1)
                    } else {
                        mergeIndex += 1
                    }
                }
                changed = true
                break
            }
        }

        var output = timeline
        for run in runs {
            for timeIndex in run.start..<run.end {
                output[timeIndex] = run.phase
            }
        }
        return output
    }

    // MARK: - Event Consolidation

    /// Converts a flat per-second timeline into `PhaseSegment` spans.
    func consolidatePhaseSegments(
        timeline: [HypnosisMetadata.Phase?],
        duration: Double
    ) -> [PhaseSegment] {
        guard !timeline.isEmpty else { return [] }

        var segments: [PhaseSegment] = []
        var currentPhase = timeline[0] ?? .preTalk
        var spanStart = 0

        for timeIndex in 1..<timeline.count {
            let phase = timeline[timeIndex] ?? currentPhase
            if phase != currentPhase {
                segments.append(buildPhaseSegment(
                    phase: currentPhase,
                    startTime: Double(spanStart),
                    endTime: Double(timeIndex)
                ))
                currentPhase = phase
                spanStart = timeIndex
            }
        }

        segments.append(buildPhaseSegment(
            phase: currentPhase,
            startTime: Double(spanStart),
            endTime: duration
        ))

        return segments
    }

    private func buildPhaseSegment(
        phase: HypnosisMetadata.Phase,
        startTime: Double,
        endTime: Double
    ) -> PhaseSegment {
        PhaseSegment(
            phase: phase,
            startTime: startTime,
            endTime: endTime,
            characteristics: phase.displayName,
            tranceDepthEstimate: phase.tranceDepthEstimate,
            confidenceLevel: .medium
        )
    }

    private func suggestPhaseTimeline(
        for transcription: AudioTranscriptionResult,
        transcriptAnalysis: TranscriptAnalysis,
        transcriptAnalyzer: TranscriptFeatureAnalyzer
    ) -> PhaseSuggestionTimeline {
        let decodedWindows = decodePhaseEvidenceWindows(
            from: transcriptAnalysis,
            duration: transcription.duration
        )
        guard !decodedWindows.isEmpty else {
            return PhaseSuggestionTimeline(windows: [], segments: [])
        }

        let rawSegments = normalizeAdjacentBoundaries(
            suggestedSegments(from: decodedWindows),
            duration: transcription.duration
        )
        let orderedSegments = enforcePhaseOrdering(phaseSegments: rawSegments)
        let refinedSegments = normalizeAdjacentBoundaries(
            refinePhaseBoundaries(
                orderedSegments,
                transcription: transcription,
                transcriptAnalyzer: transcriptAnalyzer
            ),
            duration: transcription.duration
        )
        let cueSplitSegments = splitSegmentsOnDirectTextCues(
            refinedSegments,
            transcription: transcription
        )
        let terminalRepairedSegments = restoreTerminalEmergenceCue(
            cueSplitSegments,
            transcription: transcription
        )
        let activeTailOrderedSegments = preventSuggestionRegressionAfterConditioning(
            terminalRepairedSegments
        )
        let stabilizedSegments = stabilizeAdaptedPhaseRuns(
            activeTailOrderedSegments,
            baselineSegments: refinedSegments,
            duration: transcription.duration
        )
        let analysis = transcriptAnalyzer.analyze(
            transcription: transcription,
            phases: stabilizedSegments
        )
        let enrichedSegments = enrichSegmentsWithTranscriptConfidence(
            stabilizedSegments,
            transcriptAnalysis: analysis
        )

        return PhaseSuggestionTimeline(
            windows: decodedWindows,
            segments: enrichedSegments
        )
    }

    private func makeTranscription(
        segments: [AudioTranscriptionSegment],
        duration: Double
    ) -> AudioTranscriptionResult {
        AudioTranscriptionResult(
            fullText: segments.map(\.text).joined(separator: " "),
            segments: segments,
            duration: duration,
            detectedLanguage: Locale.current.language.languageCode?.identifier ?? "en"
        )
    }

    private func refinePhaseAssignments(
        _ phaseSegments: [PhaseSegment],
        transcriptAnalysis: TranscriptAnalysis
    ) -> [PhaseSegment] {
        let refined = phaseSegments.map { segment -> PhaseSegment in
            let midpoint = (segment.startTime + segment.endTime) / 2
            guard let section = transcriptAnalysis.section(at: midpoint) else { return segment }

            let currentScore = transcriptSupportScore(for: segment.phase, section: section)
            // Don't allow a relabel that moves a segment backward in the canonical
            // phase order: a backward relabel (e.g. induction → pre_talk) doesn't
            // refine the phase, it erases it by merging into the earlier adjacent
            // phase, dropping a structural stage the keyword pipeline detected.
            // Forward refinement (induction → deepening) is still allowed.
            let currentOrderIndex = Self.orderedPhases.firstIndex(of: segment.phase)
            let alternatives = candidatePhases(for: segment.phase).filter { candidate in
                guard
                    let currentOrderIndex,
                    let candidateIndex = Self.orderedPhases.firstIndex(of: candidate)
                else { return true }
                return candidateIndex >= currentOrderIndex
            }
            let bestCandidate = alternatives.max { lhs, rhs in
                transcriptSupportScore(for: lhs, section: section) < transcriptSupportScore(for: rhs, section: section)
            } ?? segment.phase
            let bestScore = transcriptSupportScore(for: bestCandidate, section: section)

            guard
                bestCandidate != segment.phase,
                currentScore < 0.62,
                bestScore > currentScore + 0.12
            else {
                return segment
            }

            return PhaseSegment(
                id: segment.id,
                phase: bestCandidate,
                startTime: segment.startTime,
                endTime: segment.endTime,
                characteristics: bestCandidate.displayName,
                tranceDepthEstimate: bestCandidate.tranceDepthEstimate,
                linguisticMarkers: segment.linguisticMarkers,
                confidenceLevel: segment.confidenceLevel,
                confidenceRationale: segment.confidenceRationale,
                transitionTarget: segment.transitionTarget
            )
        }

        return mergeAdjacentPhaseSegments(refined)
    }

    private func candidatePhases(for phase: HypnosisMetadata.Phase) -> [HypnosisMetadata.Phase] {
        let canonicalPhase = phase.labelingPhase
        var candidates = Set([canonicalPhase])
        if let phaseIndex = Self.orderedPhases.firstIndex(of: canonicalPhase) {
            for delta in -2...2 {
                let candidateIndex = phaseIndex + delta
                guard Self.orderedPhases.indices.contains(candidateIndex) else { continue }
                candidates.insert(Self.orderedPhases[candidateIndex])
            }
        }

        if [.suggestions, .eroticSuggestions, .brainwashing, .conditioning].contains(phase) {
            candidates.formUnion([.suggestions, .eroticSuggestions, .brainwashing, .conditioning])
        }
        if [.induction, .fractionation, .deepening, .confusion].contains(phase) {
            candidates.formUnion([.induction, .deepening])
        }

        return Self.orderedPhases.filter { candidates.contains($0) }
    }

    private func selectBestAdaptedSegments(
        primarySegments: [PhaseSegment],
        proposalSegments: [PhaseSegment],
        transcription: AudioTranscriptionResult,
        transcriptAnalyzer: TranscriptFeatureAnalyzer
    ) -> (segments: [PhaseSegment], analysis: TranscriptAnalysis) {
        let primaryAnalysis = transcriptAnalyzer.analyze(
            transcription: transcription,
            phases: primarySegments
        )
        let normalizedProposalSegments = normalizeAdjacentBoundaries(
            proposalSegments,
            duration: transcription.duration
        )
        guard !normalizedProposalSegments.isEmpty else {
            return (primarySegments, primaryAnalysis)
        }

        // A proposal with overlapping spans is structurally invalid (a timeline
        // cannot be in two phases at once). It must never win over the primary on
        // an intrinsic quality score — reject it outright and keep the primary.
        guard Self.segmentsAreNonOverlapping(normalizedProposalSegments) else {
            return (primarySegments, primaryAnalysis)
        }

        let proposalAnalysis = transcriptAnalyzer.analyze(
            transcription: transcription,
            phases: normalizedProposalSegments
        )
        let primaryScore = intrinsicQualityScore(
            for: primarySegments,
            transcriptAnalysis: primaryAnalysis
        )
        let proposalScore = intrinsicQualityScore(
            for: normalizedProposalSegments,
            transcriptAnalysis: proposalAnalysis
        )
        let primaryDistinctPhases = Set(primarySegments.map(\.phase)).count
        let proposalDistinctPhases = Set(normalizedProposalSegments.map(\.phase)).count
        let proposalHasBetterCoverage = proposalDistinctPhases > primaryDistinctPhases
        let proposalAddsTerminalEmergence =
            normalizedProposalSegments.last?.phase == .emergence &&
            primarySegments.last?.phase != .emergence
        let proposalWinsClearly = proposalScore > primaryScore + 0.035
        let proposalWinsCoverageTie =
            proposalHasBetterCoverage &&
            proposalScore >= primaryScore - 0.05 &&
            primaryDistinctPhases < 4
        let proposalRestoresEmergence =
            proposalAddsTerminalEmergence &&
            proposalScore >= primaryScore - 0.08

        if proposalWinsClearly || proposalWinsCoverageTie || proposalRestoresEmergence {
            return (normalizedProposalSegments, proposalAnalysis)
        }

        return (primarySegments, primaryAnalysis)
    }

    /// True when no two segments overlap in time (sorted by start). A small
    /// epsilon tolerates floating-point boundary touch-points.
    static func segmentsAreNonOverlapping(_ segments: [PhaseSegment]) -> Bool {
        let sorted = segments.sorted { $0.startTime < $1.startTime }
        for (lhs, rhs) in zip(sorted, sorted.dropFirst()) where lhs.endTime > rhs.startTime + 0.001 {
            return false
        }
        return true
    }

    private func mergeAdjacentPhaseSegments(
        _ phaseSegments: [PhaseSegment]
    ) -> [PhaseSegment] {
        guard var current = phaseSegments.first else { return [] }
        var merged: [PhaseSegment] = []

        for segment in phaseSegments.dropFirst() {
            if segment.phase == current.phase {
                current = PhaseSegment(
                    id: current.id,
                    phase: current.phase,
                    startTime: current.startTime,
                    endTime: segment.endTime,
                    characteristics: current.phase.displayName,
                    tranceDepthEstimate: current.phase.tranceDepthEstimate,
                    linguisticMarkers: current.linguisticMarkers + segment.linguisticMarkers,
                    confidenceLevel: current.confidenceLevel,
                    confidenceRationale: current.confidenceRationale,
                    transitionTarget: current.transitionTarget
                )
            } else {
                merged.append(current)
                current = segment
            }
        }

        merged.append(current)
        return merged
    }

    /// Cue refinement runs after the second-resolution classifier has already
    /// enforced its minimum phase duration. Re-apply that invariant here so a
    /// handful of phrase-level cues cannot make playback switch modes every few
    /// seconds. The pre-refinement timeline acts as hysteresis when either
    /// neighbour agrees with it.
    private func stabilizeAdaptedPhaseRuns(
        _ phaseSegments: [PhaseSegment],
        baselineSegments: [PhaseSegment],
        duration: TimeInterval
    ) -> [PhaseSegment] {
        guard duration > 0 else { return [] }

        var stabilized = normalizeAdjacentBoundaries(
            phaseSegments,
            duration: duration
        )
        let minimumDuration = Double(
            max(
                config.minimumPhaseDurationSeconds,
                Int(duration * config.collapseThresholdFraction)
            )
        )

        while stabilized.count > 1 {
            let shortIndices = stabilized.indices.filter {
                stabilized[$0].endTime - stabilized[$0].startTime < minimumDuration
            }
            guard !shortIndices.isEmpty else { break }

            let shortIndex = shortIndices.first(where: { index in
                index > stabilized.startIndex
                    && index < stabilized.index(before: stabilized.endIndex)
                    && stabilized[stabilized.index(before: index)].phase.labelingPhase
                        == stabilized[stabilized.index(after: index)].phase.labelingPhase
            }) ?? shortIndices.first(where: { index in
                guard
                    index > stabilized.startIndex,
                    index < stabilized.index(before: stabilized.endIndex),
                    let baselinePhase = baselinePhase(
                        at: (stabilized[index].startTime + stabilized[index].endTime) / 2,
                        in: baselineSegments
                    )
                else {
                    return false
                }
                let previousPhase = stabilized[stabilized.index(before: index)].phase.labelingPhase
                let nextPhase = stabilized[stabilized.index(after: index)].phase.labelingPhase
                return baselinePhase == previousPhase || baselinePhase == nextPhase
            }) ?? shortIndices.first(where: { index in
                index > stabilized.startIndex
                    && index < stabilized.index(before: stabilized.endIndex)
            }) ?? shortIndices[0]

            let replacementPhase = stableNeighbourPhase(
                for: shortIndex,
                in: stabilized,
                baselineSegments: baselineSegments
            )
            stabilized[shortIndex] = copySegment(
                stabilized[shortIndex],
                phase: replacementPhase
            )
            stabilized = mergeAdjacentPhaseSegments(stabilized)
        }

        return normalizeAdjacentBoundaries(stabilized, duration: duration)
    }

    private func stableNeighbourPhase(
        for index: Int,
        in phaseSegments: [PhaseSegment],
        baselineSegments: [PhaseSegment]
    ) -> HypnosisMetadata.Phase {
        guard index > phaseSegments.startIndex else {
            return phaseSegments[phaseSegments.index(after: index)].phase
        }
        guard index < phaseSegments.index(before: phaseSegments.endIndex) else {
            return phaseSegments[phaseSegments.index(before: index)].phase
        }

        let previousPhase = phaseSegments[phaseSegments.index(before: index)].phase
        let nextPhase = phaseSegments[phaseSegments.index(after: index)].phase
        guard previousPhase.labelingPhase != nextPhase.labelingPhase else {
            return previousPhase
        }

        let midpoint = (phaseSegments[index].startTime + phaseSegments[index].endTime) / 2
        if let baselinePhase = baselinePhase(at: midpoint, in: baselineSegments) {
            if baselinePhase == previousPhase.labelingPhase {
                return previousPhase
            }
            if baselinePhase == nextPhase.labelingPhase {
                return nextPhase
            }
        }

        // Offline hysteresis: an isolated candidate must persist for the minimum
        // duration before it can replace the preceding stable phase.
        return previousPhase
    }

    private func baselinePhase(
        at time: TimeInterval,
        in phaseSegments: [PhaseSegment]
    ) -> HypnosisMetadata.Phase? {
        phaseSegments.first { segment in
            time >= segment.startTime && time < segment.endTime
        }?.phase.labelingPhase
    }

    private func normalizeAdjacentBoundaries(
        _ phaseSegments: [PhaseSegment],
        duration: TimeInterval? = nil
    ) -> [PhaseSegment] {
        var adjusted = phaseSegments
            .filter { $0.endTime > $0.startTime }
            .sorted { lhs, rhs in
                if abs(lhs.startTime - rhs.startTime) < 0.001 {
                    return lhs.endTime < rhs.endTime
                }
                return lhs.startTime < rhs.startTime
            }
        guard !adjusted.isEmpty else { return [] }

        if let duration {
            adjusted[0] = copySegment(
                adjusted[0],
                startTime: 0,
                endTime: adjusted[0].endTime
            )
            let lastIndex = adjusted.count - 1
            adjusted[lastIndex] = copySegment(
                adjusted[lastIndex],
                startTime: adjusted[lastIndex].startTime,
                endTime: max(adjusted[lastIndex].startTime, duration)
            )
        }

        guard adjusted.count >= 2 else { return adjusted }

        for index in 0..<(adjusted.count - 1) {
            let left = adjusted[index]
            let right = adjusted[index + 1]
            let midpointBoundary = (left.endTime + right.startTime) / 2.0
            let lowerBound = left.startTime + 0.001
            let upperBound = right.endTime - 0.001
            let boundary = min(max(midpointBoundary, lowerBound), upperBound)

            adjusted[index] = copySegment(
                left,
                startTime: left.startTime,
                endTime: boundary
            )
            adjusted[index + 1] = copySegment(
                right,
                startTime: boundary,
                endTime: right.endTime
            )
        }

        return mergeAdjacentPhaseSegments(
            adjusted.filter { $0.endTime > $0.startTime + 0.001 }
        )
    }

    private func repairOpeningActivePhase(
        _ phaseSegments: [PhaseSegment],
        wordTimestamps: [WordTimestamp],
        duration: TimeInterval
    ) -> [PhaseSegment] {
        guard
            duration > 0,
            var firstSegment = phaseSegments.first,
            firstSegment.startTime <= 0.001,
            isImpossibleOpeningActivePhase(firstSegment.phase)
        else {
            return phaseSegments
        }

        let anchorStart = duration * (Self.positionAnchorRange(for: firstSegment.phase).lowerBound / 100.0)
        let minimumOpeningDuration = min(max(duration * 0.08, 8.0), 30.0)
        guard anchorStart >= minimumOpeningDuration else { return phaseSegments }

        let structuralPhase = openingStructuralPhase(
            wordTimestamps: wordTimestamps,
            duration: duration
        )
        var repaired = phaseSegments
        if firstSegment.endTime > anchorStart + 4.0 {
            let openingSegment = copySegment(
                firstSegment,
                phase: structuralPhase,
                startTime: firstSegment.startTime,
                endTime: anchorStart
            )
            firstSegment = copySegment(
                firstSegment,
                startTime: anchorStart,
                endTime: firstSegment.endTime
            )
            repaired[0] = openingSegment
            repaired.insert(firstSegment, at: 1)
        } else {
            repaired[0] = copySegment(firstSegment, phase: structuralPhase)
        }

        return mergeAdjacentPhaseSegments(repaired)
    }

    private func isImpossibleOpeningActivePhase(_ phase: HypnosisMetadata.Phase) -> Bool {
        switch phase {
        case .brainwashing, .conditioning, .emergence:
            return true
        default:
            return false
        }
    }

    private func openingStructuralPhase(
        wordTimestamps: [WordTimestamp],
        duration: TimeInterval
    ) -> HypnosisMetadata.Phase {
        let openingCutoff = min(max(duration * 0.18, 10.0), 35.0)
        let tokens = wordTimestamps
            .filter { $0.startTime <= openingCutoff }
            .flatMap { normalizedTokens(in: $0.word) }
        let tokenSet = Set(tokens)
        let normalizedText = " \(tokens.joined(separator: " ")) "
        let preTalkWords = [
            "welcome", "today", "session", "comfortable", "comfortably",
            "ready", "begin", "settle", "before", "explain", "process"
        ]
        let preTalkPhrases = [
            "get comfortable", "settle in", "this session", "before we begin"
        ]
        if !tokenSet.isDisjoint(with: preTalkWords)
            || preTalkPhrases.contains(where: { normalizedText.contains(" \($0) ") }) {
            return .preTalk
        }

        return .induction
    }

    private func restoreTerminalEmergenceCue(
        _ phaseSegments: [PhaseSegment],
        transcription: AudioTranscriptionResult
    ) -> [PhaseSegment] {
        guard !phaseSegments.isEmpty, transcription.duration > 0 else {
            return phaseSegments
        }
        let normalizedSegments = normalizeAdjacentBoundaries(
            phaseSegments,
            duration: transcription.duration
        )
        guard normalizedSegments.last?.phase != .emergence else {
            return normalizedSegments
        }

        let tailWindow = min(max(45.0, transcription.duration * 0.25), 180.0)
        let tailStart = max(transcription.duration * 0.58, transcription.duration - tailWindow)
        let sortedTranscriptSegments = transcription.segments.sorted { $0.timestamp < $1.timestamp }
        guard
            let cueSegment = sortedTranscriptSegments.first(where: {
                $0.timestamp >= tailStart && hasDirectEmergenceCue(in: $0.text)
            })
        else {
            return normalizedSegments
        }

        let cueStart = max(0.0, min(cueSegment.timestamp, transcription.duration))
        guard transcription.duration - cueStart >= 4.0 else { return normalizedSegments }

        var repaired: [PhaseSegment] = []
        var insertedEmergence = false
        for segment in normalizedSegments {
            if insertedEmergence {
                repaired.append(copySegment(segment, phase: .emergence))
                continue
            }

            if cueStart <= segment.startTime + 0.001 {
                repaired.append(copySegment(segment, phase: .emergence))
                insertedEmergence = true
                continue
            }

            if cueStart >= segment.endTime - 0.001 {
                repaired.append(segment)
                continue
            }

            if cueStart > segment.startTime + 4.0 {
                repaired.append(
                    copySegment(
                        segment,
                        startTime: segment.startTime,
                        endTime: cueStart
                    )
                )
            }
            repaired.append(
                copySegment(
                    segment,
                    phase: .emergence,
                    startTime: max(segment.startTime, cueStart),
                    endTime: segment.endTime
                )
            )
            insertedEmergence = true
        }

        guard insertedEmergence else { return normalizedSegments }
        return mergeAdjacentPhaseSegments(repaired)
    }

    private func preventSuggestionRegressionAfterConditioning(
        _ phaseSegments: [PhaseSegment]
    ) -> [PhaseSegment] {
        var seenConditioning = false
        let repaired = phaseSegments.map { segment -> PhaseSegment in
            if segment.phase == .conditioning {
                seenConditioning = true
                return segment
            }
            if segment.phase == .emergence {
                return segment
            }
            guard
                seenConditioning,
                segment.phase == .suggestions
            else {
                return segment
            }

            return copySegment(segment, phase: .conditioning)
        }

        return mergeAdjacentPhaseSegments(repaired)
    }

    private func repairUnsupportedPhaseAssignments(
        _ phaseSegments: [PhaseSegment],
        transcription: AudioTranscriptionResult,
        transcriptAnalyzer: TranscriptFeatureAnalyzer
    ) -> [PhaseSegment] {
        guard !phaseSegments.isEmpty else { return [] }
        let analysis = transcriptAnalyzer.analyze(
            transcription: transcription,
            phases: phaseSegments
        )
        let repaired = phaseSegments.map { segment -> PhaseSegment in
            let midpoint = (segment.startTime + segment.endTime) / 2.0
            guard let section = analysis.section(at: midpoint) else { return segment }
            let segmentText = text(
                in: segment,
                transcription: transcription
            )

            let currentEvidence = configuredPhaseEvidenceScore(
                for: segment.phase,
                section: section,
                transcriptText: segmentText
            )
            let candidates = repairCandidatePhases(for: segment.phase)
            let best = candidates
                .map { phase in
                    (
                        phase: phase,
                        score: configuredPhaseEvidenceScore(
                            for: phase,
                            section: section,
                            transcriptText: segmentText
                        )
                    )
                }
                .max { lhs, rhs in
                    if abs(lhs.score - rhs.score) < 0.0001 {
                        return phaseOrderIndex(lhs.phase) > phaseOrderIndex(rhs.phase)
                    }
                    return lhs.score < rhs.score
                }

            guard
                let best,
                best.phase != segment.phase,
                shouldRepairPhase(
                    from: segment.phase,
                    to: best.phase,
                    currentEvidence: currentEvidence,
                    candidateEvidence: best.score
                )
            else {
                return segment
            }

            return copySegment(segment, phase: best.phase)
        }

        let cueSplitSegments = splitSegmentsOnDirectTextCues(
            mergeAdjacentPhaseSegments(repaired),
            transcription: transcription
        )
        return mergeAdjacentPhaseSegments(
            suppressUnsupportedActiveIslands(
                cueSplitSegments,
                transcription: transcription
            )
        )
    }

    private func suppressUnsupportedActiveIslands(
        _ phaseSegments: [PhaseSegment],
        transcription: AudioTranscriptionResult
    ) -> [PhaseSegment] {
        phaseSegments.enumerated().map { index, segment in
            let canonicalPhase = segment.phase.labelingPhase
            let segmentText = text(in: segment, transcription: transcription)
            if [.induction, .deepening, .therapy].contains(canonicalPhase),
               let activeReplacement = activePhaseReplacement(
                    for: canonicalPhase,
                    segmentText: segmentText
               ) {
                return copySegment(segment, phase: activeReplacement)
            }

            guard [.suggestions, .brainwashing, .emergence].contains(canonicalPhase) else {
                return segment
            }

            let currentTextEvidence = configuredTextEvidenceScore(
                for: canonicalPhase,
                transcriptText: segmentText
            )
            let lacksRequiredSuggestionCue =
                canonicalPhase == .suggestions &&
                !hasDirectSuggestionCue(in: segmentText)
            guard currentTextEvidence < 0.24 || lacksRequiredSuggestionCue else { return segment }

            let fallbackCandidates: [HypnosisMetadata.Phase]
            switch canonicalPhase {
            case .suggestions:
                fallbackCandidates = [.therapy, .deepening, .induction]
            case .brainwashing:
                fallbackCandidates = [.suggestions, .conditioning, .therapy, .deepening]
            case .emergence:
                fallbackCandidates = [.conditioning, .therapy, .deepening, .induction]
            default:
                fallbackCandidates = []
            }

            let bestTextCandidate = fallbackCandidates
                .map {
                    (
                        phase: $0,
                        score: configuredTextEvidenceScore(
                            for: $0,
                            transcriptText: segmentText
                        )
                    )
                }
                .max { $0.score < $1.score }
            if let bestTextCandidate, bestTextCandidate.score >= 0.28 {
                return copySegment(segment, phase: bestTextCandidate.phase)
            }

            let neighboringPhases = [
                index > 0 ? phaseSegments[index - 1].phase.labelingPhase : nil,
                index + 1 < phaseSegments.count ? phaseSegments[index + 1].phase.labelingPhase : nil
            ].compactMap { $0 }
            if let neighbor = neighboringPhases.first(where: {
                [.induction, .deepening, .therapy].contains($0)
            }) {
                return copySegment(segment, phase: neighbor)
            }

            return segment
        }
    }

    private func splitSegmentsOnDirectTextCues(
        _ phaseSegments: [PhaseSegment],
        transcription: AudioTranscriptionResult
    ) -> [PhaseSegment] {
        guard transcription.segments.count >= 2 else { return phaseSegments }

        return phaseSegments.flatMap { segment -> [PhaseSegment] in
            let duration = segment.endTime - segment.startTime
            guard duration >= 36 else { return [segment] }

            let overlappingSegments = transcription.segments.compactMap { transcriptSegment -> (segment: AudioTranscriptionSegment, start: TimeInterval, end: TimeInterval)? in
                let transcriptStart = transcriptSegment.timestamp
                let transcriptEnd = transcriptSegment.timestamp + max(transcriptSegment.duration, 0.0)
                let overlapStart = max(transcriptStart, segment.startTime)
                let overlapEnd = min(transcriptEnd, segment.endTime)
                let overlapDuration = overlapEnd - overlapStart
                let transcriptDuration = max(transcriptEnd - transcriptStart, 0.001)
                guard overlapDuration >= 8.0 || overlapDuration / transcriptDuration >= 0.45 else {
                    return nil
                }
                return (transcriptSegment, overlapStart, overlapEnd)
            }

            guard overlappingSegments.count >= 2 else { return [segment] }

            let cuePieces = overlappingSegments.map { entry -> PhaseSegment in
                let cuePhase = directCuePhase(in: entry.segment.text) ?? segment.phase
                return copySegment(
                    segment,
                    phase: cuePhase,
                    startTime: entry.start,
                    endTime: entry.end
                )
            }

            let containsMeaningfulCueChange = cuePieces.contains { $0.phase.labelingPhase != segment.phase.labelingPhase }
                || Set(cuePieces.map { $0.phase.labelingPhase }).count > 1
            guard containsMeaningfulCueChange else { return [segment] }

            var pieces = cuePieces.sorted { $0.startTime < $1.startTime }
            if let first = pieces.first, first.startTime > segment.startTime {
                pieces.insert(
                    copySegment(
                        segment,
                        startTime: segment.startTime,
                        endTime: first.startTime
                    ),
                    at: 0
                )
            }
            if let last = pieces.last, last.endTime < segment.endTime {
                pieces.append(
                    copySegment(
                        segment,
                        startTime: last.endTime,
                        endTime: segment.endTime
                    )
                )
            }

            return mergeAdjacentPhaseSegments(pieces)
        }
    }

    private func directCuePhase(in text: String) -> HypnosisMetadata.Phase? {
        if hasDirectEmergenceCue(in: text) {
            return .emergence
        }
        if hasDirectConditioningCue(in: text) {
            return .conditioning
        }
        if hasDirectSuggestionCue(in: text) {
            return .suggestions
        }

        let scored: [(phase: HypnosisMetadata.Phase, score: Double)] = [
            (.therapy, configuredTextEvidenceScore(for: .therapy, transcriptText: text)),
            (.deepening, configuredTextEvidenceScore(for: .deepening, transcriptText: text)),
            (.induction, configuredTextEvidenceScore(for: .induction, transcriptText: text))
        ]
        guard let best = scored.max(by: { $0.score < $1.score }), best.score >= 0.36 else {
            return nil
        }
        return best.phase
    }

    private func hasDirectEmergenceCue(in text: String) -> Bool {
        let tokens = normalizedTokens(in: text)
        guard !tokens.isEmpty else { return false }
        let tokenSet = Set(tokens)
        let normalizedText = " \(tokens.joined(separator: " ")) "
        let phrases = [
            "wide awake", "fully awake", "coming back", "come back",
            "back in the room", "when you wake", "as you return",
            "count to five", "clear headed", "open your eyes"
        ]
        if phrases.contains(where: { normalizedText.contains(" \($0) ") }) {
            return true
        }
        return !tokenSet.isDisjoint(with: ["awake", "alert", "refreshed", "energized"])
    }

    private func activePhaseReplacement(
        for currentPhase: HypnosisMetadata.Phase,
        segmentText: String
    ) -> HypnosisMetadata.Phase? {
        let currentEvidence = configuredTextEvidenceScore(
            for: currentPhase,
            transcriptText: segmentText
        )
        let suggestionsEvidence = configuredTextEvidenceScore(
            for: .suggestions,
            transcriptText: segmentText
        )
        let conditioningEvidence = configuredTextEvidenceScore(
            for: .conditioning,
            transcriptText: segmentText
        )
        let candidates: [(phase: HypnosisMetadata.Phase, score: Double, hasCue: Bool)] = [
            (.conditioning, conditioningEvidence, hasDirectConditioningCue(in: segmentText)),
            (.suggestions, suggestionsEvidence, hasDirectSuggestionCue(in: segmentText))
        ]
        guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }
        guard best.hasCue, best.score >= 0.35, best.score >= currentEvidence + 0.10 else {
            return nil
        }
        return best.phase
    }

    private func hasDirectSuggestionCue(in text: String) -> Bool {
        let tokens = normalizedTokens(in: text)
        guard !tokens.isEmpty else { return false }
        let tokenSet = Set(tokens)
        let normalizedText = " \(tokens.joined(separator: " ")) "
        let phrases = [
            "you will", "from now on", "every time", "each time",
            "from this moment", "you feel", "you find", "you are becoming",
            "you are now", "your subconscious", "inner mind"
        ]
        if phrases.contains(where: { normalizedText.contains(" \($0) ") }) {
            return true
        }
        let words = [
            "subconscious", "imagine", "believe", "powerful", "change",
            "transform", "suggestion", "accept", "absorb", "program",
            "imprint", "healing", "visualize", "suggest", "automatic",
            "anchor", "trigger"
        ]
        return !tokenSet.isDisjoint(with: words)
    }

    private func hasDirectConditioningCue(in text: String) -> Bool {
        let tokens = normalizedTokens(in: text)
        guard !tokens.isEmpty else { return false }
        let tokenSet = Set(tokens)
        let normalizedText = " \(tokens.joined(separator: " ")) "
        let phrases = [
            "post hypnotic", "future pacing", "carry with you", "take with you",
            "remember this", "when i say", "hear the word", "next time you hear",
            "when i snap my fingers", "snap my fingers"
        ]
        if phrases.contains(where: { normalizedText.contains(" \($0) ") }) {
            return true
        }
        return !tokenSet.isDisjoint(with: ["whenever", "trigger", "anchor"])
    }

    private func repairCandidatePhases(
        for phase: HypnosisMetadata.Phase
    ) -> [HypnosisMetadata.Phase] {
        switch phase.labelingPhase {
        case .induction, .deepening:
            return [.induction, .deepening, .therapy, .suggestions, .conditioning, .emergence]
        case .therapy:
            return [.deepening, .therapy, .suggestions, .conditioning]
        case .suggestions, .eroticSuggestions, .brainwashing, .conditioning:
            return [.deepening, .therapy, .suggestions, .conditioning, .brainwashing, .emergence]
        case .emergence:
            return [.therapy, .suggestions, .conditioning, .emergence]
        default:
            return Self.orderedPhases
        }
    }

    private func shouldRepairPhase(
        from currentPhase: HypnosisMetadata.Phase,
        to candidatePhase: HypnosisMetadata.Phase,
        currentEvidence: Double,
        candidateEvidence: Double
    ) -> Bool {
        guard candidateEvidence >= 0.34 else { return false }

        switch currentPhase.labelingPhase {
        case .brainwashing:
            return currentEvidence < 0.44 && candidateEvidence >= currentEvidence + 0.12
        case .emergence:
            return currentEvidence < 0.40 && candidateEvidence >= currentEvidence + 0.12
        case .induction, .deepening:
            let candidateIsActive = [.therapy, .suggestions, .conditioning, .emergence].contains(candidatePhase.labelingPhase)
            return candidateIsActive
                ? candidateEvidence >= max(currentEvidence + 0.14, 0.42)
                : candidateEvidence >= currentEvidence + 0.18
        case .suggestions, .conditioning:
            let candidateIsTrance = [.deepening, .therapy].contains(candidatePhase.labelingPhase)
            if candidateIsTrance, currentEvidence < 0.34 {
                return candidateEvidence >= currentEvidence + 0.10
            }
            return candidateEvidence >= currentEvidence + 0.14
        default:
            return candidateEvidence >= currentEvidence + 0.20
        }
    }

    private func configuredPhaseEvidenceScore(
        for phase: HypnosisMetadata.Phase,
        section: TranscriptSectionMetrics,
        transcriptText: String? = nil
    ) -> Double {
        let terms = configuredEvidenceTerms(for: phase.labelingPhase)
        let distinctiveWordMatches = section.topDistinctiveWords
            .filter { terms.words.contains($0.word) }
            .count
        let commonWordMatches = section.topWords
            .filter { terms.words.contains($0.word) }
            .count
        let distinctivePhraseMatches = section.topDistinctivePhrases
            .filter { terms.phrases.contains($0.phrase) }
            .count
        let commonPhraseMatches = section.topPhrases
            .filter { terms.phrases.contains($0.phrase) }
            .count
        let wordScore = clamp(
            (Double(distinctiveWordMatches) * 0.38) + (Double(commonWordMatches) * 0.16),
            lower: 0.0,
            upper: 1.0
        )
        let phraseScore = clamp(
            (Double(distinctivePhraseMatches) * 0.55) + (Double(commonPhraseMatches) * 0.35),
            lower: 0.0,
            upper: 1.0
        )
        let waymarkerScore = phaseWaymarkerAlignment(for: phase, section: section)
        let sectionScore = max(wordScore, phraseScore, waymarkerScore)

        guard let transcriptText, !transcriptText.isEmpty else {
            return sectionScore
        }

        let textScore = configuredTextEvidenceScore(
            words: terms.words,
            phrases: terms.phrases,
            transcriptText: transcriptText
        )
        return max(textScore, sectionScore * 0.65)
    }

    private func configuredTextEvidenceScore(
        words: Set<String>,
        phrases: Set<String>,
        transcriptText: String
    ) -> Double {
        let tokens = normalizedTokens(in: transcriptText)
        guard !tokens.isEmpty else { return 0.0 }

        let tokenSet = Set(tokens)
        let normalizedText = " \(tokens.joined(separator: " ")) "
        let wordMatches = words.filter { tokenSet.contains($0) }.count
        let phraseMatches = phrases.filter { phrase in
            normalizedText.contains(" \(normalizePhrase(phrase)) ")
        }.count
        let wordScore = clamp(Double(wordMatches) * 0.18, lower: 0.0, upper: 1.0)
        let phraseScore = clamp(Double(phraseMatches) * 0.50, lower: 0.0, upper: 1.0)
        return max(wordScore, phraseScore)
    }

    private func configuredTextEvidenceScore(
        for phase: HypnosisMetadata.Phase,
        transcriptText: String
    ) -> Double {
        let terms = configuredEvidenceTerms(for: phase.labelingPhase)
        return configuredTextEvidenceScore(
            words: terms.words,
            phrases: terms.phrases,
            transcriptText: transcriptText
        )
    }

    private func text(
        in segment: PhaseSegment,
        transcription: AudioTranscriptionResult
    ) -> String {
        let overlappingText = transcription.segments
            .filter { transcriptSegment in
                let transcriptStart = transcriptSegment.timestamp
                let transcriptEnd = transcriptSegment.timestamp + max(transcriptSegment.duration, 0.0)
                let overlapStart = max(transcriptStart, segment.startTime)
                let overlapEnd = min(transcriptEnd, segment.endTime)
                let overlapDuration = max(0.0, overlapEnd - overlapStart)
                let transcriptDuration = max(transcriptEnd - transcriptStart, 0.001)
                let midpoint = (transcriptStart + transcriptEnd) / 2.0
                return overlapDuration / transcriptDuration >= 0.20
                    || (midpoint >= segment.startTime && midpoint <= segment.endTime)
            }
            .map(\.text)
            .joined(separator: " ")
        return overlappingText.isEmpty ? transcription.fullText : overlappingText
    }

    private func normalizedTokens(in text: String) -> [String] {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func configuredEvidenceTerms(
        for phase: HypnosisMetadata.Phase
    ) -> (words: Set<String>, phrases: Set<String>) {
        let ignoredWords = repairIgnoredWords(for: phase)
        let keywords = HypnosisPhaseKeywords.all.filter {
            hitMapTargetPhase(for: $0.phase).labelingPhase == phase.labelingPhase
        }
        let words = keywords
            .filter { !$0.phrase.contains(" ") }
            .filter { !ignoredWords.contains($0.phrase) }
            .map { $0.phrase }
        let phrases = keywords
            .filter { $0.phrase.contains(" ") }
            .map { normalizePhrase($0.phrase) }
        return (
            Set(words),
            Set(phrases).union(HypnosisWaymarkerLexicon.phrases(for: phase))
        )
    }

    private func repairIgnoredWords(
        for phase: HypnosisMetadata.Phase
    ) -> Set<String> {
        switch phase.labelingPhase {
        case .deepening:
            return [
                "deep", "down", "sleep", "trance", "nowhere", "nothing",
                "double", "waves", "warmth", "maybe", "perhaps", "whether",
                "wondering", "uncertain"
            ]
        case .induction:
            return ["calm", "comfortable", "today", "ready", "begin", "subconscious"]
        case .therapy:
            return ["now", "mind", "unconscious"]
        default:
            return []
        }
    }

    private func phaseOrderIndex(_ phase: HypnosisMetadata.Phase) -> Int {
        Self.orderedPhases.firstIndex(of: phase.labelingPhase) ?? Int.max
    }

    private func copySegment(
        _ segment: PhaseSegment,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> PhaseSegment {
        PhaseSegment(
            id: segment.id,
            phase: segment.phase,
            startTime: startTime,
            endTime: endTime,
            characteristics: segment.characteristics,
            tranceDepthEstimate: segment.tranceDepthEstimate,
            linguisticMarkers: segment.linguisticMarkers,
            confidenceLevel: segment.confidenceLevel,
            confidenceRationale: segment.confidenceRationale,
            transitionTarget: segment.transitionTarget
        )
    }

    private func copySegment(
        _ segment: PhaseSegment,
        phase: HypnosisMetadata.Phase
    ) -> PhaseSegment {
        PhaseSegment(
            id: segment.id,
            phase: phase,
            startTime: segment.startTime,
            endTime: segment.endTime,
            characteristics: phase.displayName,
            tranceDepthEstimate: phase.tranceDepthEstimate,
            linguisticMarkers: segment.linguisticMarkers,
            confidenceLevel: segment.confidenceLevel,
            confidenceRationale: segment.confidenceRationale,
            transitionTarget: segment.transitionTarget
        )
    }

    private func copySegment(
        _ segment: PhaseSegment,
        phase: HypnosisMetadata.Phase,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> PhaseSegment {
        PhaseSegment(
            id: segment.id,
            phase: phase,
            startTime: startTime,
            endTime: endTime,
            characteristics: phase.displayName,
            tranceDepthEstimate: phase.tranceDepthEstimate,
            linguisticMarkers: segment.linguisticMarkers,
            confidenceLevel: segment.confidenceLevel,
            confidenceRationale: segment.confidenceRationale,
            transitionTarget: segment.transitionTarget
        )
    }

    func attachLinguisticMarkers(
        _ phaseSegments: [PhaseSegment],
        markers: [LinguisticMarker]
    ) -> [PhaseSegment] {
        phaseSegments.map { segment in
            let segmentMarkers = markers
                .filter { marker in
                    marker.timestamp >= max(0.0, segment.startTime - 2.0)
                        && marker.timestamp <= segment.endTime + 2.0
                }
                .sorted { $0.timestamp < $1.timestamp }

            return PhaseSegment(
                id: segment.id,
                phase: segment.phase,
                startTime: segment.startTime,
                endTime: segment.endTime,
                characteristics: segment.characteristics,
                tranceDepthEstimate: segment.tranceDepthEstimate,
                linguisticMarkers: segmentMarkers,
                confidenceLevel: segment.confidenceLevel,
                confidenceRationale: segment.confidenceRationale,
                transitionTarget: segment.transitionTarget
            )
        }
    }

    private func refinePhaseBoundaries(
        _ phaseSegments: [PhaseSegment],
        transcription: AudioTranscriptionResult,
        transcriptAnalyzer: TranscriptFeatureAnalyzer
    ) -> [PhaseSegment] {
        guard phaseSegments.count >= 2 else { return phaseSegments }

        let context = transcriptAnalyzer.makeWindowContext(transcription: transcription)
        var adjustedSegments = phaseSegments

        for boundaryIndex in 0..<(adjustedSegments.count - 1) {
            if Task.isCancelled { return adjustedSegments }
            let leftSegment = adjustedSegments[boundaryIndex]
            let rightSegment = adjustedSegments[boundaryIndex + 1]

            guard leftSegment.phase != rightSegment.phase else { continue }

            let leftDuration = leftSegment.endTime - leftSegment.startTime
            let rightDuration = rightSegment.endTime - rightSegment.startTime
            let minimumSideDuration = min(
                boundaryRefinement.minimumSideDurationCeiling,
                max(
                    boundaryRefinement.minimumSideDurationFloor,
                    Double(config.minimumPhaseDurationSeconds) * boundaryRefinement.minimumSideDurationFactor
                )
            )

            guard leftDuration > minimumSideDuration, rightDuration > minimumSideDuration else {
                continue
            }

            let originalBoundary = leftSegment.endTime
            let searchRadius = min(
                boundaryRefinement.maximumSearchRadiusSeconds,
                max(
                    boundaryRefinement.minimumSearchRadiusSeconds,
                    min(leftDuration, rightDuration) * boundaryRefinement.searchRadiusFactor
                )
            )
            let lowerBound = max(
                leftSegment.startTime + minimumSideDuration,
                originalBoundary - searchRadius
            )
            let upperBound = min(
                rightSegment.endTime - minimumSideDuration,
                originalBoundary + searchRadius
            )

            guard upperBound - lowerBound >= 2.0 else { continue }

            let windowDuration = min(
                boundaryRefinement.maximumWindowSeconds,
                max(
                    boundaryRefinement.minimumWindowSeconds,
                    min(leftDuration, rightDuration) * boundaryRefinement.windowFactor
                )
            )
            let candidateBoundaries = candidateBoundaryTimes(
                lowerBound: lowerBound,
                upperBound: upperBound,
                preferred: originalBoundary
            )

            var bestBoundary = originalBoundary
            var bestScore = Double.leastNormalMagnitude

            for candidateBoundary in candidateBoundaries {
                if Task.isCancelled { return adjustedSegments }
                let leftMetrics = transcriptAnalyzer.sectionMetrics(
                    startTime: max(leftSegment.startTime, candidateBoundary - windowDuration),
                    endTime: candidateBoundary,
                    phase: leftSegment.phase,
                    using: context
                )
                let rightMetrics = transcriptAnalyzer.sectionMetrics(
                    startTime: candidateBoundary,
                    endTime: min(rightSegment.endTime, candidateBoundary + windowDuration),
                    phase: rightSegment.phase,
                    using: context
                )

                let candidateScore = boundaryAlignmentScore(
                    leftPhase: leftSegment.phase,
                    rightPhase: rightSegment.phase,
                    leftSection: leftMetrics,
                    rightSection: rightMetrics,
                    originalBoundary: originalBoundary,
                    candidateBoundary: candidateBoundary
                )

                if candidateScore > bestScore {
                    bestScore = candidateScore
                    bestBoundary = candidateBoundary
                }
            }

            guard abs(bestBoundary - originalBoundary) >= 1.0 else { continue }

            adjustedSegments[boundaryIndex] = PhaseSegment(
                id: leftSegment.id,
                phase: leftSegment.phase,
                startTime: leftSegment.startTime,
                endTime: bestBoundary,
                characteristics: leftSegment.characteristics,
                tranceDepthEstimate: leftSegment.tranceDepthEstimate,
                linguisticMarkers: leftSegment.linguisticMarkers,
                confidenceLevel: leftSegment.confidenceLevel,
                confidenceRationale: leftSegment.confidenceRationale,
                transitionTarget: leftSegment.transitionTarget
            )
            adjustedSegments[boundaryIndex + 1] = PhaseSegment(
                id: rightSegment.id,
                phase: rightSegment.phase,
                startTime: bestBoundary,
                endTime: rightSegment.endTime,
                characteristics: rightSegment.characteristics,
                tranceDepthEstimate: rightSegment.tranceDepthEstimate,
                linguisticMarkers: rightSegment.linguisticMarkers,
                confidenceLevel: rightSegment.confidenceLevel,
                confidenceRationale: rightSegment.confidenceRationale,
                transitionTarget: rightSegment.transitionTarget
            )
        }

        return mergeAdjacentPhaseSegments(adjustedSegments)
    }

    private func decodePhaseEvidenceWindows(
        from transcriptAnalysis: TranscriptAnalysis,
        duration: TimeInterval
    ) -> [PhaseEvidenceWindow] {
        let windows = transcriptAnalysis.timelineWindows.sorted { $0.startTime < $1.startTime }
        guard !windows.isEmpty else { return [] }

        let baseEvidence = windows.map { baseEvidenceBreakdowns(for: $0, duration: duration) }
        var cumulativeScores = Array(
            repeating: Array(repeating: Double.leastNormalMagnitude, count: Self.orderedPhases.count),
            count: windows.count
        )
        var previousChoice = Array(
            repeating: Array(repeating: -1, count: Self.orderedPhases.count),
            count: windows.count
        )

        for phaseIndex in Self.orderedPhases.indices {
            let startPenalty = Double(max(0, phaseIndex - 2)) * 0.08
            cumulativeScores[0][phaseIndex] = baseEvidence[0][phaseIndex].totalScore - startPenalty
        }

        if windows.count > 1 {
            for windowIndex in 1..<windows.count {
                for phaseIndex in Self.orderedPhases.indices {
                    let currentPhase = Self.orderedPhases[phaseIndex]
                    let emissionScore = baseEvidence[windowIndex][phaseIndex].totalScore
                    var bestScore = Double.leastNormalMagnitude
                    var bestPreviousIndex = phaseIndex

                    for previousPhaseIndex in 0...phaseIndex {
                        let previousPhase = Self.orderedPhases[previousPhaseIndex]
                        let transitionScore = transitionScore(
                            from: previousPhase,
                            to: currentPhase
                        )
                        let score = cumulativeScores[windowIndex - 1][previousPhaseIndex]
                            + emissionScore
                            + transitionScore
                        if score > bestScore {
                            bestScore = score
                            bestPreviousIndex = previousPhaseIndex
                        }
                    }

                    cumulativeScores[windowIndex][phaseIndex] = bestScore
                    previousChoice[windowIndex][phaseIndex] = bestPreviousIndex
                }
            }
        }

        guard
            let finalPhaseIndex = cumulativeScores.last?.enumerated().max(by: {
                $0.element < $1.element
            })?.offset
        else {
            return []
        }

        var chosenIndices = Array(repeating: 0, count: windows.count)
        var currentPhaseIndex = finalPhaseIndex
        for windowIndex in stride(from: windows.count - 1, through: 0, by: -1) {
            chosenIndices[windowIndex] = currentPhaseIndex
            guard windowIndex > 0 else { continue }
            currentPhaseIndex = max(0, previousChoice[windowIndex][currentPhaseIndex])
        }

        return windows.enumerated().map { windowIndex, window in
            let previousPhase = windowIndex > 0
                ? Self.orderedPhases[chosenIndices[windowIndex - 1]]
                : nil
            let evidence = decorateEvidenceBreakdowns(
                baseEvidence[windowIndex],
                previousPhase: previousPhase
            )
            let sortedEvidence = evidence.sorted { lhs, rhs in
                if abs(lhs.totalScore - rhs.totalScore) < 0.0001 {
                    return lhs.phase.displayName < rhs.phase.displayName
                }
                return lhs.totalScore > rhs.totalScore
            }
            let chosenPhase = Self.orderedPhases[chosenIndices[windowIndex]]
            let chosenEvidence = sortedEvidence.first(where: { $0.phase == chosenPhase }) ?? sortedEvidence[0]
            let alternateScore = sortedEvidence.dropFirst().first?.totalScore ?? 0.0
            let confidence = suggestionConfidence(
                selectedScore: chosenEvidence.totalScore,
                alternateScore: alternateScore,
                waymarkerStrength: chosenEvidence.waymarkerScore,
                phraseStrength: chosenEvidence.phraseLibraryScore
            )
            let confidenceLevel = confidenceLevel(for: confidence)

            return PhaseEvidenceWindow(
                id: window.id,
                startTime: window.startTime,
                endTime: window.endTime,
                phase: chosenPhase,
                confidence: confidence,
                confidenceLevel: confidenceLevel,
                rationale: suggestionRationale(
                    for: chosenEvidence,
                    section: window,
                    confidenceLevel: confidenceLevel
                ),
                evidence: Array(sortedEvidence.prefix(4)),
                topPhrases: Array(window.topDistinctivePhrases.prefix(4)),
                topWaymarkers: Array(window.waymarkerMatches.prefix(4))
            )
        }
    }

    private func baseEvidenceBreakdowns(
        for section: TranscriptSectionMetrics,
        duration: TimeInterval
    ) -> [PhaseEvidenceBreakdown] {
        let midpoint = (section.startTime + section.endTime) / 2.0
        let phaseBucketCount = max(Int(ceil(duration)), 1)
        let secondIndex = min(
            max(Int(midpoint.rounded(.down)), 0),
            max(phaseBucketCount - 1, 0)
        )

        return Self.orderedPhases.map { phase in
            let keywordAlignment = phaseKeywordAlignment(for: phase, section: section)
            let transcriptSupport = transcriptSupportScore(for: phase, section: section)
            let semanticTranscriptScore = (transcriptSupport * 0.50) + (keywordAlignment * 0.50)
            let transcriptScore = semanticTranscriptScore * 0.52
            let phraseAlignment = phraseLibraryAlignment(for: phase, section: section)
            let phraseScore = phraseAlignment.score * 0.24
            let waymarkerScore = phaseWaymarkerAlignment(for: phase, section: section) * 0.16
            let positionScore = phasePositionWeight(
                for: phase,
                secondIndex: secondIndex,
                bucketCount: phaseBucketCount
            ) * 0.08
            let totalScore = transcriptScore + phraseScore + waymarkerScore + positionScore

            return PhaseEvidenceBreakdown(
                phase: phase,
                totalScore: totalScore,
                transcriptScore: transcriptScore,
                phraseLibraryScore: phraseScore,
                waymarkerScore: waymarkerScore,
                positionScore: positionScore,
                transitionScore: 0.0,
                matchedPhrases: phraseAlignment.matchedPhrases
            )
        }
    }

    private func decorateEvidenceBreakdowns(
        _ evidence: [PhaseEvidenceBreakdown],
        previousPhase: HypnosisMetadata.Phase?
    ) -> [PhaseEvidenceBreakdown] {
        evidence.map { breakdown in
            let transitionBonus = previousPhase.map {
                self.transitionScore(from: $0, to: breakdown.phase)
            } ?? 0.0
            return PhaseEvidenceBreakdown(
                phase: breakdown.phase,
                totalScore: breakdown.totalScore + transitionBonus,
                transcriptScore: breakdown.transcriptScore,
                phraseLibraryScore: breakdown.phraseLibraryScore,
                waymarkerScore: breakdown.waymarkerScore,
                positionScore: breakdown.positionScore,
                transitionScore: transitionBonus,
                matchedPhrases: breakdown.matchedPhrases
            )
        }
    }

    private func phraseLibraryAlignment(
        for phase: HypnosisMetadata.Phase,
        section: TranscriptSectionMetrics
    ) -> (score: Double, matchedPhrases: [String]) {
        let associations = corpusKnowledge.phraseAssociations[phase] ?? []
        guard !associations.isEmpty else {
            return (0.0, [])
        }

        var phraseStats: [String: TranscriptPhraseStatistic] = [:]
        for statistic in section.topDistinctivePhrases + section.topPhrases {
            phraseStats[normalizePhrase(statistic.phrase)] = statistic
        }

        let matches = associations.compactMap { association -> (phrase: String, value: Double)? in
            let key = normalizePhrase(association.phrase)
            guard let statistic = phraseStats[key] else { return nil }
            let alignment = min(
                1.0,
                (association.weight / 5.0 * 0.65)
                    + (min(statistic.normalizedShareLift, 2.5) / 2.5 * 0.20)
                    + (min(statistic.share * 4.0, 1.0) * 0.15)
            )
            return (association.phrase, alignment)
        }
        .sorted { lhs, rhs in
            if abs(lhs.value - rhs.value) < 0.0001 {
                return lhs.phrase < rhs.phrase
            }
            return lhs.value > rhs.value
        }

        let score = min(matches.reduce(0.0) { $0 + $1.value }, 1.0)
        return (score, Array(matches.prefix(3).map(\.phrase)))
    }

    private func transitionScore(
        from previousPhase: HypnosisMetadata.Phase,
        to nextPhase: HypnosisMetadata.Phase
    ) -> Double {
        guard
            let previousIndex = Self.orderedPhases.firstIndex(of: previousPhase),
            let nextIndex = Self.orderedPhases.firstIndex(of: nextPhase)
        else {
            return 0.0
        }

        if nextIndex < previousIndex {
            return -0.40
        }

        let jump = nextIndex - previousIndex
        let priorBonus = transitionPrior(from: previousPhase, to: nextPhase) * 0.30

        switch jump {
        case 0:
            return 0.10 + priorBonus
        case 1:
            return 0.08 + priorBonus
        case 2:
            return 0.03 + priorBonus
        default:
            return -0.08 * Double(jump - 2) + priorBonus
        }
    }

    private func suggestionConfidence(
        selectedScore: Double,
        alternateScore: Double,
        waymarkerStrength: Double,
        phraseStrength: Double
    ) -> Double {
        let margin = max(0.0, selectedScore - alternateScore)
        let base = min(selectedScore / 1.1, 1.0) * 0.65
        let distinction = min(margin / 0.30, 1.0) * 0.20
        let phraseBoost = min((waymarkerStrength + phraseStrength) / 0.35, 1.0) * 0.15
        return clamp(base + distinction + phraseBoost, lower: 0.0, upper: 1.0)
    }

    private func confidenceLevel(
        for confidence: Double
    ) -> HypnosisMetadata.ConfidenceLevel {
        switch confidence {
        case 0.78...:
            return .high
        case 0.50...:
            return .medium
        default:
            return .low
        }
    }

    private func suggestionRationale(
        for evidence: PhaseEvidenceBreakdown,
        section: TranscriptSectionMetrics,
        confidenceLevel: HypnosisMetadata.ConfidenceLevel
    ) -> String {
        var reasons: [String] = []

        if let leadingWaymarker = section.waymarkerMatches.first(where: { $0.phase.labelingPhase == evidence.phase.labelingPhase }) {
            reasons.append("way-marker '\(leadingWaymarker.phrase)' is active")
        }
        if let matchedPhrase = evidence.matchedPhrases.first {
            reasons.append("phrase library matches '\(matchedPhrase)'")
        }
        if evidence.positionScore >= 0.085 {
            reasons.append("session position fits \(evidence.phase.displayName.lowercased())")
        }
        if evidence.transcriptScore >= 0.32 {
            reasons.append("pace and wording fit \(evidence.phase.displayName.lowercased())")
        }

        let tone: String
        switch confidenceLevel {
        case .high:
            tone = "Phrase evidence strongly points to \(evidence.phase.displayName)."
        case .medium:
            tone = "Phrase evidence leans toward \(evidence.phase.displayName)."
        case .low:
            tone = "Phrase evidence tentatively suggests \(evidence.phase.displayName)."
        }

        let detail = reasons.prefix(3).joined(separator: ", ")
        return detail.isEmpty ? tone : "\(tone) \(detail)."
    }

    private func suggestedSegments(
        from windows: [PhaseEvidenceWindow]
    ) -> [PhaseSegment] {
        guard let firstWindow = windows.first else { return [] }
        var currentPhase = firstWindow.phase
        var buffer: [PhaseEvidenceWindow] = [firstWindow]
        var segments: [PhaseSegment] = []

        func makeSegment(from windowGroup: [PhaseEvidenceWindow]) -> PhaseSegment {
            let phase = windowGroup[0].phase
            let startTime = windowGroup[0].startTime
            let endTime = windowGroup.last?.endTime ?? windowGroup[0].endTime
            let averageConfidence = windowGroup.reduce(0.0) { $0 + $1.confidence } / Double(windowGroup.count)
            let level = confidenceLevel(for: averageConfidence)
            let rationale = Array(
                Set(windowGroup.map(\.rationale).filter { !$0.isEmpty })
            )
            .prefix(2)
            .joined(separator: " ")

            return PhaseSegment(
                phase: phase,
                startTime: startTime,
                endTime: endTime,
                characteristics: phase.displayName,
                tranceDepthEstimate: phase.tranceDepthEstimate,
                confidenceLevel: level,
                confidenceRationale: rationale.isEmpty ? nil : rationale
            )
        }

        for window in windows.dropFirst() {
            if window.phase == currentPhase {
                buffer.append(window)
            } else {
                segments.append(makeSegment(from: buffer))
                buffer = [window]
                currentPhase = window.phase
            }
        }

        if !buffer.isEmpty {
            segments.append(makeSegment(from: buffer))
        }

        return mergeShortSuggestedSegments(segments)
    }

    private func mergeShortSuggestedSegments(
        _ segments: [PhaseSegment]
    ) -> [PhaseSegment] {
        guard segments.count >= 2 else { return segments }
        var adjusted = segments
        // These are phrase-driven *evidence windows*, not final second-by-second
        // playback phases, so they use a smaller minimum than the keyword
        // pipeline's collapse pass. A 25s floor erased genuine ~16–24s proposal
        // phases (e.g. a short conditioning or emergence block) on brief clips,
        // collapsing multi-phase proposals down to one or two phases.
        let minimumDuration = min(18.0, Double(config.minimumPhaseDurationSeconds) * 0.60)

        var index = 0
        while index < adjusted.count {
            let duration = adjusted[index].endTime - adjusted[index].startTime
            guard duration < minimumDuration, adjusted.count > 1 else {
                index += 1
                continue
            }

            if index == 0 {
                adjusted[1] = PhaseSegment(
                    id: adjusted[1].id,
                    phase: adjusted[1].phase,
                    startTime: adjusted[0].startTime,
                    endTime: adjusted[1].endTime,
                    characteristics: adjusted[1].characteristics,
                    tranceDepthEstimate: adjusted[1].tranceDepthEstimate,
                    linguisticMarkers: adjusted[1].linguisticMarkers,
                    confidenceLevel: adjusted[1].confidenceLevel,
                    confidenceRationale: adjusted[1].confidenceRationale,
                    transitionTarget: adjusted[1].transitionTarget
                )
                adjusted.remove(at: 0)
                continue
            }

            let previous = adjusted[index - 1]
            adjusted[index - 1] = PhaseSegment(
                id: previous.id,
                phase: previous.phase,
                startTime: previous.startTime,
                endTime: adjusted[index].endTime,
                characteristics: previous.characteristics,
                tranceDepthEstimate: previous.tranceDepthEstimate,
                linguisticMarkers: previous.linguisticMarkers,
                confidenceLevel: previous.confidenceLevel,
                confidenceRationale: previous.confidenceRationale,
                transitionTarget: previous.transitionTarget
            )
            adjusted.remove(at: index)
        }

        return mergeAdjacentPhaseSegments(adjusted)
    }

    private func candidateBoundaryTimes(
        lowerBound: TimeInterval,
        upperBound: TimeInterval,
        preferred: TimeInterval
    ) -> [TimeInterval] {
        var candidates = Set(
            stride(
                from: ceil(lowerBound),
                through: floor(upperBound),
                by: 1.0
            )
            .map { Double($0) }
        )
        candidates.insert(preferred)
        return candidates.sorted()
    }

    private func boundaryAlignmentScore(
        leftPhase: HypnosisMetadata.Phase,
        rightPhase: HypnosisMetadata.Phase,
        leftSection: TranscriptSectionMetrics,
        rightSection: TranscriptSectionMetrics,
        originalBoundary: TimeInterval,
        candidateBoundary: TimeInterval
    ) -> Double {
        let leftOwnSupport = transcriptSupportScore(for: leftPhase, section: leftSection)
        let rightOwnSupport = transcriptSupportScore(for: rightPhase, section: rightSection)
        let leftLeakage = transcriptSupportScore(for: rightPhase, section: leftSection)
        let rightLeakage = transcriptSupportScore(for: leftPhase, section: rightSection)

        let phaseSeparation = max(0.0, leftOwnSupport - leftLeakage)
            + max(0.0, rightOwnSupport - rightLeakage)
        let featureShift =
            abs(rightSection.normalizedWordsPerMinute - leftSection.normalizedWordsPerMinute) * boundaryRefinement.paceShiftWeight
            + abs(rightSection.normalizedRepetitionDensity - leftSection.normalizedRepetitionDensity) * boundaryRefinement.repetitionShiftWeight
            + abs(rightSection.normalizedLexicalDiversity - leftSection.normalizedLexicalDiversity) * boundaryRefinement.lexicalShiftWeight
            + abs(rightSection.normalizedSpeechCoverage - leftSection.normalizedSpeechCoverage) * boundaryRefinement.coverageShiftWeight
        let phaseTransitionBonus = transitionTraitBonus(
            leftPhase: leftPhase,
            rightPhase: rightPhase,
            leftSection: leftSection,
            rightSection: rightSection
        )
        let distancePenalty = abs(candidateBoundary - originalBoundary) * boundaryRefinement.distancePenaltyWeight

        return (leftOwnSupport * boundaryRefinement.phaseSupportWeight)
            + (rightOwnSupport * boundaryRefinement.phaseSupportWeight)
            + (phaseSeparation * boundaryRefinement.phaseSeparationWeight)
            + featureShift
            + phaseTransitionBonus
            - distancePenalty
    }

    private func transitionTraitBonus(
        leftPhase: HypnosisMetadata.Phase,
        rightPhase: HypnosisMetadata.Phase,
        leftSection: TranscriptSectionMetrics,
        rightSection: TranscriptSectionMetrics
    ) -> Double {
        let paceDelta = rightSection.normalizedWordsPerMinute - leftSection.normalizedWordsPerMinute
        let repetitionDelta = rightSection.normalizedRepetitionDensity - leftSection.normalizedRepetitionDensity
        let varietyDelta = rightSection.normalizedLexicalDiversity - leftSection.normalizedLexicalDiversity

        switch rightPhase {
        case .induction:
            return max(0.0, -paceDelta) * 0.07
                + max(0.0, rightSection.normalizedSpeechCoverage - leftSection.normalizedSpeechCoverage) * 0.05
        case .fractionation, .deepening, .confusion:
            return max(0.0, repetitionDelta) * 0.08
                + max(0.0, -paceDelta) * 0.06
        case .therapy, .suggestions, .eroticSuggestions:
            return max(0.0, rightSection.normalizedSpeechCoverage - leftSection.normalizedSpeechCoverage) * 0.05
                + max(0.0, varietyDelta) * 0.04
        case .brainwashing, .conditioning:
            return max(0.0, repetitionDelta) * 0.10
                + max(0.0, -paceDelta) * 0.05
        case .emergence:
            return max(0.0, paceDelta) * 0.09
                + max(0.0, -repetitionDelta) * 0.08
                + max(0.0, varietyDelta) * 0.05
        case .preTalk:
            return max(0.0, paceDelta) * 0.05
                + max(0.0, varietyDelta) * 0.05
        case .transitional:
            return 0.0
        }
    }

    func enrichSegmentsWithTranscriptConfidence(
        _ phaseSegments: [PhaseSegment],
        transcriptAnalysis: TranscriptAnalysis
    ) -> [PhaseSegment] {
        phaseSegments.map { segment in
            let section = transcriptAnalysis.sections.first(where: { $0.id == segment.id })
                ?? transcriptAnalysis.section(at: (segment.startTime + segment.endTime) / 2)
            guard let section else { return segment }

            let scored = transcriptConfidence(for: segment.phase, section: section)
            return PhaseSegment(
                id: segment.id,
                phase: segment.phase,
                startTime: segment.startTime,
                endTime: segment.endTime,
                characteristics: segment.characteristics,
                tranceDepthEstimate: segment.tranceDepthEstimate,
                linguisticMarkers: segment.linguisticMarkers,
                confidenceLevel: scored.level,
                confidenceRationale: scored.rationale,
                transitionTarget: segment.transitionTarget
            )
        }
    }

    private func transcriptConfidence(
        for phase: HypnosisMetadata.Phase,
        section: TranscriptSectionMetrics
    ) -> (level: HypnosisMetadata.ConfidenceLevel, rationale: String?) {
        let traitAlignment = phaseTraitAlignment(for: phase, section: section)
        let keywordAlignment = phaseKeywordAlignment(for: phase, section: section)
        let durationSupport = clamp(section.duration / 45.0, lower: 0.35, upper: 1.0)
        let confidenceScore = transcriptSupportScore(
            traitAlignment: traitAlignment,
            keywordAlignment: keywordAlignment,
            durationSupport: durationSupport
        )

        let level: HypnosisMetadata.ConfidenceLevel
        switch confidenceScore {
        case 0.78...:
            level = .high
        case 0.50...:
            level = .medium
        default:
            level = .low
        }

        let rationale = confidenceRationale(
            for: phase,
            section: section,
            traitAlignment: traitAlignment,
            keywordAlignment: keywordAlignment,
            durationSupport: durationSupport,
            level: level
        )
        return (level, rationale)
    }

    private func transcriptSupportScore(
        for phase: HypnosisMetadata.Phase,
        section: TranscriptSectionMetrics
    ) -> Double {
        let traitAlignment = phaseTraitAlignment(for: phase, section: section)
        let keywordAlignment = phaseKeywordAlignment(for: phase, section: section)
        let durationSupport = clamp(section.duration / 45.0, lower: 0.35, upper: 1.0)
        return transcriptSupportScore(
            traitAlignment: traitAlignment,
            keywordAlignment: keywordAlignment,
            durationSupport: durationSupport
        )
    }

    private func transcriptSupportScore(
        traitAlignment: Double,
        keywordAlignment: Double,
        durationSupport: Double
    ) -> Double {
        (traitAlignment * 0.45) + (keywordAlignment * 0.40) + (durationSupport * 0.15)
    }

    private func intrinsicQualityScore(
        for phaseSegments: [PhaseSegment],
        transcriptAnalysis: TranscriptAnalysis
    ) -> Double {
        guard !phaseSegments.isEmpty else { return 0 }

        let totalDuration = max(phaseSegments.reduce(0.0) { $0 + max(0, $1.endTime - $1.startTime) }, 0.001)
        let transcriptSupport = phaseSegments.reduce(0.0) { partial, segment in
            let midpoint = (segment.startTime + segment.endTime) / 2
            guard let section = transcriptAnalysis.section(at: midpoint) else { return partial }
            let segmentDuration = max(0, segment.endTime - segment.startTime)
            return partial + transcriptSupportScore(for: segment.phase, section: section) * segmentDuration
        } / totalDuration

        let distinctPhaseScore = clamp(Double(Set(phaseSegments.map(\.phase)).count) / 5.0, lower: 0.25, upper: 1.0)
        let shortRunRatio = phaseSegments.reduce(0.0) { partial, segment in
            let segmentDuration = max(0, segment.endTime - segment.startTime)
            return partial + (segmentDuration < 18 ? segmentDuration : 0)
        } / totalDuration
        let durationBalance = clamp(1.0 - shortRunRatio, lower: 0.25, upper: 1.0)
        return (transcriptSupport * 0.70)
            + (distinctPhaseScore * 0.15)
            + (durationBalance * 0.15)
    }

    /// Compares analyzer sources primarily with independent transcript traits,
    /// coverage, confidence, and stability. Semantic evidence remains a minority
    /// signal so obvious label/content mismatches can still be rejected without
    /// grading the keyword model solely against its own feature system.
    private func sourceSelectionQualityScore(
        for phaseSegments: [PhaseSegment],
        transcription: AudioTranscriptionResult
    ) -> Double {
        guard phaseSegments.isEmpty == false else { return 0 }
        let analysis = TranscriptFeatureAnalyzer().analyze(
            transcription: transcription,
            phases: phaseSegments
        )
        let totalDuration = max(
            phaseSegments.reduce(0.0) { $0 + max(0, $1.endTime - $1.startTime) },
            0.001
        )
        let traitSupport = phaseSegments.reduce(0.0) { partial, segment in
            let midpoint = (segment.startTime + segment.endTime) / 2
            guard let section = analysis.section(at: midpoint) else { return partial }
            let segmentDuration = max(0, segment.endTime - segment.startTime)
            return partial + phaseTraitAlignment(for: segment.phase, section: section) * segmentDuration
        } / totalDuration
        let semanticSupport = phaseSegments.reduce(0.0) { partial, segment in
            let midpoint = (segment.startTime + segment.endTime) / 2
            guard let section = analysis.section(at: midpoint) else { return partial }
            let segmentDuration = max(0, segment.endTime - segment.startTime)
            return partial + transcriptSupportScore(for: segment.phase, section: section) * segmentDuration
        } / totalDuration
        let confidence = phaseSegments.reduce(0.0) { partial, segment in
            let segmentDuration = max(0, segment.endTime - segment.startTime)
            return partial + segment.confidenceLevel.numericValue * segmentDuration
        } / totalDuration
        let coveredDuration = min(totalDuration, max(transcription.duration, 0.001))
        let coverage = clamp(
            coveredDuration / max(transcription.duration, 0.001),
            lower: 0,
            upper: 1
        )
        let shortRunDuration = phaseSegments.reduce(0.0) { partial, segment in
            let duration = max(0, segment.endTime - segment.startTime)
            return partial + (duration < 18 ? duration : 0)
        }
        let stability = clamp(1 - (shortRunDuration / totalDuration), lower: 0.25, upper: 1)
        return (traitSupport * 0.35)
            + (semanticSupport * 0.35)
            + (confidence * 0.10)
            + (coverage * 0.10)
            + (stability * 0.10)
    }

    private func phaseTraitAlignment(
        for phase: HypnosisMetadata.Phase,
        section: TranscriptSectionMetrics
    ) -> Double {
        let pace = section.normalizedWordsPerMinute
        let repetition = section.normalizedRepetitionDensity
        let variety = section.normalizedLexicalDiversity
        let coverage = section.normalizedSpeechCoverage

        switch phase {
        case .preTalk:
            return average(
                scoreAbove(pace, threshold: 1.05),
                scoreAbove(variety, threshold: 1.0),
                scoreBelow(repetition, threshold: 1.0)
            )
        case .induction:
            return average(
                scoreBelow(pace, threshold: 1.0),
                scoreAbove(coverage, threshold: 0.95),
                scoreBelow(variety, threshold: 1.05)
            )
        case .fractionation:
            return average(
                scoreNear(pace, target: 1.0, tolerance: 0.30),
                scoreAbove(repetition, threshold: 1.05),
                scoreAbove(coverage, threshold: 0.95)
            )
        case .deepening:
            return average(
                scoreBelow(pace, threshold: 0.95),
                scoreAbove(repetition, threshold: 1.10),
                scoreBelow(variety, threshold: 1.0)
            )
        case .confusion:
            return average(
                scoreAbove(variety, threshold: 1.05),
                scoreAbove(repetition, threshold: 0.95),
                scoreNear(pace, target: 1.0, tolerance: 0.40)
            )
        case .therapy:
            return average(
                scoreAbove(variety, threshold: 1.0),
                scoreBelow(repetition, threshold: 1.15),
                scoreAbove(coverage, threshold: 0.95)
            )
        case .suggestions:
            return average(
                scoreNear(pace, target: 1.0, tolerance: 0.35),
                scoreAbove(repetition, threshold: 1.0),
                scoreAbove(coverage, threshold: 0.95)
            )
        case .eroticSuggestions:
            return average(
                scoreNear(pace, target: 0.95, tolerance: 0.35),
                scoreAbove(repetition, threshold: 1.05),
                scoreAbove(coverage, threshold: 0.95)
            )
        case .brainwashing:
            return average(
                scoreBelow(pace, threshold: 0.95),
                scoreAbove(repetition, threshold: 1.35),
                scoreBelow(variety, threshold: 0.95)
            )
        case .conditioning:
            return average(
                scoreNear(pace, target: 0.95, tolerance: 0.35),
                scoreAbove(repetition, threshold: 1.10),
                scoreAbove(coverage, threshold: 0.95)
            )
        case .emergence:
            return average(
                scoreAbove(pace, threshold: 1.05),
                scoreBelow(repetition, threshold: 0.95),
                scoreAbove(variety, threshold: 1.0)
            )
        case .transitional:
            return average(
                scoreNear(pace, target: 1.0, tolerance: 0.40),
                scoreNear(repetition, target: 1.0, tolerance: 0.40),
                scoreNear(variety, target: 1.0, tolerance: 0.40)
            )
        }
    }

    private func phaseKeywordAlignment(
        for phase: HypnosisMetadata.Phase,
        section: TranscriptSectionMetrics
    ) -> Double {
        let phaseWords = phaseKeywordTokens(for: phase)
        let phasePhrases = phaseKeywordPhrases(for: phase)
        let waymarkerAlignment = phaseWaymarkerAlignment(for: phase, section: section)
        guard !phaseWords.isEmpty || !phasePhrases.isEmpty || waymarkerAlignment > 0 else {
            return 0.35
        }

        let distinctiveMatches = section.topDistinctiveWords.filter { phaseWords.contains($0.word) }.count
        let commonMatches = section.topWords.filter { phaseWords.contains($0.word) }.count
        let distinctivePhraseMatches = section.topDistinctivePhrases.filter { phasePhrases.contains($0.phrase) }.count
        let commonPhraseMatches = section.topPhrases.filter { phasePhrases.contains($0.phrase) }.count
        let wordAlignment = clamp(
            (Double(distinctiveMatches) * 0.45) + (Double(commonMatches) * 0.15),
            lower: 0.0,
            upper: 1.0
        )
        let phraseAlignment = clamp(
            (Double(distinctivePhraseMatches) * 0.50) + (Double(commonPhraseMatches) * 0.18),
            lower: 0.0,
            upper: 1.0
        )

        // Weight the three evidence channels, but redistribute the weight of any
        // channel that has no signal onto the channels that do. Otherwise a
        // section with strong, unambiguous vocabulary matches (e.g. repeated
        // "obey"/"programmed") but no multi-word phrases or way-marker phrases is
        // structurally capped at 0.45 and can never fully support its phase —
        // even though the word evidence alone is decisive.
        let channels: [(value: Double, baseWeight: Double, hasSignal: Bool)] = [
            (wordAlignment, 0.45, distinctiveMatches > 0 || commonMatches > 0),
            (phraseAlignment, 0.35, distinctivePhraseMatches > 0 || commonPhraseMatches > 0),
            (waymarkerAlignment, 0.20, waymarkerAlignment > 0)
        ]
        let activeWeight = channels.filter(\.hasSignal).reduce(0.0) { $0 + $1.baseWeight }
        guard activeWeight > 0 else {
            // No channel has any signal: fall back to the plain weighted sum.
            return clamp(
                (wordAlignment * 0.45) + (phraseAlignment * 0.35) + (waymarkerAlignment * 0.20),
                lower: 0.0,
                upper: 1.0
            )
        }
        let combined = channels.reduce(0.0) { partial, channel in
            guard channel.hasSignal else { return partial }
            return partial + channel.value * (channel.baseWeight / activeWeight)
        }
        return clamp(combined, lower: 0.0, upper: 1.0)
    }

    private func confidenceRationale(
        for phase: HypnosisMetadata.Phase,
        section: TranscriptSectionMetrics,
        traitAlignment: Double,
        keywordAlignment: Double,
        durationSupport: Double,
        level: HypnosisMetadata.ConfidenceLevel
    ) -> String {
        var reasons: [String] = []

        // Evidence-match reasons first: direct vocabulary / phrase / way-marker
        // hits are the strongest justification and must survive the prefix cap
        // below, ahead of the generic prosody prose.
        let matchedWords = section.topDistinctiveWords
            .map(\.word)
            .filter { phaseKeywordTokens(for: phase).contains($0) }
        if !matchedWords.isEmpty {
            reasons.append("standout words match \(phase.displayName.lowercased()) vocabulary")
        }

        let matchedPhrases = section.topDistinctivePhrases
            .map(\.phrase)
            .filter { phaseKeywordPhrases(for: phase).contains($0) }
        if !matchedPhrases.isEmpty {
            reasons.append("standout phrases look like \(phase.displayName.lowercased()) way-markers")
        }

        let waymarkers = section.waymarkerMatches
            .filter { $0.phase.labelingPhase == phase.labelingPhase }
            .map(\.phrase)
        if !waymarkers.isEmpty {
            reasons.append("explicit hypnosis marker phrases are present")
        }

        if section.normalizedWordsPerMinute < 0.92 {
            reasons.append("pace is below the file average")
        } else if section.normalizedWordsPerMinute > 1.08 {
            reasons.append("pace is above the file average")
        }

        if section.normalizedRepetitionDensity > 1.15 {
            reasons.append("repetition is elevated")
        } else if section.normalizedRepetitionDensity < 0.90 {
            reasons.append("repetition is lighter than average")
        }

        if section.normalizedLexicalDiversity > 1.08 {
            reasons.append("lexical variety is elevated")
        } else if section.normalizedLexicalDiversity < 0.92 {
            reasons.append("language is tighter than average")
        }

        if section.duration < 25 {
            reasons.append("the section is short")
        } else if durationSupport > 0.9 {
            reasons.append("the section has enough duration for a stable read")
        }

        let tone: String
        if level == .high {
            tone = "Transcript cues strongly support \(phase.displayName)."
        } else if level == .medium {
            tone = traitAlignment >= keywordAlignment
                ? "Transcript cues are reasonably consistent with \(phase.displayName)."
                : "Transcript cues partially support \(phase.displayName)."
        } else {
            tone = "Transcript cues are mixed for \(phase.displayName)."
        }

        let detail = reasons.prefix(3).joined(separator: ", ")
        return detail.isEmpty ? tone : "\(tone) \(detail)."
    }

    private func phaseKeywordTokens(for phase: HypnosisMetadata.Phase) -> Set<String> {
        keywordTokensByPhase[phase] ?? []
    }

    private static func makeKeywordTokens(
        for phase: HypnosisMetadata.Phase,
        knowledge: CorpusPhaseKnowledge,
        corpusLearning: AnalyzerConfig.CorpusLearning
    ) -> Set<String> {
        let tokens = HypnosisPhaseKeywords.all
            .filter { $0.phase == phase }
            .flatMap { keyword in
                keyword.phrase
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
                    .map { String($0).lowercased() }
            }
            .filter { !$0.isEmpty }
        let phraseTokens = (knowledge.phraseWeights[phase] ?? [:])
            .keys
            .filter { phrase in
                corpusLearning.sourceMultiplier(
                    for: knowledge.phraseSourcePacks[phase]?[phrase] ?? [],
                    phase: phase
                ) > 0
            }
            .flatMap { phrase in
                phrase
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
                    .map { String($0).lowercased() }
            }
        let learnedTokens = (knowledge.phaseTokens[phase] ?? [])
            .filter { token in
                corpusLearning.sourceMultiplier(
                    for: knowledge.keywordSourcePacks[phase]?[token] ?? [],
                    phase: phase
                ) > 0
            }
        return Set(tokens)
            .union(learnedTokens)
            .union(phraseTokens)
    }

    private func phaseKeywordPhrases(for phase: HypnosisMetadata.Phase) -> Set<String> {
        keywordPhrasesByPhase[phase] ?? []
    }

    private static func makeKeywordPhrases(
        for phase: HypnosisMetadata.Phase,
        knowledge: CorpusPhaseKnowledge,
        corpusLearning: AnalyzerConfig.CorpusLearning
    ) -> Set<String> {
        let configuredPhrases = HypnosisPhaseKeywords.all
            .filter { $0.phase == phase && $0.phrase.contains(" ") }
            .map { normalizedPhrase($0.phrase) }
        let learnedPhrases = (knowledge.phraseWeights[phase] ?? [:])
            .keys
            .filter { phrase in
                corpusLearning.sourceMultiplier(
                    for: knowledge.phraseSourcePacks[phase]?[phrase] ?? [],
                    phase: phase
                ) > 0
            }
            .map(normalizedPhrase)
        let waymarkerPhrases = HypnosisWaymarkerLexicon.phrases(for: phase)
        return Set(configuredPhrases)
            .union(learnedPhrases)
            .union(waymarkerPhrases)
    }

    private func phaseWaymarkerAlignment(
        for phase: HypnosisMetadata.Phase,
        section: TranscriptSectionMetrics
    ) -> Double {
        let matches = section.waymarkerMatches.filter { $0.phase.labelingPhase == phase.labelingPhase }
        guard !matches.isEmpty else { return 0.0 }
        let totalScore = matches.reduce(0.0) { $0 + $1.score }
        return clamp(totalScore / 2.5, lower: 0.0, upper: 1.0)
    }

    private func normalizePhrase(_ phrase: String) -> String {
        Self.normalizedPhrase(phrase)
    }

    private static func normalizedPhrase(_ phrase: String) -> String {
        phrase
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map { String($0).lowercased() }
            .joined(separator: " ")
    }

    private func transitionPrior(
        from previousPhase: HypnosisMetadata.Phase,
        to nextPhase: HypnosisMetadata.Phase
    ) -> Double {
        return (corpusKnowledge.transitionPriors[previousPhase]?[nextPhase] ?? 0.0)
            * corpusLearning.transitionPriorMultiplier
    }

    private func scoreAbove(_ value: Double, threshold: Double) -> Double {
        clamp((value - threshold) / 0.35, lower: 0.0, upper: 1.0)
    }

    private func scoreBelow(_ value: Double, threshold: Double) -> Double {
        clamp((threshold - value) / 0.35, lower: 0.0, upper: 1.0)
    }

    private func scoreNear(_ value: Double, target: Double, tolerance: Double) -> Double {
        clamp(1.0 - (abs(value - target) / tolerance), lower: 0.0, upper: 1.0)
    }

    private func average(_ values: Double...) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
