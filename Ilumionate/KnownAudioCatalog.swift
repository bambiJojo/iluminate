//
//  KnownAudioCatalog.swift
//  Ilumionate
//

import Foundation

/// Resolves imported audio against an optional bundled transcript catalog.
///
/// No catalog state is surfaced in the interface. Files that do not confidently
/// match an entry continue through the normal on-device transcription pipeline.
nonisolated struct KnownAudioCatalog: Sendable {
    static let shared = KnownAudioCatalog()
    static let reviewedAnalysisVersion = 2

    let entries: [KnownAudioCatalogEntry]

    init(entries: [KnownAudioCatalogEntry]) {
        self.entries = entries
    }

    init(bundle: Bundle = .main, resourceName: String = "KnownAudioCatalog") {
        guard let url = Self.resourceURL(
            named: resourceName,
            in: bundle
        ),
        let data = try? Data(contentsOf: url),
        let document = try? JSONDecoder().decode(KnownAudioCatalogDocument.self, from: data),
        document.schemaVersion == 1 else {
            entries = []
            return
        }

        entries = document.entries
    }

    func match(audioFile: AudioFile) -> KnownAudioCatalogMatch? {
        if let fingerprint = audioFile.contentFingerprint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           fingerprint.isEmpty == false,
           let entry = entries.first(where: {
               $0.contentFingerprints.contains { $0.lowercased() == fingerprint }
           }) {
            return KnownAudioCatalogMatch(entry: entry, confidence: 1)
        }

        let candidates = [
            audioFile.filename,
            audioFile.trackMetadata?.embeddedTitle
        ]
        .compactMap { $0 }

        return candidates
            .compactMap(match(candidate:))
            .max { $0.confidence < $1.confidence }
    }

    func transcription(for audioFile: AudioFile) -> AudioTranscriptionResult? {
        guard let match = match(audioFile: audioFile) else { return nil }
        guard match.entry.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return TimestampedTranscriptBuilder().makeResult(
            transcript: match.entry.transcript,
            duration: audioFile.duration
        )
    }

    func verifiedMetadata(for audioFile: AudioFile) -> AudioTrackMetadata? {
        guard let match = match(audioFile: audioFile) else { return nil }
        let entry = match.entry
        return AudioTrackMetadata(
            generatedTitle: entry.title,
            creator: entry.creator,
            album: entry.series,
            genre: "Hypnosis",
            themes: ["Hypnosis", entry.seedProfile.rawValue.capitalized],
            confidence: match.confidence,
            verificationSource: "Bundled transcript catalog",
            verificationURL: entry.sourceURL
        )
    }

    /// Materializes the human-reviewed catalog evidence as an app analysis.
    ///
    /// Recognized files should never wait on a generic language model before
    /// their reviewed score becomes usable. This analysis is deliberately
    /// derived only from the versioned catalog, its transcript/audio-review
    /// evidence, and the already-authored gold timeline.
    func reviewedAnalysis(for audioFile: AudioFile) -> AnalysisResult? {
        guard audioFile.duration.isFinite, audioFile.duration > 0,
              let entry = match(audioFile: audioFile)?.entry else {
            return nil
        }

        let score = entry.goldLightScore
        let frequencies = score.moments.map(\.frequency)
        let minimumFrequency = frequencies.min() ?? 4
        let maximumFrequency = max(frequencies.max() ?? 8, minimumFrequency + 0.1)
        let averageIntensity = score.moments.isEmpty
            ? 0.5
            : score.moments.map(\.intensity).reduce(0, +) / Double(score.moments.count)
        let colorTemperatures = score.moments.compactMap(\.colorTemperature)
        let averageColorTemperature = colorTemperatures.isEmpty
            ? nil
            : colorTemperatures.reduce(0, +) / Double(colorTemperatures.count)
        let phases = reviewedPhases(for: entry, audioFile: audioFile)
        let isProvisional = score.evidenceKind == .catalogMetadata
        let confidence = isProvisional ? 0.55 : 1.0
        let verdict: ExpertAnalysis.Verdict = isProvisional
            ? .reviewRecommended
            : .productionReady
        let evidenceDescription = Self.evidenceDescription(for: score.evidenceKind)
        let timingDescription = Self.timingDescription(for: score.timingBasis)

        let expertAnalysis = ExpertAnalysis(
            qualityScore: confidence,
            verdict: verdict,
            summary: isProvisional
                ? "Catalog review \(Self.reviewedAnalysisVersion). This version \(score.scoreVersion) template is based on title and playlist intent only; supplied audio still needs a timing review."
                : "Catalog review \(Self.reviewedAnalysisVersion). This version \(score.scoreVersion) light score passed the catalog evidence, timing, transition, and safety audit.",
            findings: [
                ExpertAnalysis.Finding(
                    title: "Evidence",
                    detail: evidenceDescription,
                    severity: isProvisional ? .warning : .info
                ),
                ExpertAnalysis.Finding(
                    title: "Timing",
                    detail: timingDescription,
                    severity: isProvisional ? .warning : .info
                ),
                ExpertAnalysis.Finding(
                    title: "Playlist role",
                    detail: "Reviewed for \(Self.playlistDescription(for: score.playlistPlacement)).",
                    severity: .info
                )
            ],
            improvementActions: isProvisional
                ? [
                    ExpertAnalysis.ImprovementAction(
                        priority: 1,
                        title: "Review the source audio",
                        detail: "Confirm spoken transitions and replace the intent-only timing with reviewed anchors."
                    )
                ]
                : [],
            reviewMoments: score.evidenceAnchors.map { anchor in
                ExpertAnalysis.ReviewMoment(
                    time: anchor.position * audioFile.duration,
                    phase: phase(at: anchor.position * audioFile.duration, in: phases),
                    reason: anchor.cue
                )
            }
        )

        return AnalysisResult(
            mood: .relaxing,
            energyLevel: max(0, min(1, 1 - averageIntensity)),
            suggestedFrequencyRange: minimumFrequency...maximumFrequency,
            suggestedIntensity: averageIntensity,
            suggestedColorTemperature: averageColorTemperature,
            keyMoments: reviewedKeyMoments(for: entry, duration: audioFile.duration),
            aiSummary: isProvisional
                ? "A provisional catalog light template based on the file intent and playlist role."
                : "This recognized file uses its version \(score.scoreVersion) reviewed gold light score. It is not regenerated by on-device AI.",
            recommendedPreset: "\(entry.title) — Gold Light Score",
            contentType: entry.seedProfile == .sleep ? .sleepHypnosis : .hypnosis,
            hypnosisMetadata: HypnosisMetadata(
                phases: phases,
                inductionStyle: entry.seedProfile == .induction ? .rapid : nil,
                estimatedTranceDeph: entry.seedProfile == .sleep ? .somnambulism : .deep,
                suggestionDensity: nil,
                languagePatterns: [],
                detectedTechniques: []
            ),
            classificationConfidence: ClassificationConfidence(
                overallConfidence: confidence,
                isDefinitelyHypnosis: true,
                ambiguousSegments: [],
                alternativeInterpretations: [],
                detectionCriteria: [
                    evidenceDescription,
                    timingDescription,
                    "Matched bundled catalog entry \(entry.id)"
                ]
            ),
            expertAnalysis: expertAnalysis,
            discoveredMetadata: verifiedMetadata(for: audioFile)
        )
    }

    /// Applies a recognized catalog review without changing user-authored
    /// transcript corrections or authoritative embedded tags.
    func applyingReviewedAnalysis(to audioFile: AudioFile) -> AudioFile? {
        guard let analysis = reviewedAnalysis(for: audioFile) else { return nil }

        var updated = audioFile
        updated.analysisResult = analysis
        if AudioTranscriptionResult.sanitizedTranscriptText(updated.transcription ?? "").isEmpty,
           let bundled = transcription(for: audioFile) {
            updated.transcription = bundled.fullText
        }

        let embedded = updated.trackMetadata ?? AudioTrackMetadata()
        let metadata = embedded.mergingVerified(analysis.discoveredMetadata)
        updated.trackMetadata = metadata.isEmpty ? nil : metadata
        return updated
    }

    /// Builds the same completion payload as the normal analysis pipeline, but
    /// without invoking transcription or Foundation Models for known content.
    func reviewedCompletion(for audioFile: AudioFile) -> CompletedAnalysis? {
        guard let reviewedFile = applyingReviewedAnalysis(to: audioFile),
              let analysis = reviewedFile.analysisResult else {
            return nil
        }

        let transcription = reusableTranscription(for: reviewedFile)
            ?? AudioTranscriptionResult(
                fullText: "",
                segments: [],
                duration: audioFile.duration,
                detectedLanguage: "und"
            )
        return CompletedAnalysis(
            audioFile: reviewedFile,
            transcription: transcription,
            analysis: analysis,
            completedAt: .now
        )
    }

    /// Resolves a recognized track to its bundled canonical light score.
    ///
    /// The resource stores normalized positions because filenames can identify
    /// encodes with slightly different leading silence or duration. Materializing
    /// against the imported duration keeps the final control point sample-exact.
    @MainActor
    func goldLightSession(for audioFile: AudioFile) -> LightSession? {
        guard audioFile.duration.isFinite, audioFile.duration > 0,
              let entry = match(audioFile: audioFile)?.entry else {
            return nil
        }

        let score = entry.goldLightScore
        let moments = score.moments
            .filter {
                $0.position.isFinite
                    && $0.frequency.isFinite
                    && $0.intensity.isFinite
            }
            .sorted { $0.position < $1.position }
            .map { moment in
                LightMoment(
                    time: min(max(moment.position, 0), 1) * audioFile.duration,
                    frequency: LightSafety.clampFlashHz(moment.frequency),
                    intensity: min(max(moment.intensity, 0), 1),
                    waveform: moment.waveform.lightWaveform,
                    ramp_duration: moment.rampDuration.map {
                        min(max($0, 0), audioFile.duration)
                    },
                    bilateral: moment.bilateral,
                    bilateral_transition_duration: moment.bilateralTransitionDuration,
                    color_temperature: moment.colorTemperature
                )
            }

        guard moments.count >= 2,
              moments.first?.time == 0,
              moments.last?.time == audioFile.duration else {
            return nil
        }

        return LightSession(
            id: score.sessionID,
            session_name: "\(entry.title) — Gold Light Score",
            duration_sec: audioFile.duration,
            light_score: moments
        )
    }

    private func match(candidate: String) -> KnownAudioCatalogMatch? {
        let normalizedCandidate = Self.normalized(candidate)
        guard normalizedCandidate.count >= 6 else { return nil }

        var best: KnownAudioCatalogMatch?
        for entry in entries {
            for alias in entry.aliases + [entry.title] {
                let normalizedAlias = Self.normalized(alias)
                let confidence = Self.matchConfidence(
                    candidate: normalizedCandidate,
                    alias: normalizedAlias
                )
                guard confidence >= 0.90 else { continue }

                if best == nil || confidence > (best?.confidence ?? 0) {
                    best = KnownAudioCatalogMatch(
                        entry: entry,
                        confidence: confidence
                    )
                }
            }
        }
        return best
    }

    private static func matchConfidence(candidate: String, alias: String) -> Double {
        guard !alias.isEmpty else { return 0 }
        if candidate == alias {
            return 1
        }

        let aliasTokens = alias.split(separator: " ")
        if aliasTokens.count >= 3, candidate.hasSuffix(" \(alias)") {
            return 0.98
        }

        let candidateTokens = Set(candidate.split(separator: " ").map(String.init))
        let expectedTokens = Set(aliasTokens.map(String.init))
        guard expectedTokens.count >= 3 else { return 0 }

        let coverage = Double(candidateTokens.intersection(expectedTokens).count)
            / Double(expectedTokens.count)
        let extraTokenCount = candidateTokens.subtracting(expectedTokens).count
        if coverage == 1, extraTokenCount <= 4 {
            return 0.92
        }
        return 0
    }

    private func reusableTranscription(for audioFile: AudioFile) -> AudioTranscriptionResult? {
        let userText = AudioTranscriptionResult.sanitizedTranscriptText(
            audioFile.transcription ?? ""
        )
        if userText.isEmpty == false {
            return AudioTranscriptionResult(
                fullText: userText,
                segments: [
                    AudioTranscriptionSegment(
                        text: userText,
                        timestamp: 0,
                        duration: audioFile.duration,
                        confidence: 0.85
                    )
                ],
                duration: audioFile.duration,
                detectedLanguage: "en"
            )
        }
        return transcription(for: audioFile)
    }

    private func reviewedPhases(
        for entry: KnownAudioCatalogEntry,
        audioFile: AudioFile
    ) -> [PhaseSegment] {
        let rationale = "Boundary derived from the reviewed catalog intent and gold-score timing."
        switch entry.seedProfile {
        case .induction:
            let boundary = entry.goldLightScore.evidenceAnchors
                .last(where: { $0.position <= 0.85 })?
                .position ?? 0.65
            return [
                reviewedPhase(
                    .induction,
                    start: 0,
                    end: boundary * audioFile.duration,
                    characteristics: "Reviewed induction and entry sequence",
                    rationale: rationale
                ),
                reviewedPhase(
                    .deepening,
                    start: boundary * audioFile.duration,
                    end: audioFile.duration,
                    characteristics: "Reviewed descent and playlist handoff",
                    rationale: rationale
                )
            ]
        case .deepening:
            return [
                reviewedPhase(
                    .deepening,
                    start: 0,
                    end: audioFile.duration,
                    characteristics: "Reviewed deepening loop",
                    rationale: rationale
                )
            ]
        case .conditioning:
            return [
                reviewedPhase(
                    .conditioning,
                    start: 0,
                    end: audioFile.duration,
                    characteristics: "Reviewed conditioning or reinforcement loop",
                    rationale: rationale
                )
            ]
        case .emergence:
            let wakeStart = entry.goldLightScore.moments
                .first { $0.position >= 0.70 && $0.frequency >= 7 }
                .map(\.position) ?? 0.85
            return [
                reviewedPhase(
                    .deepening,
                    start: 0,
                    end: wakeStart * audioFile.duration,
                    characteristics: "Deep-state hold before emergence",
                    rationale: rationale
                ),
                reviewedPhase(
                    .emergence,
                    start: wakeStart * audioFile.duration,
                    end: audioFile.duration,
                    characteristics: "Reviewed alerting and playlist exit",
                    rationale: rationale
                )
            ]
        case .sleep:
            return [
                reviewedPhase(
                    .deepening,
                    start: 0,
                    end: audioFile.duration,
                    characteristics: "Reviewed sleep descent and deep-state hold",
                    rationale: rationale
                )
            ]
        }
    }

    private func reviewedPhase(
        _ phase: HypnosisMetadata.Phase,
        start: TimeInterval,
        end: TimeInterval,
        characteristics: String,
        rationale: String
    ) -> PhaseSegment {
        PhaseSegment(
            phase: phase,
            startTime: start,
            endTime: max(start, end),
            characteristics: characteristics,
            tranceDepthEstimate: phase.tranceDepthEstimate,
            confidenceLevel: .medium,
            confidenceRationale: rationale
        )
    }

    private func reviewedKeyMoments(
        for entry: KnownAudioCatalogEntry,
        duration: TimeInterval
    ) -> [KeyMoment] {
        let score = entry.goldLightScore
        let anchors = score.evidenceAnchors.isEmpty
            ? score.moments.dropFirst().dropLast().prefix(4).map {
                KnownAudioGoldEvidenceAnchor(
                    position: $0.position,
                    cue: "Reviewed light transition",
                    source: .reviewedIntent
                )
            }
            : score.evidenceAnchors

        return anchors.map { anchor in
            KeyMoment(
                time: anchor.position * duration,
                description: anchor.cue,
                action: reviewedAction(at: anchor.position, moments: score.moments)
            )
        }
    }

    private func reviewedAction(
        at position: Double,
        moments: [KnownAudioGoldLightMoment]
    ) -> LightAction {
        guard let currentIndex = moments.lastIndex(where: { $0.position <= position }) else {
            return .deepen
        }
        let previousIndex = max(moments.startIndex, currentIndex - 1)
        let current = moments[currentIndex]
        let previous = moments[previousIndex]

        if current.frequency < previous.frequency - 0.2 { return .deepen }
        if current.frequency > previous.frequency + 0.2 { return .energize }
        if current.intensity < previous.intensity - 0.03 { return .reduceIntensity }
        if current.intensity > previous.intensity + 0.03 { return .increaseIntensity }
        if (current.colorTemperature ?? 3_000) < (previous.colorTemperature ?? 3_000) {
            return .warm
        }
        return .cool
    }

    private func phase(
        at time: TimeInterval,
        in phases: [PhaseSegment]
    ) -> HypnosisMetadata.Phase? {
        phases.first { time >= $0.startTime && time <= $0.endTime }?.phase
    }

    private static func evidenceDescription(
        for evidence: KnownAudioGoldEvidenceKind
    ) -> String {
        switch evidence {
        case .communityTranscript:
            "Reviewed transcript content and session intent."
        case .localAudioReview:
            "Reviewed supplied audio timing and session intent."
        case .catalogMetadata:
            "Catalog title, intent, and playlist role only."
        }
    }

    private static func timingDescription(
        for basis: KnownAudioGoldTimingBasis
    ) -> String {
        switch basis {
        case .referenceAudio:
            "Calibrated to the supplied reference audio."
        case .transcriptMarkers:
            "Calibrated to explicit transcript timestamps."
        case .transcriptOrder:
            "Placed from reviewed transcript order against reference duration."
        case .reviewedAudioTiming:
            "Calibrated from direct review of the supplied audio."
        case .intentOnly:
            "Provisional intent-only timing."
        }
    }

    private static func playlistDescription(
        for placement: KnownAudioGoldPlaylistPlacement
    ) -> String {
        switch placement {
        case .entry:
            "playlist entry and induction handoff"
        case .early:
            "early-session deepening"
        case .earlyOrMiddle:
            "early-to-middle reinforcement"
        case .middle:
            "middle-session reinforcement"
        case .late:
            "late-session conditioning"
        case .exit:
            "alerting exit"
        case .sleepExit:
            "sleep-state exit"
        }
    }

    private static func normalized(_ value: String) -> String {
        let filename = URL(filePath: value)
            .deletingPathExtension()
            .lastPathComponent
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        var tokens = filename
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: " ",
                options: .regularExpression
            )
            .split(separator: " ")
            .map(String.init)

        if let first = tokens.first,
           let trackNumber = Int(first),
           (0...99).contains(trackNumber) {
            tokens.removeFirst()
        }

        let disposableSuffixes: Set<String> = [
            "audio", "final", "hq", "official", "remastered",
            "mp3", "m4a", "wav", "v2", "320kbps"
        ]
        while let last = tokens.last, disposableSuffixes.contains(last) {
            tokens.removeLast()
        }

        return tokens.joined(separator: " ")
    }

    private static func resourceURL(
        named resourceName: String,
        in preferredBundle: Bundle
    ) -> URL? {
        if let url = preferredBundle.url(
            forResource: resourceName,
            withExtension: "json"
        ) {
            return url
        }

        return (Bundle.allBundles + Bundle.allFrameworks)
            .lazy
            .compactMap {
                $0.url(forResource: resourceName, withExtension: "json")
            }
            .first
    }
}

private extension KnownAudioGoldWaveform {
    @MainActor
    var lightWaveform: WaveformType {
        switch self {
        case .sine:
            .sine
        case .triangle:
            .triangle
        case .softPulse:
            .softPulse
        case .noiseModulatedSine:
            .noiseModulatedSine
        }
    }
}
