//
//  PlaylistWholeSessionAnalyzer.swift
//  Ilumionate
//
//  Builds a fast playlist-level analysis from already analyzed audio files.
//

import Foundation

struct PlaylistWholeSessionBuildResult: Sendable {
    let virtualAudioFile: AudioFile
    let analysis: AnalysisResult
    let summary: PlaylistWholeSessionAnalysis
}

enum PlaylistWholeSessionAnalysisError: LocalizedError, Equatable {
    case emptyPlaylist
    case missingAudioFiles([String])
    case missingAnalyses([String])

    var errorDescription: String? {
        switch self {
        case .emptyPlaylist:
            return "Add sessions before building a whole-journey analysis."
        case .missingAudioFiles(let names):
            return "Missing audio files: \(names.joined(separator: ", "))"
        case .missingAnalyses(let names):
            return "Analyze these sessions first: \(names.joined(separator: ", "))"
        }
    }
}

struct PlaylistWholeSessionAnalyzer: Sendable {

    func build(
        playlist: Playlist,
        audioFiles: [AudioFile]
    ) throws -> PlaylistWholeSessionBuildResult {
        guard !playlist.items.isEmpty else { throw PlaylistWholeSessionAnalysisError.emptyPlaylist }

        // Keyed by the item, not by `audioFileId`: the recorded id can be stale
        // (see `PlaylistTrackBinding`), and a library holding one id twice used
        // to trap `Dictionary(uniqueKeysWithValues:)` outright.
        let fileLookup = PlaylistTrackBinding.resolvedFiles(for: playlist.items, in: audioFiles)
        let missingFiles = playlist.items
            .filter { fileLookup[$0.id] == nil }
            .map(\.displayName)
        guard missingFiles.isEmpty else {
            throw PlaylistWholeSessionAnalysisError.missingAudioFiles(missingFiles)
        }

        let tracks = playlist.items.enumerated().compactMap { index, item -> TrackAnalysis? in
            guard let file = fileLookup[item.id] else { return nil }
            return TrackAnalysis(index: index, item: item, audioFile: file, analysis: file.analysisResult)
        }

        let missingAnalyses = tracks
            .filter { $0.analysis == nil }
            .map { $0.item.displayName }
        guard missingAnalyses.isEmpty else {
            throw PlaylistWholeSessionAnalysisError.missingAnalyses(missingAnalyses)
        }

        let analyzedTracks = tracks.compactMap { track -> AnalyzedTrack? in
            guard let analysis = track.analysis else { return nil }
            return AnalyzedTrack(
                index: track.index,
                item: track.item,
                audioFile: track.audioFile,
                analysis: analysis
            )
        }

        let totalDuration = playlist.totalDuration
        let timeline = buildTimeline(for: analyzedTracks, totalDuration: totalDuration)
        let combinedAnalysis = buildAnalysis(
            playlist: playlist,
            tracks: timeline.tracks,
            phases: timeline.phaseSegments,
            totalDuration: totalDuration
        )

        var virtualAudioFile = AudioFile(
            id: playlist.id,
            filename: "\(playlist.name.isEmpty ? "Playlist" : playlist.name).playlist",
            duration: totalDuration,
            fileSize: 0
        )
        virtualAudioFile.analysisResult = combinedAnalysis

        let summary = PlaylistWholeSessionAnalysis(
            generatedAt: Date(),
            sourceSignature: playlist.sourceSignature,
            duration: totalDuration,
            trackCount: playlist.itemCount,
            contentType: combinedAnalysis.contentType,
            phases: timeline.phaseSummaries,
            warnings: timeline.warnings
        )

        return PlaylistWholeSessionBuildResult(
            virtualAudioFile: virtualAudioFile,
            analysis: combinedAnalysis,
            summary: summary
        )
    }

    // MARK: - Timeline

    private func buildTimeline(
        for tracks: [AnalyzedTrack],
        totalDuration: TimeInterval
    ) -> PlaylistTimeline {
        var offset: TimeInterval = 0
        var placedTracks: [PlacedTrack] = []
        var phaseSegments: [PhaseSegment] = []
        var phaseSummaries: [PlaylistWholeSessionPhaseSummary] = []
        var warnings: [String] = []

        for track in tracks {
            let start = offset
            let end = min(totalDuration, start + track.item.duration)
            let roleResult = inferRole(for: track, trackCount: tracks.count)
            let phase = phaseForRole(
                roleResult.role,
                preferredPhase: dominantPhase(in: track.analysis, isLastTrack: track.index == tracks.count - 1)
            )
            let confidence: HypnosisMetadata.ConfidenceLevel = roleResult.usedFilenameSignal ? .high : .medium

            if !roleResult.usedFilenameSignal {
                warnings.append("Inferred \(track.item.displayName) as \(roleResult.role.displayName) from playlist position and analysis.")
            }

            let segment = PhaseSegment(
                phase: phase,
                startTime: start,
                endTime: end,
                characteristics: "\(track.item.displayName) used as playlist \(roleResult.role.displayName.lowercased()).",
                tranceDepthEstimate: phase.tranceDepthEstimate,
                linguisticMarkers: offsetMarkers(from: track.analysis, by: start),
                confidenceLevel: confidence,
                confidenceRationale: roleResult.usedFilenameSignal
                    ? "Matched playlist role wording in the filename."
                    : "No explicit role wording found; inferred from order and the strongest analyzed phase."
            )

            phaseSegments.append(segment)
            phaseSummaries.append(PlaylistWholeSessionPhaseSummary(
                phase: phase,
                role: roleResult.role,
                startTime: start,
                endTime: end
            ))
            placedTracks.append(PlacedTrack(track: track, startTime: start, endTime: end, role: roleResult.role, phase: phase))
            offset = end
        }

        let mergedPhases = mergeAdjacentPhases(phaseSegments)
        let mergedSummaries = mergeAdjacentSummaries(phaseSummaries)

        return PlaylistTimeline(
            tracks: placedTracks,
            phaseSegments: mergedPhases,
            phaseSummaries: mergedSummaries,
            warnings: warnings
        )
    }

    private func inferRole(for track: AnalyzedTrack, trackCount: Int) -> (role: PlaylistSessionRole, usedFilenameSignal: Bool) {
        if let catalogRole = KnownAudioCatalog.shared
            .match(audioFile: track.audioFile)?
            .entry.role {
            return (catalogRole, true)
        }

        let roleText = [
            track.item.filename,
            track.audioFile.displayName
        ]
        .joined(separator: " ")
        .lowercased()

        if containsAny(roleText, ["awak", "emerg", "return", "wake up", "wake-up", "count up"]) {
            return (.emergence, true)
        }
        if containsAny(roleText, ["deepener", "deepening", "deepen", "fractionation", "fractionate"]) {
            return (.deepening, true)
        }
        if containsAny(roleText, ["induction", "induce", "eye fixation", "progressive relaxation"]) {
            return (.induction, true)
        }
        if containsAny(roleText, ["suggestion", "affirmation", "therapy", "therapeutic", "conditioning", "programming"]) {
            return (.suggestions, true)
        }

        if let dominant = dominantPhase(in: track.analysis, isLastTrack: track.index == trackCount - 1) {
            switch dominant.labelingPhase {
            case .induction:
                return (.induction, false)
            case .deepening:
                return (.deepening, false)
            case .suggestions, .brainwashing:
                return (.suggestions, false)
            case .emergence:
                return (.emergence, false)
            default:
                break
            }
        }

        if track.index == 0 {
            return (.induction, false)
        }
        if track.index == trackCount - 1 {
            return (.emergence, false)
        }
        if track.index == 1 {
            return (.deepening, false)
        }
        return (.suggestions, false)
    }

    private func phaseForRole(
        _ role: PlaylistSessionRole,
        preferredPhase: HypnosisMetadata.Phase?
    ) -> HypnosisMetadata.Phase {
        switch role {
        case .induction:
            return .induction
        case .deepening:
            return .deepening
        case .suggestions:
            return preferredPhase?.labelingPhase == .brainwashing ? .brainwashing : .suggestions
        case .emergence:
            return .emergence
        case .support:
            return preferredPhase?.labelingPhase ?? .suggestions
        }
    }

    private func dominantPhase(in analysis: AnalysisResult, isLastTrack: Bool) -> HypnosisMetadata.Phase? {
        guard let phases = analysis.hypnosisMetadata?.phases, !phases.isEmpty else { return nil }

        let candidates = phases.filter { segment in
            isLastTrack || segment.phase.labelingPhase != .emergence
        }
        let usable = candidates.isEmpty ? phases : candidates
        return usable.max { lhs, rhs in
            (lhs.endTime - lhs.startTime) < (rhs.endTime - rhs.startTime)
        }?.phase.labelingPhase
    }

    private func mergeAdjacentPhases(_ phases: [PhaseSegment]) -> [PhaseSegment] {
        guard var last = phases.first else { return [] }
        var merged: [PhaseSegment] = []

        for phase in phases.dropFirst() {
            if phase.phase.labelingPhase == last.phase.labelingPhase {
                last = PhaseSegment(
                    id: last.id,
                    phase: last.phase.labelingPhase,
                    startTime: last.startTime,
                    endTime: phase.endTime,
                    characteristics: "\(last.characteristics) \(phase.characteristics)",
                    tranceDepthEstimate: max(last.tranceDepthEstimate, phase.tranceDepthEstimate),
                    linguisticMarkers: last.linguisticMarkers + phase.linguisticMarkers,
                    confidenceLevel: minConfidence(last.confidenceLevel, phase.confidenceLevel),
                    confidenceRationale: last.confidenceRationale ?? phase.confidenceRationale,
                    transitionTarget: phase.transitionTarget
                )
            } else {
                merged.append(last)
                last = phase
            }
        }

        merged.append(last)
        return merged
    }

    private func mergeAdjacentSummaries(
        _ summaries: [PlaylistWholeSessionPhaseSummary]
    ) -> [PlaylistWholeSessionPhaseSummary] {
        guard var last = summaries.first else { return [] }
        var merged: [PlaylistWholeSessionPhaseSummary] = []

        for summary in summaries.dropFirst() {
            if summary.phase.labelingPhase == last.phase.labelingPhase && summary.role == last.role {
                last = PlaylistWholeSessionPhaseSummary(
                    id: last.id,
                    phase: last.phase.labelingPhase,
                    role: last.role,
                    startTime: last.startTime,
                    endTime: summary.endTime
                )
            } else {
                merged.append(last)
                last = summary
            }
        }

        merged.append(last)
        return merged
    }

    // MARK: - Combined Analysis

    private func buildAnalysis(
        playlist: Playlist,
        tracks: [PlacedTrack],
        phases: [PhaseSegment],
        totalDuration: TimeInterval
    ) -> AnalysisResult {
        let analyses = tracks.map(\.track.analysis)
        let totalWeight = max(totalDuration, 1)
        let energy = weightedAverage(tracks) { $0.track.analysis.energyLevel }
        let intensity = weightedAverage(tracks) { $0.track.analysis.suggestedIntensity }
        let colorTemperature = weightedOptionalAverage(tracks) { $0.track.analysis.suggestedColorTemperature }
        let lowerFrequency = weightedAverage(tracks) { $0.track.analysis.suggestedFrequencyRange.lowerBound }
        let upperFrequency = weightedAverage(tracks) { $0.track.analysis.suggestedFrequencyRange.upperBound }
        let frequencyRange = min(lowerFrequency, upperFrequency - 0.5)...max(upperFrequency, lowerFrequency + 0.5)
        let contentType = dominantContentType(from: analyses, phases: phases)

        let metadata = HypnosisMetadata(
            phases: phases,
            inductionStyle: analyses.compactMap { $0.hypnosisMetadata?.inductionStyle }.first,
            estimatedTranceDeph: deepestTranceDepth(from: analyses),
            suggestionDensity: weightedSuggestionDensity(tracks),
            languagePatterns: uniqueLanguagePatterns(from: analyses),
            detectedTechniques: offsetTechniques(from: tracks)
        )

        let keyMoments = tracks.flatMap { placedTrack in
            placedTrack.track.analysis.keyMoments.map { moment in
                KeyMoment(
                    time: min(totalDuration, placedTrack.startTime + moment.time),
                    description: "\(placedTrack.track.item.displayName): \(moment.description)",
                    action: moment.action
                )
            }
        }

        let confidence = ClassificationConfidence(
            overallConfidence: min(0.95, max(0.35, Double(analyses.count) / Double(max(playlist.itemCount, 1)))),
            isDefinitelyHypnosis: contentType.isHypnosisLike || !phases.isEmpty,
            ambiguousSegments: [],
            alternativeInterpretations: [],
            detectionCriteria: [
                "Synthesized from \(analyses.count) already analyzed playlist items.",
                "Whole-session phase boundaries use playlist order and inferred item roles."
            ]
        )

        return AnalysisResult(
            mood: dominantMood(from: tracks),
            energyLevel: clamp(energy, lower: 0, upper: 1),
            suggestedFrequencyRange: frequencyRange,
            suggestedIntensity: clamp(intensity, lower: 0.05, upper: 1.0),
            suggestedColorTemperature: colorTemperature,
            keyMoments: keyMoments,
            aiSummary: "Whole-journey analysis for \(playlist.name.isEmpty ? "playlist" : playlist.name), built from \(playlist.itemCount) analyzed session files over \(formatDuration(totalWeight)).",
            recommendedPreset: "Whole Journey",
            contentType: contentType,
            hypnosisMetadata: metadata,
            temporalAnalysis: nil,
            voiceCharacteristics: nil,
            classificationConfidence: confidence,
            expertAnalysis: nil,
            prosodicProfile: combinedProsody(from: tracks, totalDuration: totalDuration),
            techniqueDetection: combinedTechniqueDetection(from: tracks),
            transcriptAnalysis: nil
        )
    }

    private func dominantContentType(
        from analyses: [AnalysisResult],
        phases: [PhaseSegment]
    ) -> AudioContentType {
        if !phases.isEmpty || analyses.contains(where: { $0.contentType.isHypnosisLike }) {
            return .hypnosis
        }

        var weights: [String: Double] = [:]
        for analysis in analyses {
            weights[analysis.contentType.rawValue, default: 0] += 1
        }
        let raw = weights.max { $0.value < $1.value }?.key
        return raw.flatMap(AudioContentType.init(rawValue:)) ?? .unknown
    }

    private func dominantMood(from tracks: [PlacedTrack]) -> AnalysisResult.Mood {
        var weights: [String: Double] = [:]
        for track in tracks {
            weights[track.track.analysis.mood.rawValue, default: 0] += max(track.track.item.duration, 1)
        }
        let raw = weights.max { $0.value < $1.value }?.key
        return raw.flatMap(AnalysisResult.Mood.init(rawValue:)) ?? .neutral
    }

    private func deepestTranceDepth(from analyses: [AnalysisResult]) -> HypnosisMetadata.TranceDeph {
        let ranked: [(HypnosisMetadata.TranceDeph, Int)] = analyses.map {
            let depth = $0.hypnosisMetadata?.estimatedTranceDeph ?? .medium
            return (depth, depthRank(depth))
        }
        return ranked.max { $0.1 < $1.1 }?.0 ?? .medium
    }

    private func depthRank(_ depth: HypnosisMetadata.TranceDeph) -> Int {
        switch depth {
        case .light: return 0
        case .medium: return 1
        case .deep: return 2
        case .somnambulism: return 3
        }
    }

    private func weightedSuggestionDensity(_ tracks: [PlacedTrack]) -> Double? {
        weightedOptionalAverage(tracks) { $0.track.analysis.hypnosisMetadata?.suggestionDensity }
    }

    private func uniqueLanguagePatterns(from analyses: [AnalysisResult]) -> [String] {
        var seen = Set<String>()
        return analyses.flatMap { $0.hypnosisMetadata?.languagePatterns ?? [] }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private func offsetTechniques(from tracks: [PlacedTrack]) -> [HypnoticTechnique] {
        tracks.flatMap { placedTrack in
            (placedTrack.track.analysis.hypnosisMetadata?.detectedTechniques ?? []).map { technique in
                HypnoticTechnique(
                    technique: technique.technique,
                    timestamp: placedTrack.startTime + technique.timestamp,
                    description: technique.description,
                    suggestedLightSync: technique.suggestedLightSync
                )
            }
        }
    }

    private func offsetMarkers(from analysis: AnalysisResult, by offset: TimeInterval) -> [LinguisticMarker] {
        (analysis.hypnosisMetadata?.phases ?? []).flatMap(\.linguisticMarkers).map { marker in
            LinguisticMarker(
                type: marker.type,
                timestamp: offset + marker.timestamp,
                textSnippet: marker.textSnippet,
                strength: marker.strength
            )
        }
    }

    private func combinedTechniqueDetection(from tracks: [PlacedTrack]) -> TechniqueDetectionResult? {
        var techniques: [HypnoticTechnique] = []
        var markers: [LinguisticMarker] = []

        for placedTrack in tracks {
            guard let detection = placedTrack.track.analysis.techniqueDetection else { continue }
            techniques += detection.techniques.map { technique in
                HypnoticTechnique(
                    technique: technique.technique,
                    timestamp: placedTrack.startTime + technique.timestamp,
                    description: technique.description,
                    suggestedLightSync: technique.suggestedLightSync
                )
            }
            markers += detection.markers.map { marker in
                LinguisticMarker(
                    type: marker.type,
                    timestamp: placedTrack.startTime + marker.timestamp,
                    textSnippet: marker.textSnippet,
                    strength: marker.strength
                )
            }
        }

        guard !techniques.isEmpty || !markers.isEmpty else { return nil }
        return TechniqueDetectionResult(techniques: techniques, markers: markers)
    }

    private func combinedProsody(from tracks: [PlacedTrack], totalDuration: TimeInterval) -> ProsodicProfile? {
        let profiles = tracks.compactMap { placedTrack -> (PlacedTrack, ProsodicProfile)? in
            guard let profile = placedTrack.track.analysis.prosodicProfile else { return nil }
            return (placedTrack, profile)
        }
        guard let first = profiles.first else { return nil }

        let pauses = profiles.flatMap { placedTrack, profile in
            profile.pauses.map { pause in
                DetectedPause(
                    startTime: placedTrack.startTime + pause.startTime,
                    duration: pause.duration,
                    precedingText: pause.precedingText,
                    followingText: pause.followingText,
                    category: pause.category
                )
            }
        }

        return ProsodicProfile(
            windowDuration: first.1.windowDuration,
            speechRateCurve: profiles.flatMap { $0.1.speechRateCurve },
            volumeCurve: profiles.flatMap { $0.1.volumeCurve },
            pitchCurve: profiles.flatMap { $0.1.pitchCurve },
            speechSilenceRatio: profiles.flatMap { $0.1.speechSilenceRatio },
            pauses: pauses,
            totalDuration: totalDuration
        )
    }

    // MARK: - Helpers

    private func weightedAverage(
        _ tracks: [PlacedTrack],
        value: (PlacedTrack) -> Double
    ) -> Double {
        let totalWeight = max(tracks.reduce(0) { $0 + $1.track.item.duration }, 1)
        return tracks.reduce(0) { partial, track in
            partial + value(track) * max(track.track.item.duration, 1)
        } / totalWeight
    }

    private func weightedOptionalAverage(
        _ tracks: [PlacedTrack],
        value: (PlacedTrack) -> Double?
    ) -> Double? {
        var total: Double = 0
        var weight: Double = 0

        for track in tracks {
            guard let trackValue = value(track) else { continue }
            let trackWeight = max(track.track.item.duration, 1)
            total += trackValue * trackWeight
            weight += trackWeight
        }

        guard weight > 0 else { return nil }
        return total / weight
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func minConfidence(
        _ lhs: HypnosisMetadata.ConfidenceLevel,
        _ rhs: HypnosisMetadata.ConfidenceLevel
    ) -> HypnosisMetadata.ConfidenceLevel {
        lhs.numericValue <= rhs.numericValue ? lhs : rhs
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }

    private struct TrackAnalysis {
        let index: Int
        let item: PlaylistItem
        let audioFile: AudioFile
        let analysis: AnalysisResult?
    }

    private struct AnalyzedTrack {
        let index: Int
        let item: PlaylistItem
        let audioFile: AudioFile
        let analysis: AnalysisResult
    }

    private struct PlacedTrack {
        let track: AnalyzedTrack
        let startTime: TimeInterval
        let endTime: TimeInterval
        let role: PlaylistSessionRole
        let phase: HypnosisMetadata.Phase
    }

    private struct PlaylistTimeline {
        let tracks: [PlacedTrack]
        let phaseSegments: [PhaseSegment]
        let phaseSummaries: [PlaylistWholeSessionPhaseSummary]
        let warnings: [String]
    }
}
