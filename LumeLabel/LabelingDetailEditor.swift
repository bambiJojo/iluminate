//
//  LabelingDetailEditor.swift
//  LumeLabel
//
//  Main-actor editor model for the macOS labeling workflow.
//

import SwiftUI
import Observation
import AVFoundation

@MainActor
@Observable
final class LabelingDetailEditor {
    struct PhasePoint: Identifiable, Sendable {
        let id: UUID
        let phase: TrancePhase
        let time: TimeInterval
    }

    struct TranscriptKeyword: Identifiable, Hashable, Sendable {
        let word: String
        let count: Int
        let relativeWeight: Double?

        var id: String { word }
    }

    struct TranscriptExcerpt: Identifiable, Hashable, Sendable {
        let id: UUID
        let startTime: TimeInterval
        let endTime: TimeInterval
        let text: String
    }

    struct PhaseTranscriptInsight: Identifiable, Sendable {
        let id: UUID
        let phase: TrancePhase?
        let startTime: TimeInterval
        let endTime: TimeInterval
        let duration: TimeInterval
        let transcriptText: String
        let excerpts: [TranscriptExcerpt]
        let wordCount: Int
        let uniqueWordCount: Int
        let wordsPerMinute: Double
        let normalizedWordsPerMinute: Double
        let speechCoverage: Double
        let normalizedSpeechCoverage: Double
        let longestPause: TimeInterval
        let averageSegmentDuration: TimeInterval
        let lexicalDiversity: Double
        let normalizedLexicalDiversity: Double
        let repetitionDensity: Double
        let normalizedRepetitionDensity: Double
        let topWords: [TranscriptKeyword]
        let topDistinctiveWords: [TranscriptKeyword]
    }

    enum DiagnosticsEngine: String, Sendable {
        case keyword
        case chunked
        case ensemble

        var displayName: String {
            switch self {
            case .keyword: return "Keyword"
            case .chunked: return "Chunked AI"
            case .ensemble: return "Ensemble"
            }
        }
    }

    struct AnalyzerPhaseComparison: Identifiable, Sendable {
        let id: UUID
        let labeledPhaseID: UUID
        let labeledPhase: TrancePhase
        let labeledStartTime: TimeInterval
        let labeledEndTime: TimeInterval
        let predictedPhase: TrancePhase?
        let predictedStartTime: TimeInterval?
        let predictedEndTime: TimeInterval?
        let overlapFraction: Double
        let startDelta: TimeInterval?
        let endDelta: TimeInterval?
        let predictedConfidence: HypnosisMetadata.ConfidenceLevel?
        let predictedRationale: String?
        let evidenceWords: [TranscriptKeyword]

        var isMatch: Bool { predictedPhase == labeledPhase }
        var averageBoundaryError: TimeInterval? {
            let deltas = [startDelta, endDelta].compactMap { $0 }.map(abs)
            guard !deltas.isEmpty else { return nil }
            return deltas.reduce(0, +) / Double(deltas.count)
        }
    }

    struct AnalyzerDiagnostics: Sendable {
        let engine: DiagnosticsEngine
        let predictedPhases: [PhaseSegment]
        let comparisons: [AnalyzerPhaseComparison]
        let techniqueMarkers: [LinguisticMarker]
        let averageBoundaryError: TimeInterval?

        var labeledMatchCount: Int {
            comparisons.filter(\.isMatch).count
        }

        var mismatchCount: Int {
            comparisons.count - labeledMatchCount
        }
    }

    struct SuggestedPhaseSegment: Identifiable, Sendable {
        let id: UUID
        let phase: TrancePhase
        let startTime: TimeInterval
        let endTime: TimeInterval
        let confidence: Double
        let confidenceLevel: HypnosisMetadata.ConfidenceLevel
        let rationale: String?
    }

    private struct CachedTranscription: Codable {
        let schemaVersion: Int
        let cachedAt: Date
        let exampleID: UUID
        let audioSHA256: String
        let transcription: AudioTranscriptionResult
    }

    let fileID: LabeledFile.ID
    let orderedPhases: [TrancePhase] = TrancePhase.orderedHypnosisPhases

    var draft: LabeledFile
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var viewStart: Double = 0
    var viewEnd: Double = 1
    var lastMagnification: Double = 1
    var draggingPointID: PhasePoint.ID?
    var alertMessage: String?
    var isSaving = false
    var selectedPhaseID: UUID?
    var transcription: AudioTranscriptionResult?
    var transcriptStatusMessage: String?
    var transcriptErrorMessage: String?
    var isTranscriptLoading = false
    var phaseTranscriptInsights: [UUID: PhaseTranscriptInsight] = [:]
    var fullTranscriptInsight: PhaseTranscriptInsight?
    var analyzerDiagnostics: AnalyzerDiagnostics?
    var isDiagnosticsLoading = false
    var diagnosticsStatusMessage: String?
    var diagnosticsErrorMessage: String?
    var diagnosticsAreStale = true
    var suggestedPhaseTimeline: HypnosisPhaseAnalyzer.PhaseSuggestionTimeline?
    var isSuggestionLoading = false
    var suggestionStatusMessage: String?
    var suggestionErrorMessage: String?

    private let corpus: TrainingCorpusManager
    private var player: AVAudioPlayer?
    private var positionTask: Task<Void, Never>?
    private var transcriptAnalyzer: AudioAnalyzer?

    init(file: LabeledFile, corpus: TrainingCorpusManager) {
        self.fileID = file.id
        self.draft = file
        self.corpus = corpus
        self.draft.expectedContentType = .hypnosis
        normalizePhases()
        syncSelectedPhase()
    }

    var duration: TimeInterval { max(draft.audioDuration, 1) }
    var viewSpan: Double { max(0.001, viewEnd - viewStart) }
    var phasePoints: [PhasePoint] {
        draft.phases.map { phase in
            PhasePoint(id: phase.id, phase: phase.phase, time: phase.startTime)
        }
    }
    var activeTranscriptInsight: PhaseTranscriptInsight? {
        if let selectedPhaseID,
           let insight = phaseTranscriptInsights[selectedPhaseID] {
            return insight
        }
        return fullTranscriptInsight
    }
    var selectedPhase: LabeledFile.LabeledPhase? {
        guard let selectedPhaseID else { return nil }
        return draft.phases.first { $0.id == selectedPhaseID }
    }
    var selectedPhaseComparison: AnalyzerPhaseComparison? {
        guard let selectedPhaseID else { return nil }
        return analyzerDiagnostics?.comparisons.first { $0.labeledPhaseID == selectedPhaseID }
    }
    var hasTranscript: Bool { transcription != nil }
    var canRunAnalyzerDiagnostics: Bool {
        transcription != nil && !draft.phases.isEmpty
    }
    var canSuggestPhases: Bool { transcription != nil }
    var suggestedPhaseSegments: [SuggestedPhaseSegment] {
        (suggestedPhaseTimeline?.segments ?? []).compactMap { segment in
            guard let trancePhase = trancePhase(for: segment.phase) else { return nil }
            return SuggestedPhaseSegment(
                id: segment.id,
                phase: trancePhase,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: suggestionConfidence(for: segment),
                confidenceLevel: segment.confidenceLevel,
                rationale: segment.confidenceRationale
            )
        }
    }

    func timeToViewFrac(_ time: TimeInterval) -> Double {
        (time / duration - viewStart) / viewSpan
    }

    func timeForViewX(_ xPosition: CGFloat, width: CGFloat) -> TimeInterval {
        let normalizedX = max(0, min(1, width > 0 ? xPosition / width : 0))
        return max(0, min(duration, (viewStart + normalizedX * viewSpan) * duration))
    }

    func phaseForCanvasY(_ yPosition: CGFloat, chartHeight: CGFloat) -> TrancePhase {
        let availablePhases = orderedPhases
        guard !availablePhases.isEmpty else { return .induction }

        return availablePhases.min { lhs, rhs in
            let lhsY = chartHeight * (1 - phaseDepth(lhs))
            let rhsY = chartHeight * (1 - phaseDepth(rhs))
            return abs(lhsY - yPosition) < abs(rhsY - yPosition)
        } ?? .induction
    }

    func preparePlayer() {
        do {
            let url = corpus.audioURL(for: draft)
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func cleanup() {
        positionTask?.cancel()
        positionTask = nil
        player?.stop()
        isPlaying = false
        if let transcriptAnalyzer {
            Task { await transcriptAnalyzer.cancelTranscription() }
        }
    }

    func clearAlert() {
        alertMessage = nil
    }

    func togglePlayback() {
        guard let player else {
            alertMessage = "Audio player is unavailable for this file."
            return
        }

        if isPlaying {
            player.pause()
            positionTask?.cancel()
            positionTask = nil
            isPlaying = false
            return
        }

        player.play()
        isPlaying = true
        positionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.currentTime = player.currentTime
                if player.currentTime >= player.duration {
                    self.isPlaying = false
                    break
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(duration, time))
        player?.currentTime = clamped
        currentTime = clamped
    }

    func seekRelative(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func zoomAround(_ center: Double, scale: Double) {
        guard scale.isFinite, scale > 0 else { return }
        let newSpan = max(0.005, min(1.0, viewSpan / scale))
        let newStart = max(0, min(1 - newSpan, center - newSpan / 2))
        viewStart = newStart
        viewEnd = newStart + newSpan
    }

    func zoomIn() {
        zoomAround(currentTime / duration, scale: 2)
    }

    func zoomOut() {
        zoomAround(currentTime / duration, scale: 0.5)
    }

    func zoomFit() {
        viewStart = 0
        viewEnd = 1
    }

    func markPhaseStart(_ phase: TrancePhase) {
        let maxStartTime = max(duration - 0.001, 0)
        let clampedTime = max(0, min(maxStartTime, currentTime))
        if let existingIndex = draft.phases.firstIndex(where: { abs($0.startTime - clampedTime) < 0.05 }) {
            draft.phases[existingIndex].phase = phase
            draft.phases[existingIndex].startTime = clampedTime
        } else {
            draft.phases.append(
                LabeledFile.LabeledPhase(
                    phase: phase,
                    startTime: clampedTime,
                    endTime: draft.audioDuration
                )
            )
        }
        normalizePhases()
    }

    func removePhase(at index: Int) {
        guard draft.phases.indices.contains(index) else { return }
        draft.phases.remove(at: index)
        normalizePhases()
    }

    func clearAllPhases() {
        draft.phases.removeAll()
        syncSelectedPhase()
        rebuildTranscriptInsights()
    }

    func jumpToPhase(_ phase: LabeledFile.LabeledPhase) {
        seek(to: phase.startTime)
        let frac = phase.startTime / duration
        let newStart = max(0, min(1 - viewSpan, frac - viewSpan / 2))
        viewStart = newStart
        viewEnd = newStart + viewSpan
    }

    func movePhasePoint(id: PhasePoint.ID, to time: TimeInterval) {
        guard let index = draft.phases.firstIndex(where: { $0.id == id }) else { return }
        let maxStartTime = max(duration - 0.001, 0)
        draft.phases[index].startTime = max(0, min(maxStartTime, time))
        normalizePhases()
    }

    func updatePhasePoint(
        id: PhasePoint.ID,
        time: TimeInterval,
        phase: TrancePhase
    ) {
        guard let index = draft.phases.firstIndex(where: { $0.id == id }) else { return }
        let maxStartTime = max(duration - 0.001, 0)
        draft.phases[index].startTime = max(0, min(maxStartTime, time))
        draft.phases[index].phase = phase
        normalizePhases()
    }

    func setPhase(ofPointID id: PhasePoint.ID, to phase: TrancePhase) {
        guard let index = draft.phases.firstIndex(where: { $0.id == id }) else { return }
        draft.phases[index].phase = phase
        normalizePhases()
    }

    func deletePhasePoint(id: PhasePoint.ID) {
        guard let index = draft.phases.firstIndex(where: { $0.id == id }) else { return }
        draft.phases.remove(at: index)
        normalizePhases()
    }

    func selectPhase(id: UUID?) {
        selectedPhaseID = id
    }

    func loadTranscriptIfAvailable() async {
        guard transcription == nil else { return }

        let cacheURL = transcriptCacheURL()
        guard FileManager.default.fileExists(atPath: cacheURL.path()) else {
            transcriptStatusMessage = "Generate a transcript to inspect each labeled section."
            transcriptErrorMessage = nil
            rebuildTranscriptInsights()
            return
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cached = try decoder.decode(CachedTranscription.self, from: data)
            guard cached.audioSHA256 == draft.audioSHA256 else {
                transcriptStatusMessage = "Transcript cache is stale. Regenerate to refresh it."
                transcriptErrorMessage = nil
                rebuildTranscriptInsights()
                return
            }

            applyTranscription(cached.transcription, statusMessage: "Transcript loaded from cache.")
        } catch {
            transcriptStatusMessage = "Transcript cache could not be read."
            transcriptErrorMessage = error.localizedDescription
            rebuildTranscriptInsights()
        }
    }

    func generateTranscript() async {
        guard !isTranscriptLoading else { return }

        isTranscriptLoading = true
        transcriptErrorMessage = nil
        transcriptStatusMessage = "Preparing WhisperKit..."
        defer { isTranscriptLoading = false }

        do {
            let analyzer = makeTranscriptAnalyzer()
            try await analyzer.prepareModel()
            transcriptStatusMessage = "Transcribing \(draft.audioFilename)..."
            let audioFile = try makeAudioFileForTranscription()
            let result = try await analyzer.transcribe(audioFile: audioFile)
            try persistTranscript(result)
            applyTranscription(result, statusMessage: "Transcript ready.")
        } catch {
            transcriptErrorMessage = error.localizedDescription
            transcriptStatusMessage = "Transcript generation failed."
        }
    }

    func refreshAnalyzerDiagnostics() async {
        guard !isDiagnosticsLoading else { return }
        guard let transcription else {
            analyzerDiagnostics = nil
            diagnosticsStatusMessage = "Generate a transcript to compare analyzer predictions against your labels."
            diagnosticsErrorMessage = nil
            diagnosticsAreStale = true
            return
        }
        guard !draft.phases.isEmpty else {
            analyzerDiagnostics = nil
            diagnosticsStatusMessage = "Add labeled phases to compare predictions against the analyzer."
            diagnosticsErrorMessage = nil
            diagnosticsAreStale = true
            return
        }

        isDiagnosticsLoading = true
        diagnosticsErrorMessage = nil
        diagnosticsStatusMessage = "Running analyzer comparison..."
        defer { isDiagnosticsLoading = false }

        let keywordAnalyzer = HypnosisPhaseAnalyzer()
        let wordTimestamps = keywordAnalyzer.approximateWordTimestamps(from: transcription.segments)
        let keywordPhases = keywordAnalyzer.analyze(
            wordTimestamps: wordTimestamps,
            transcription: transcription,
            techniqueDetection: nil
        )
        let chunkedPhases = await ChunkedPhaseAnalyzer.analyze(
            wordTimestamps: wordTimestamps,
            duration: transcription.duration
        )
        let selection = keywordAnalyzer.selectPreferredPhases(
            keywordPhases: keywordPhases,
            chunkedPhases: chunkedPhases,
            transcription: transcription,
            techniqueDetection: nil
        )
        let techniqueDetection = TechniqueDetectionResult(techniques: [], markers: [])
        let predictedPhases = selection.phases

        analyzerDiagnostics = Self.buildAnalyzerDiagnostics(
            draft: draft,
            duration: duration,
            transcription: transcription,
            keywordPhases: keywordPhases,
            chunkedPhases: chunkedPhases,
            selectedPhases: predictedPhases,
            usedChunkedAnalyzer: selection.usedChunkedAnalyzer,
            techniqueDetection: techniqueDetection
        )
        diagnosticsStatusMessage = "Analyzer comparison ready."
        diagnosticsAreStale = false
    }

    func generatePhaseSuggestions() async {
        guard !isSuggestionLoading else { return }
        guard let transcription else {
            suggestedPhaseTimeline = nil
            suggestionStatusMessage = "Generate a transcript to build phase suggestions."
            suggestionErrorMessage = nil
            return
        }

        isSuggestionLoading = true
        suggestionErrorMessage = nil
        suggestionStatusMessage = "Building phrase-driven phase suggestions..."
        defer { isSuggestionLoading = false }

        let analyzer = HypnosisPhaseAnalyzer()
        let suggestionTimeline = analyzer.suggestPhaseTimeline(for: transcription)
        suggestedPhaseTimeline = suggestionTimeline

        if suggestionTimeline.segments.isEmpty {
            suggestionStatusMessage = "No strong phase proposal could be built from this transcript yet."
        } else {
            suggestionStatusMessage = "Suggested \(suggestionTimeline.segments.count) phase segments from phrase evidence."
        }
    }

    func applyPhaseSuggestions() {
        guard !suggestedPhaseSegments.isEmpty else {
            suggestionStatusMessage = "Generate suggestions before applying them."
            return
        }

        draft.phases = suggestedPhaseSegments.map { suggestion in
            LabeledFile.LabeledPhase(
                phase: suggestion.phase,
                startTime: suggestion.startTime,
                endTime: suggestion.endTime,
                notes: suggestion.rationale
            )
        }
        suggestionStatusMessage = "Applied \(draft.phases.count) suggested phase boundaries."
        normalizePhases()
    }

    func jumpToSuggestedPhase(_ segment: SuggestedPhaseSegment) {
        seek(to: segment.startTime)
        let frac = segment.startTime / duration
        let newStart = max(0, min(1 - viewSpan, frac - viewSpan / 2))
        viewStart = newStart
        viewEnd = newStart + viewSpan
    }

    func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            normalizePhases()
            var toSave = draft
            toSave.expectedContentType = .hypnosis
            toSave.labeledAt = Date()
            let saved = try await corpus.save(toSave)
            draft = saved
            syncSelectedPhase()
            rebuildTranscriptInsights()
            alertMessage = nil
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func niceInterval(for visibleDuration: TimeInterval) -> TimeInterval {
        let targets: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600]
        let raw = visibleDuration / 8
        return targets.first { $0 >= raw } ?? 3600
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):\(mins < 10 ? "0" : "")\(mins):\(secs < 10 ? "0" : "")\(secs)"
        }
        return "\(mins):\(secs < 10 ? "0" : "")\(secs)"
    }

    func phaseDepth(_ phase: TrancePhase) -> Double {
        switch phase {
        case .preTalk:      return 0.10
        case .induction:    return 0.28
        case .fractionation:return 0.48
        case .deepening:    return 0.72
        case .confusion:    return 0.82
        case .therapy:      return 0.88
        case .suggestions:  return 0.68
        case .eroticSuggestions: return 0.74
        case .brainwashing: return 0.79
        case .conditioning: return 0.42
        case .emergence:    return 0.15
        case .transitional: return 0.40
        }
    }

    func phaseColor(_ phase: TrancePhase) -> Color {
        switch phase {
        case .preTalk:      return .indigo
        case .induction:    return .blue
        case .fractionation:return .cyan
        case .deepening:    return .teal
        case .confusion:    return .mint
        case .therapy:      return .purple
        case .suggestions:  return .pink
        case .eroticSuggestions: return .red
        case .brainwashing: return .brown
        case .conditioning: return .orange
        case .emergence:    return .green
        case .transitional: return .gray
        }
    }

    func keyboardShortcutLabel(for index: Int) -> String? {
        guard (0..<9).contains(index) else { return nil }
        return String(index + 1)
    }

    private func normalizePhases() {
        guard !draft.phases.isEmpty else {
            syncSelectedPhase()
            analyzerDiagnostics = nil
            diagnosticsStatusMessage = nil
            diagnosticsErrorMessage = nil
            diagnosticsAreStale = true
            rebuildTranscriptInsights()
            return
        }

        draft.phases.sort { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.startTime < rhs.startTime
        }

        var normalized: [LabeledFile.LabeledPhase] = []
        for phase in draft.phases {
            let maxStartTime = max(duration - 0.001, 0)
            let clampedStart = max(0, min(maxStartTime, phase.startTime))
            if var previous = normalized.last, abs(previous.startTime - clampedStart) < 0.05 {
                previous.phase = phase.phase
                previous.notes = phase.notes
                normalized[normalized.count - 1] = previous
                continue
            }

            normalized.append(
                LabeledFile.LabeledPhase(
                    id: phase.id,
                    phase: phase.phase,
                    startTime: clampedStart,
                    endTime: duration,
                    notes: phase.notes
                )
            )
        }

        for index in normalized.indices {
            let nextStart = normalized.indices.contains(index + 1) ? normalized[index + 1].startTime : duration
            normalized[index].endTime = index + 1 < normalized.count
                ? max(normalized[index].startTime + 0.001, nextStart)
                : duration
        }

        draft.phases = normalized
        diagnosticsAreStale = true
        syncSelectedPhase()
        rebuildTranscriptInsights()
    }

    private func syncSelectedPhase() {
        guard !draft.phases.isEmpty else {
            selectedPhaseID = nil
            return
        }

        if let selectedPhaseID,
           draft.phases.contains(where: { $0.id == selectedPhaseID }) {
            return
        }

        selectedPhaseID = draft.phases.first?.id
    }

    private func suggestionConfidence(for segment: PhaseSegment) -> Double {
        let overlappingWindows = suggestedPhaseTimeline?.windows.filter {
            $0.startTime < segment.endTime && $0.endTime > segment.startTime
        } ?? []
        guard !overlappingWindows.isEmpty else { return 0 }
        let total = overlappingWindows.reduce(0.0) { $0 + $1.confidence }
        return total / Double(overlappingWindows.count)
    }

    private func trancePhase(for phase: HypnosisMetadata.Phase) -> TrancePhase? {
        switch phase {
        case .preTalk: return .preTalk
        case .induction: return .induction
        case .fractionation: return .fractionation
        case .deepening: return .deepening
        case .confusion: return .confusion
        case .therapy: return .therapy
        case .suggestions: return .suggestions
        case .eroticSuggestions: return .eroticSuggestions
        case .brainwashing: return .brainwashing
        case .conditioning: return .conditioning
        case .emergence: return .emergence
        case .transitional: return .transitional
        }
    }

    private func makeTranscriptAnalyzer() -> AudioAnalyzer {
        if let transcriptAnalyzer {
            return transcriptAnalyzer
        }
        let analyzer = AudioAnalyzer()
        transcriptAnalyzer = analyzer
        return analyzer
    }

    private func transcriptCacheURL() -> URL {
        corpus.analyzerDatasetDirectory
            .appending(path: "cache", directoryHint: .isDirectory)
            .appending(path: "transcripts", directoryHint: .isDirectory)
            .appending(path: "\(draft.audioSHA256).json")
    }

    private func makeAudioFileForTranscription() throws -> AudioFile {
        let url = corpus.audioURL(for: draft)
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        return AudioFile(
            id: draft.id,
            filename: url.standardizedFileURL.path(),
            duration: draft.audioDuration,
            fileSize: Int64(resourceValues?.fileSize ?? 0),
            createdDate: resourceValues?.creationDate ?? draft.labeledAt
        )
    }

    private func persistTranscript(_ result: AudioTranscriptionResult) throws {
        let cacheURL = transcriptCacheURL()
        let cacheDirectory = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let payload = CachedTranscription(
            schemaVersion: 1,
            cachedAt: Date(),
            exampleID: draft.id,
            audioSHA256: draft.audioSHA256,
            transcription: result
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: cacheURL, options: .atomic)
    }

    private func applyTranscription(
        _ result: AudioTranscriptionResult,
        statusMessage: String
    ) {
        transcription = result
        transcriptErrorMessage = nil
        transcriptStatusMessage = statusMessage
        diagnosticsAreStale = true
        diagnosticsErrorMessage = nil
        diagnosticsStatusMessage = canRunAnalyzerDiagnostics
            ? "Refresh analyzer diagnostics to compare predictions against your labels."
            : "Add labeled phases to compare analyzer predictions."
        suggestedPhaseTimeline = nil
        suggestionErrorMessage = nil
        suggestionStatusMessage = "Use the phrase library to propose a phase timeline from this transcript."
        rebuildTranscriptInsights()
    }

    private func rebuildTranscriptInsights() {
        guard let transcription else {
            phaseTranscriptInsights = [:]
            fullTranscriptInsight = nil
            return
        }

        guard let rawFullInsight = Self.makeTranscriptInsight(
            id: draft.id,
            phase: nil,
            startTime: 0,
            endTime: duration,
            transcription: transcription
        ) else {
            fullTranscriptInsight = nil
            phaseTranscriptInsights = [:]
            return
        }

        let rawPhaseInsights: [UUID: PhaseTranscriptInsight] = Dictionary(
            uniqueKeysWithValues: draft.phases.compactMap { phase in
                guard let insight = Self.makeTranscriptInsight(
                    id: phase.id,
                    phase: phase.phase,
                    startTime: phase.startTime,
                    endTime: phase.endTime,
                    transcription: transcription
                ) else {
                    return nil
                }
                return (phase.id, insight)
            }
        )

        fullTranscriptInsight = Self.normalizeTranscriptInsight(
            rawFullInsight,
            overall: rawFullInsight,
            distinctiveBaseline: rawFullInsight,
            allowsDistinctiveWords: false
        )
        phaseTranscriptInsights = rawPhaseInsights.mapValues { insight in
            Self.normalizeTranscriptInsight(
                insight,
                overall: rawFullInsight,
                distinctiveBaseline: rawFullInsight
            )
        }
    }

    nonisolated static func makeTranscriptInsight(
        id: UUID,
        phase: TrancePhase?,
        startTime: TimeInterval,
        endTime: TimeInterval,
        transcription: AudioTranscriptionResult
    ) -> PhaseTranscriptInsight? {
        let clippedStart = max(0, min(startTime, transcription.duration))
        let clippedEnd = max(clippedStart, min(endTime, transcription.duration))
        let sectionDuration = max(0, clippedEnd - clippedStart)
        guard sectionDuration > 0 else { return nil }

        let overlappingSegments = transcription.segments.compactMap { segment -> (AudioTranscriptionSegment, ClosedRange<TimeInterval>)? in
            let segmentStart = segment.timestamp
            let segmentEnd = segment.timestamp + max(segment.duration, 0)
            let overlapStart = max(clippedStart, segmentStart)
            let overlapEnd = min(clippedEnd, segmentEnd)
            guard overlapEnd > overlapStart else { return nil }
            return (segment, overlapStart...overlapEnd)
        }

        let excerpts = overlappingSegments.compactMap { segment, overlap -> TranscriptExcerpt? in
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return TranscriptExcerpt(
                id: segment.id,
                startTime: overlap.lowerBound,
                endTime: overlap.upperBound,
                text: trimmed
            )
        }

        let transcriptText = excerpts.map(\.text).joined(separator: " ")
        let allWords = tokenizeWords(in: transcriptText)
        let keywordCounts = keywordFrequency(in: transcriptText)
        let topWords = keywordCounts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .prefix(20)
            .map { TranscriptKeyword(word: $0.key, count: $0.value, relativeWeight: nil) }

        let mergedIntervals = mergeIntervals(overlappingSegments.map(\.1))
        let spokenDuration = mergedIntervals.reduce(0.0) { partial, interval in
            partial + (interval.upperBound - interval.lowerBound)
        }

        var longestPause = clippedStart > 0 ? 0.0 : 0.0
        if mergedIntervals.isEmpty {
            longestPause = sectionDuration
        } else {
            longestPause = max(0, mergedIntervals[0].lowerBound - clippedStart)
            for index in 1..<mergedIntervals.count {
                longestPause = max(
                    longestPause,
                    mergedIntervals[index].lowerBound - mergedIntervals[index - 1].upperBound
                )
            }
            longestPause = max(longestPause, clippedEnd - mergedIntervals[mergedIntervals.count - 1].upperBound)
        }

        let averageSegmentDuration = excerpts.isEmpty
            ? 0
            : excerpts.map { $0.endTime - $0.startTime }.reduce(0, +) / Double(excerpts.count)

        let uniqueWordCount = Set(allWords).count
        let lexicalDiversity = allWords.isEmpty ? 0 : Double(uniqueWordCount) / Double(allWords.count)
        let repetitionDensity = allWords.isEmpty
            ? 0
            : Double(repeatedPhraseOccurrences(in: allWords, phraseLength: 3)) / Double(allWords.count)

        return PhaseTranscriptInsight(
            id: id,
            phase: phase,
            startTime: clippedStart,
            endTime: clippedEnd,
            duration: sectionDuration,
            transcriptText: transcriptText,
            excerpts: excerpts,
            wordCount: allWords.count,
            uniqueWordCount: uniqueWordCount,
            wordsPerMinute: sectionDuration > 0 ? (Double(allWords.count) / sectionDuration) * 60 : 0,
            normalizedWordsPerMinute: 1,
            speechCoverage: sectionDuration > 0 ? min(spokenDuration / sectionDuration, 1) : 0,
            normalizedSpeechCoverage: 1,
            longestPause: max(longestPause, 0),
            averageSegmentDuration: averageSegmentDuration,
            lexicalDiversity: lexicalDiversity,
            normalizedLexicalDiversity: 1,
            repetitionDensity: repetitionDensity,
            normalizedRepetitionDensity: 1,
            topWords: topWords.map { TranscriptKeyword(word: $0.word, count: $0.count, relativeWeight: nil) },
            topDistinctiveWords: []
        )
    }

    nonisolated private static func normalizeTranscriptInsight(
        _ insight: PhaseTranscriptInsight,
        overall: PhaseTranscriptInsight,
        distinctiveBaseline: PhaseTranscriptInsight,
        allowsDistinctiveWords: Bool = true
    ) -> PhaseTranscriptInsight {
        let sectionCounts = keywordFrequency(in: insight.transcriptText)
        let overallCounts = keywordFrequency(in: distinctiveBaseline.transcriptText)
        let totalSectionWords = max(sectionCounts.values.reduce(0, +), 1)
        let totalOverallWords = max(overallCounts.values.reduce(0, +), 1)

        let topDistinctiveWords: [TranscriptKeyword]
        if allowsDistinctiveWords {
            topDistinctiveWords = sectionCounts.compactMap { word, count in
                let sectionShare = Double(count) / Double(totalSectionWords)
                let overallShare = Double(overallCounts[word, default: 0]) / Double(totalOverallWords)
                let lift = overallShare > 0 ? sectionShare / overallShare : sectionShare * Double(totalOverallWords)
                guard lift > 1.1 else { return nil }
                return TranscriptKeyword(word: word, count: count, relativeWeight: lift)
            }
            .sorted {
                let lhsWeight = $0.relativeWeight ?? 0
                let rhsWeight = $1.relativeWeight ?? 0
                if lhsWeight == rhsWeight {
                    if $0.count == $1.count {
                        return $0.word < $1.word
                    }
                    return $0.count > $1.count
                }
                return lhsWeight > rhsWeight
            }
            .prefix(20)
            .map { $0 }
        } else {
            topDistinctiveWords = []
        }

        return PhaseTranscriptInsight(
            id: insight.id,
            phase: insight.phase,
            startTime: insight.startTime,
            endTime: insight.endTime,
            duration: insight.duration,
            transcriptText: insight.transcriptText,
            excerpts: insight.excerpts,
            wordCount: insight.wordCount,
            uniqueWordCount: insight.uniqueWordCount,
            wordsPerMinute: insight.wordsPerMinute,
            normalizedWordsPerMinute: normalizedRatio(insight.wordsPerMinute, baseline: overall.wordsPerMinute),
            speechCoverage: insight.speechCoverage,
            normalizedSpeechCoverage: normalizedRatio(insight.speechCoverage, baseline: overall.speechCoverage),
            longestPause: insight.longestPause,
            averageSegmentDuration: insight.averageSegmentDuration,
            lexicalDiversity: insight.lexicalDiversity,
            normalizedLexicalDiversity: normalizedRatio(insight.lexicalDiversity, baseline: overall.lexicalDiversity),
            repetitionDensity: insight.repetitionDensity,
            normalizedRepetitionDensity: normalizedRatio(insight.repetitionDensity, baseline: overall.repetitionDensity),
            topWords: insight.topWords,
            topDistinctiveWords: topDistinctiveWords
        )
    }

    nonisolated private static func buildAnalyzerDiagnostics(
        draft: LabeledFile,
        duration: TimeInterval,
        transcription: AudioTranscriptionResult,
        keywordPhases: [PhaseSegment],
        chunkedPhases: [PhaseSegment]?,
        selectedPhases: [PhaseSegment],
        usedChunkedAnalyzer: Bool,
        techniqueDetection: TechniqueDetectionResult
    ) -> AnalyzerDiagnostics {
        let engine = diagnosticsEngine(
            selectedPhases: selectedPhases,
            keywordPhases: keywordPhases,
            chunkedPhases: chunkedPhases,
            usedChunkedAnalyzer: usedChunkedAnalyzer
        )

        let comparisons = buildPhaseComparisons(
            labeledPhases: draft.phases,
            predictedPhases: selectedPhases,
            duration: duration,
            transcription: transcription
        )

        let boundaryErrors = comparisons.compactMap { $0.averageBoundaryError }
        let averageBoundaryError = boundaryErrors.isEmpty
            ? nil
            : boundaryErrors.reduce(0, +) / Double(boundaryErrors.count)

        return AnalyzerDiagnostics(
            engine: engine,
            predictedPhases: selectedPhases,
            comparisons: comparisons,
            techniqueMarkers: techniqueDetection.markers.sorted { $0.timestamp < $1.timestamp },
            averageBoundaryError: averageBoundaryError
        )
    }

    nonisolated private static func diagnosticsEngine(
        selectedPhases: [PhaseSegment],
        keywordPhases: [PhaseSegment],
        chunkedPhases: [PhaseSegment]?,
        usedChunkedAnalyzer: Bool
    ) -> DiagnosticsEngine {
        guard let chunkedPhases else {
            return .keyword
        }

        if segmentsEquivalent(selectedPhases, keywordPhases) {
            return .keyword
        }
        if segmentsEquivalent(selectedPhases, chunkedPhases) && usedChunkedAnalyzer {
            return .chunked
        }
        return .ensemble
    }

    nonisolated private static func segmentsEquivalent(
        _ lhs: [PhaseSegment],
        _ rhs: [PhaseSegment],
        tolerance: TimeInterval = 1.5
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.phase == right.phase
                && abs(left.startTime - right.startTime) <= tolerance
                && abs(left.endTime - right.endTime) <= tolerance
        }
    }

    nonisolated private static func buildPhaseComparisons(
        labeledPhases: [LabeledFile.LabeledPhase],
        predictedPhases: [PhaseSegment],
        duration: TimeInterval,
        transcription: AudioTranscriptionResult
    ) -> [AnalyzerPhaseComparison] {
        guard let overallInsight = makeTranscriptInsight(
            id: UUID(),
            phase: nil,
            startTime: 0,
            endTime: duration,
            transcription: transcription
        ) else {
            return labeledPhases.map { phase in
                AnalyzerPhaseComparison(
                    id: phase.id,
                    labeledPhaseID: phase.id,
                    labeledPhase: phase.phase,
                    labeledStartTime: phase.startTime,
                    labeledEndTime: phase.endTime,
                    predictedPhase: nil,
                    predictedStartTime: nil,
                    predictedEndTime: nil,
                    overlapFraction: 0,
                    startDelta: nil,
                    endDelta: nil,
                    predictedConfidence: nil,
                    predictedRationale: nil,
                    evidenceWords: []
                )
            }
        }

        return labeledPhases.map { labeled in
            let predicted = bestPredictedPhase(for: labeled, in: predictedPhases)
            let overlap = predicted.map { overlapFraction(labeled: labeled, predicted: $0) } ?? 0
            let evidenceWords = predicted.flatMap {
                predictedEvidenceWords(
                    for: $0,
                    overallInsight: overallInsight,
                    transcription: transcription
                )
            } ?? []

            return AnalyzerPhaseComparison(
                id: labeled.id,
                labeledPhaseID: labeled.id,
                labeledPhase: labeled.phase,
                labeledStartTime: labeled.startTime,
                labeledEndTime: labeled.endTime,
                predictedPhase: predicted?.phase,
                predictedStartTime: predicted?.startTime,
                predictedEndTime: predicted?.endTime,
                overlapFraction: overlap,
                startDelta: predicted.map { $0.startTime - labeled.startTime },
                endDelta: predicted.map { $0.endTime - labeled.endTime },
                predictedConfidence: predicted?.confidenceLevel,
                predictedRationale: predicted?.confidenceRationale,
                evidenceWords: evidenceWords
            )
        }
    }

    nonisolated private static func bestPredictedPhase(
        for labeled: LabeledFile.LabeledPhase,
        in predictedPhases: [PhaseSegment]
    ) -> PhaseSegment? {
        predictedPhases.max { lhs, rhs in
            let lhsOverlap = overlapDuration(labeled, lhs)
            let rhsOverlap = overlapDuration(labeled, rhs)
            if abs(lhsOverlap - rhsOverlap) > 0.001 {
                return lhsOverlap < rhsOverlap
            }

            let midpoint = (labeled.startTime + labeled.endTime) / 2.0
            let lhsDistance = distanceFromMidpoint(midpoint, to: lhs)
            let rhsDistance = distanceFromMidpoint(midpoint, to: rhs)
            return lhsDistance > rhsDistance
        }
    }

    nonisolated private static func overlapFraction(
        labeled: LabeledFile.LabeledPhase,
        predicted: PhaseSegment
    ) -> Double {
        let overlap = overlapDuration(labeled, predicted)
        let labeledDuration = max(labeled.endTime - labeled.startTime, 0.001)
        return min(max(overlap / labeledDuration, 0), 1)
    }

    nonisolated private static func overlapDuration(
        _ labeled: LabeledFile.LabeledPhase,
        _ predicted: PhaseSegment
    ) -> TimeInterval {
        max(0, min(labeled.endTime, predicted.endTime) - max(labeled.startTime, predicted.startTime))
    }

    nonisolated private static func distanceFromMidpoint(
        _ midpoint: TimeInterval,
        to segment: PhaseSegment
    ) -> TimeInterval {
        if midpoint < segment.startTime { return segment.startTime - midpoint }
        if midpoint > segment.endTime { return midpoint - segment.endTime }
        return 0
    }

    nonisolated private static func predictedEvidenceWords(
        for predicted: PhaseSegment,
        overallInsight: PhaseTranscriptInsight,
        transcription: AudioTranscriptionResult
    ) -> [TranscriptKeyword] {
        guard let rawInsight = makeTranscriptInsight(
            id: predicted.id,
            phase: predicted.phase,
            startTime: predicted.startTime,
            endTime: predicted.endTime,
            transcription: transcription
        ) else {
            return []
        }

        let normalizedInsight = normalizeTranscriptInsight(
            rawInsight,
            overall: overallInsight,
            distinctiveBaseline: overallInsight
        )

        let prioritized = normalizedInsight.topDistinctiveWords.isEmpty
            ? normalizedInsight.topWords
            : normalizedInsight.topDistinctiveWords
        return Array(prioritized.prefix(5))
    }

    nonisolated private static func mergeIntervals(
        _ intervals: [ClosedRange<TimeInterval>]
    ) -> [ClosedRange<TimeInterval>] {
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        guard var current = sorted.first else { return [] }

        var merged: [ClosedRange<TimeInterval>] = []
        for interval in sorted.dropFirst() {
            if interval.lowerBound <= current.upperBound {
                current = current.lowerBound...max(current.upperBound, interval.upperBound)
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    nonisolated private static func tokenizeWords(in text: String) -> [String] {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        let normalized = String(
            text
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .unicodeScalars
                .map { allowedCharacters.contains($0) ? Character($0) : " " }
        )

        return normalized
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: "'")).lowercased()
            }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func keywordFrequency(in text: String) -> [String: Int] {
        tokenizeWords(in: text).reduce(into: [:]) { counts, word in
            guard !transcriptStopWords.contains(word) else { return }
            guard word.rangeOfCharacter(from: .letters) != nil else { return }
            counts[word, default: 0] += 1
        }
    }

    nonisolated private static func repeatedPhraseOccurrences(
        in words: [String],
        phraseLength: Int
    ) -> Int {
        guard phraseLength > 0, words.count >= phraseLength else { return 0 }
        var phrases: [String: Int] = [:]
        for index in 0...(words.count - phraseLength) {
            let phrase = words[index..<(index + phraseLength)].joined(separator: " ")
            phrases[phrase, default: 0] += 1
        }
        return phrases.values.reduce(0) { partial, count in
            partial + max(0, count - 1)
        }
    }

    nonisolated private static func normalizedRatio(_ value: Double, baseline: Double) -> Double {
        let safeBaseline = max(baseline, 0.0001)
        return value / safeBaseline
    }

    nonisolated private static let transcriptStopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "for",
        "from", "had", "has", "have", "he", "her", "hers", "him", "his", "i",
        "if", "in", "into", "is", "it", "its", "just", "let", "me", "my",
        "now", "of", "on", "or", "our", "ours", "she", "so", "that", "the",
        "their", "theirs", "them", "there", "these", "they", "this", "those",
        "to", "up", "was", "we", "were", "with", "you", "your", "yours"
    ]
}
