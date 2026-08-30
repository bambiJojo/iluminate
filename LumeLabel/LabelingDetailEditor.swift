//
//  LabelingDetailEditor.swift
//  LumeLabel
//
//  Main-actor editor model for the macOS labeling workflow.
//

import SwiftUI
import Observation
import AVFoundation

/// Owns `AVAudioPlayer` on a non-UI actor. Constructing a player for a long MP3
/// performs synchronous file reads, so keeping the non-Sendable player here
/// preserves its reliable playback clock without blocking the main actor.
actor AudioPlaybackSession {
    private var player: AVAudioPlayer?

    var isPrepared: Bool {
        player != nil
    }

    func prepare(url: URL) throws {
        try Task.checkCancellation()
        let preparedPlayer = try AVAudioPlayer(contentsOf: url)
        preparedPlayer.prepareToPlay()
        try Task.checkCancellation()
        player?.stop()
        player = preparedPlayer
    }

    func play() -> Bool {
        player?.play() ?? false
    }

    func pause() {
        player?.pause()
    }

    func seek(to time: TimeInterval) {
        guard !Task.isCancelled else { return }
        player?.currentTime = time
    }

    func currentTime() -> TimeInterval {
        player?.currentTime ?? 0
    }

    func cleanup() {
        player?.stop()
        player = nil
    }
}

@MainActor
@Observable
final class LabelingDetailEditor {
    enum LabelingPass: Sendable {
        case boundaries
        case phaseNames
    }

    enum SaveState: Equatable, Sendable {
        case saved
        case unsaved
        case saving
        case draftSaved
        case failed
    }

    struct PhasePoint: Identifiable, Sendable {
        let id: UUID
        let phase: TrancePhase?
        let time: TimeInterval
        let isInitial: Bool
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
        nonisolated var averageBoundaryError: TimeInterval? {
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
        let id: String
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
    var transitionLabeling: TransitionLabelingDraft
    var labelingPass: LabelingPass = .boundaries
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var isAudioPreparing = false
    var viewStart: Double = 0
    var viewEnd: Double = 1
    var lastMagnification: Double = 1
    var draggingPointID: PhasePoint.ID?
    var alertMessage: String?
    var isSaving = false
    var saveState: SaveState = .saved
    var saveFailureMessage: String?
    var selectedPhaseID: UUID?
    var transcription: AudioTranscriptionResult?
    var transcriptStatusMessage: String?
    var transcriptErrorMessage: String?
    var isTranscriptLoading = false
    var phaseTranscriptInsights: [UUID: PhaseTranscriptInsight] = [:]
    var fullTranscriptInsight: PhaseTranscriptInsight?
    var analyzerDiagnostics: AnalyzerDiagnostics?
    var isDiagnosticsLoading = false
    var diagnosticsProgress: Double?
    var diagnosticsStatusMessage: String?
    var diagnosticsErrorMessage: String?
    var diagnosticsAreStale = true
    var suggestedPhaseTimeline: HypnosisPhaseAnalyzer.PhaseSuggestionTimeline?
    var isSuggestionLoading = false
    var suggestionStatusMessage: String?
    var suggestionErrorMessage: String?
    var semanticPhaseAnalysis: SemanticPhaseAnalyzer.Analysis?
    var isSemanticPhaseAnalysisRunning = false
    var semanticPhaseStatusMessage: String?
    var semanticPhaseErrorMessage: String?
    var backgroundToneAnalysis: BackgroundToneAnalysis?
    var isBackgroundToneAnalysisRunning = false
    var backgroundToneStatusMessage: String?
    var backgroundToneErrorMessage: String?
    var candidateReviewRecords: [TransitionCandidateReview.Record] = []
    var selectedTransitionCandidateID: TransitionCandidateReview.ID?
    private(set) var isAnalyzerReviewMode = false
    private(set) var analyzerReviewBaseline: TransitionCandidateReview.BlindBaseline?

    private let corpus: TrainingCorpusManager
    private var playbackSession: AudioPlaybackSession?
    private var preparationTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?
    private var seekTask: Task<Void, Never>?
    private var playbackControlTask: Task<Void, Never>?
    private var semanticPhaseAnalysisTask: Task<SemanticPhaseAnalyzer.Analysis, Error>?
    private var semanticPhaseAnalysisRequestID: UUID?
    private var backgroundToneAnalysisTask: Task<BackgroundToneAnalysis, Error>?
    private var backgroundToneAnalysisRequestID: UUID?
    private var diagnosticsTask: Task<AnalyzerDiagnostics?, Never>?
    private var diagnosticsRequestID: UUID?
    private var autosaveTask: Task<Void, Never>?
    private var analyzerReviewPersistenceTask: Task<Void, Never>?
    private var pendingWork: LabelingWorkInProgress?
    private var savingRevision: UUID?
    private var transcriptAnalyzer: AudioAnalyzer?
    private let recoveryStore: LabelingDraftRecoveryStore
    private let recoveryDirectory: URL

    init(
        file: LabeledFile,
        corpus: TrainingCorpusManager,
        recoveryStore: LabelingDraftRecoveryStore = .shared
    ) {
        self.fileID = file.id
        self.draft = file
        self.transitionLabeling = TransitionLabelingDraft(
            duration: file.audioDuration,
            phases: file.phases
        )
        self.corpus = corpus
        self.recoveryStore = recoveryStore
        self.recoveryDirectory = corpus.analyzerDatasetDirectory
            .deletingLastPathComponent()
            .appending(path: "LabelingDrafts")
        self.draft.expectedContentType = .hypnosis
        syncSelectedPhase()
    }

    var duration: TimeInterval { max(draft.audioDuration, 1) }
    var hasAudioPlaybackSession: Bool { playbackSession != nil }
    var viewSpan: Double { max(0.001, viewEnd - viewStart) }
    var labelingSegments: [TransitionLabelingDraft.Segment] { transitionLabeling.segments }
    var boundaryCount: Int { transitionLabeling.boundaryCount }
    var unassignedSegmentCount: Int { transitionLabeling.unassignedCount }
    var isReadyToSave: Bool { transitionLabeling.isReadyToSave }
    var canEnterAnalyzerReview: Bool {
        saveState == .saved
            && transitionLabeling.isReadyToSave
            && draft.phases.isEmpty == false
    }
    var labelValidationMessage: String? { transitionLabeling.readinessIssue?.message }
    var phasePoints: [PhasePoint] {
        transitionLabeling.segments.enumerated().map { index, segment in
            PhasePoint(
                id: segment.id,
                phase: segment.phase,
                time: segment.startTime,
                isInitial: index == 0
            )
        }
    }
    var activeTranscriptInsight: PhaseTranscriptInsight? {
        if let selectedPhaseID,
           let insight = phaseTranscriptInsights[selectedPhaseID] {
            return insight
        }
        return fullTranscriptInsight
    }
    var selectedSegment: TransitionLabelingDraft.Segment? {
        guard let selectedPhaseID else { return nil }
        return transitionLabeling.segments.first { $0.id == selectedPhaseID }
    }
    var selectedPhaseComparison: AnalyzerPhaseComparison? {
        guard let selectedPhaseID else { return nil }
        return analyzerDiagnostics?.comparisons.first { $0.labeledPhaseID == selectedPhaseID }
    }
    var hasTranscript: Bool { transcription != nil }
    var canRunAnalyzerDiagnostics: Bool {
        transcription != nil && transitionLabeling.isReadyToSave
    }
    var canSuggestPhases: Bool { transcription != nil }
    var backgroundToneCandidates: [BackgroundToneCandidate] {
        backgroundToneAnalysis?.candidates ?? []
    }
    var transitionCandidates: [TransitionCandidateReview.Candidate] {
        guard isAnalyzerReviewMode else { return [] }
        let toneCandidates = backgroundToneCandidates.map { candidate in
            TransitionCandidateReview.Candidate(
                source: .backgroundTone,
                time: candidate.time,
                confidence: candidate.strength
            )
        }
        let semanticCandidates = (semanticPhaseAnalysis?.segments.dropFirst() ?? []).map { segment in
            TransitionCandidateReview.Candidate(
                source: .semantic,
                time: segment.startTime,
                confidence: segment.confidence,
                suggestedPhase: segment.phase,
                evidence: segment.matchedExampleText
            )
        }
        return (toneCandidates + semanticCandidates).sorted {
            if abs($0.time - $1.time) > 0.001 {
                return $0.time < $1.time
            }
            return $0.source.rawValue < $1.source.rawValue
        }
    }
    var pendingTransitionCandidates: [TransitionCandidateReview.Candidate] {
        transitionCandidates.filter { candidateDecision(for: $0.id) == nil }
    }
    var selectedTransitionCandidate: TransitionCandidateReview.Candidate? {
        guard let selectedTransitionCandidateID else { return nil }
        return transitionCandidates.first { $0.id == selectedTransitionCandidateID }
    }
    var acceptedCandidateCount: Int {
        transitionCandidates.count { candidateDecision(for: $0.id) == .accepted }
    }
    var dismissedCandidateCount: Int {
        transitionCandidates.count { candidateDecision(for: $0.id) == .dismissed }
    }
    var suggestedPhaseSegments: [SuggestedPhaseSegment] {
        (suggestedPhaseTimeline?.segments ?? []).compactMap { segment in
            guard let trancePhase = trancePhase(for: segment.phase) else { return nil }
            return SuggestedPhaseSegment(
                id: [
                    segment.id.uuidString,
                    trancePhase.rawValue,
                    String(segment.startTime.bitPattern, radix: 16),
                    String(segment.endTime.bitPattern, radix: 16)
                ].joined(separator: ":"),
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
        let url = corpus.audioURL(for: draft)
        let session = AudioPlaybackSession()
        playbackSession = session
        isAudioPreparing = true

        preparationTask?.cancel()
        preparationTask = Task { @MainActor [weak self, session] in
            defer {
                if let self, self.playbackSession === session {
                    self.isAudioPreparing = false
                    self.preparationTask = nil
                }
            }

            do {
                try await session.prepare(url: url)
            } catch is CancellationError {
                await session.cleanup()
            } catch {
                guard let self, self.playbackSession === session else { return }
                self.alertMessage = "Could not prepare audio: \(error.localizedDescription)"
            }
        }
    }

    func cleanup() {
        autosaveTask?.cancel()
        autosaveTask = nil
        analyzerReviewPersistenceTask?.cancel()
        analyzerReviewPersistenceTask = nil
        if analyzerReviewBaseline != nil || candidateReviewRecords.isEmpty == false {
            let reviewWork = makeWorkInProgress()
            recoveryStore.stage(reviewWork, in: recoveryDirectory)
            Task { [recoveryStore, recoveryDirectory] in
                try? await recoveryStore.persist(reviewWork, in: recoveryDirectory)
            }
        }
        if let pendingWork, saveState == .unsaved || saveState == .saving {
            recoveryStore.stage(pendingWork, in: recoveryDirectory)
            Task { [recoveryStore, recoveryDirectory] in
                try? await recoveryStore.persist(pendingWork, in: recoveryDirectory)
            }
        }
        preparationTask?.cancel()
        preparationTask = nil
        positionTask?.cancel()
        positionTask = nil
        seekTask?.cancel()
        seekTask = nil
        playbackControlTask?.cancel()
        playbackControlTask = nil
        semanticPhaseAnalysisTask?.cancel()
        semanticPhaseAnalysisTask = nil
        semanticPhaseAnalysisRequestID = nil
        isSemanticPhaseAnalysisRunning = false
        backgroundToneAnalysisTask?.cancel()
        backgroundToneAnalysisTask = nil
        backgroundToneAnalysisRequestID = nil
        isBackgroundToneAnalysisRunning = false
        cancelAnalyzerDiagnostics(showStatus: false)
        let session = playbackSession
        playbackSession = nil
        Task { await session?.cleanup() }
        isPlaying = false
        isAudioPreparing = false
        if let transcriptAnalyzer {
            Task { await transcriptAnalyzer.cancelTranscription() }
        }
    }

    func restoreWorkInProgressIfAvailable() async {
        do {
            guard let recovered = try await recoveryStore.recover(
                fileID: fileID,
                from: recoveryDirectory
            ) else {
                return
            }

            // Review decisions are useful measurement data even when the
            // underlying phase timeline is already fully saved.
            candidateReviewRecords = recovered.candidateReviews ?? []
            analyzerReviewBaseline = recovered.analyzerReviewBaseline
            isAnalyzerReviewMode = analyzerReviewBaseline != nil

            guard recovered.canRestore(over: draft) else { return }

            draft = recovered.fileMetadata.mergedForSave(over: draft)
            draft.expectedContentType = .hypnosis
            transitionLabeling = recovered.labeling
            labelingPass = transitionLabeling.unassignedCount == transitionLabeling.segments.count
                ? .boundaries
                : .phaseNames
            pendingWork = recovered
            saveState = .draftSaved
            saveFailureMessage = nil
            syncSelectedPhase()
            rebuildTranscriptInsights()
            scheduleAutosave(for: recovered)
        } catch {
            saveState = .failed
            saveFailureMessage = "Could not recover the saved draft: \(error.localizedDescription)"
        }
    }

    func clearAlert() {
        alertMessage = nil
    }

    @discardableResult
    func enterAnalyzerReview() -> Bool {
        guard canEnterAnalyzerReview else { return false }
        if analyzerReviewBaseline == nil {
            analyzerReviewBaseline = TransitionCandidateReview.BlindBaseline(
                lockedAt: Date(),
                sourceLabeledAt: draft.labeledAt,
                phases: draft.phases
            )
        }
        isAnalyzerReviewMode = true
        persistAnalyzerReviewState()
        return true
    }

    func togglePlayback() {
        guard let session = playbackSession else {
            alertMessage = "Audio player is unavailable for this file."
            return
        }

        if isPlaying {
            positionTask?.cancel()
            positionTask = nil
            isPlaying = false
            playbackControlTask?.cancel()
            playbackControlTask = Task {
                await session.pause()
            }
            return
        }

        isPlaying = true
        let preparationTask = preparationTask
        let seekTask = seekTask
        let previousControlTask = playbackControlTask
        positionTask = Task { @MainActor [weak self] in
            await preparationTask?.value
            await seekTask?.value
            await previousControlTask?.value

            guard let self,
                  !Task.isCancelled,
                  self.isPlaying,
                  self.playbackSession === session,
                  await session.isPrepared else {
                if !Task.isCancelled {
                    self?.isPlaying = false
                }
                return
            }

            guard await session.play() else {
                self.isPlaying = false
                self.alertMessage = "Audio playback could not start."
                return
            }

            while !Task.isCancelled {
                let observedTime = await session.currentTime()
                if observedTime.isFinite {
                    self.currentTime = observedTime
                }
                if self.currentTime >= self.duration {
                    self.isPlaying = false
                    break
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(duration, time))
        currentTime = clamped
        guard let session = playbackSession else { return }
        seekTask?.cancel()
        seekTask = Task {
            await session.seek(to: clamped)
        }
    }

    func seekRelative(_ delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func analyzeBackgroundTones(
        configuration: BackgroundToneAnalyzer.Configuration = .labelingExperiment
    ) async {
        backgroundToneAnalysisTask?.cancel()
        let requestID = UUID()
        backgroundToneAnalysisRequestID = requestID
        isBackgroundToneAnalysisRunning = true
        backgroundToneErrorMessage = nil
        backgroundToneStatusMessage = "Listening for background changes…"

        let audioURL = corpus.audioURL(for: draft)
        let analysisTask = Task.detached(priority: .userInitiated) {
            try BackgroundToneAnalyzer.analyze(
                audioURL: audioURL,
                configuration: configuration
            )
        }
        backgroundToneAnalysisTask = analysisTask

        do {
            let analysis = try await analysisTask.value
            guard backgroundToneAnalysisRequestID == requestID else { return }
            backgroundToneAnalysis = analysis
            let count = analysis.candidates.count
            if count == 0 {
                backgroundToneStatusMessage = "No strong background-tone changes found."
            } else {
                let noun = count == 1 ? "candidate" : "candidates"
                backgroundToneStatusMessage = "Found \(count) \(noun) from the \(analysis.source.displayName)."
            }
        } catch is CancellationError {
            guard backgroundToneAnalysisRequestID == requestID else { return }
            backgroundToneStatusMessage = nil
        } catch {
            guard backgroundToneAnalysisRequestID == requestID else { return }
            backgroundToneStatusMessage = "Background-tone analysis failed."
            backgroundToneErrorMessage = error.localizedDescription
        }

        if backgroundToneAnalysisRequestID == requestID {
            backgroundToneAnalysisTask = nil
            backgroundToneAnalysisRequestID = nil
            isBackgroundToneAnalysisRunning = false
        }
    }

    func cancelBackgroundToneAnalysis() {
        backgroundToneAnalysisTask?.cancel()
        backgroundToneAnalysisTask = nil
        backgroundToneAnalysisRequestID = nil
        isBackgroundToneAnalysisRunning = false
        backgroundToneStatusMessage = nil
    }

    func candidateDecision(
        for id: TransitionCandidateReview.ID
    ) -> TransitionCandidateReview.Decision? {
        candidateReviewRecords.last { $0.candidateID == id }?.decision
    }

    func jumpToTransitionCandidate(_ candidate: TransitionCandidateReview.Candidate) {
        selectedTransitionCandidateID = candidate.id
        seekAndCenter(on: candidate.time)
    }

    func selectNearestTransitionCandidate(
        to time: TimeInterval,
        tolerance: TimeInterval
    ) {
        guard let candidate = pendingTransitionCandidates.min(by: {
            abs($0.time - time) < abs($1.time - time)
        }), abs(candidate.time - time) <= tolerance else {
            return
        }
        selectedTransitionCandidateID = candidate.id
    }

    func jumpToNextTransitionCandidate() {
        let candidates = pendingTransitionCandidates
        guard candidates.isEmpty == false else {
            selectedTransitionCandidateID = nil
            return
        }
        let candidate: TransitionCandidateReview.Candidate
        if let selectedTransitionCandidateID,
           let index = candidates.firstIndex(where: { $0.id == selectedTransitionCandidateID }) {
            candidate = candidates[(index + 1) % candidates.count]
        } else {
            candidate = candidates.first { $0.time > currentTime + 0.5 } ?? candidates[0]
        }
        jumpToTransitionCandidate(candidate)
    }

    func jumpToPreviousTransitionCandidate() {
        let candidates = pendingTransitionCandidates
        guard candidates.isEmpty == false else {
            selectedTransitionCandidateID = nil
            return
        }
        let candidate: TransitionCandidateReview.Candidate
        if let selectedTransitionCandidateID,
           let index = candidates.firstIndex(where: { $0.id == selectedTransitionCandidateID }) {
            candidate = candidates[(index - 1 + candidates.count) % candidates.count]
        } else {
            candidate = candidates.last { $0.time < currentTime - 0.5 }
                ?? candidates[candidates.count - 1]
        }
        jumpToTransitionCandidate(candidate)
    }

    func acceptSelectedTransitionCandidate() {
        guard isAnalyzerReviewMode,
              let candidate = selectedTransitionCandidate,
              candidateDecision(for: candidate.id) == nil else { return }
        let nearestBoundary = transitionLabeling.segments
            .dropFirst()
            .map(\.startTime)
            .min { abs($0 - candidate.time) < abs($1 - candidate.time) }
        recordCandidateDecision(.accepted, for: candidate, boundaryTime: nearestBoundary)
        selectedTransitionCandidateID = nil
        persistAnalyzerReviewState()
        jumpToNextTransitionCandidate()
    }

    func dismissSelectedTransitionCandidate() {
        guard isAnalyzerReviewMode,
              let candidate = selectedTransitionCandidate,
              candidateDecision(for: candidate.id) == nil else { return }
        recordCandidateDecision(.dismissed, for: candidate, boundaryTime: nil)
        selectedTransitionCandidateID = nil
        persistAnalyzerReviewState()
        jumpToNextTransitionCandidate()
    }

    private func recordCandidateDecision(
        _ decision: TransitionCandidateReview.Decision,
        for candidate: TransitionCandidateReview.Candidate,
        boundaryTime: TimeInterval?
    ) {
        candidateReviewRecords.removeAll { $0.candidateID == candidate.id }
        candidateReviewRecords.append(
            TransitionCandidateReview.Record(
                candidateID: candidate.id,
                decision: decision,
                decidedAt: Date(),
                boundaryTime: boundaryTime
            )
        )
    }

    private func seekAndCenter(on time: TimeInterval) {
        seek(to: time)
        let fraction = time / duration
        let newStart = max(0, min(1 - viewSpan, fraction - viewSpan / 2))
        viewStart = newStart
        viewEnd = newStart + viewSpan
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

    func markBoundaryAtPlayhead() {
        guard !isAnalyzerReviewMode else { return }
        let previousCount = transitionLabeling.segments.count
        transitionLabeling.markBoundary(at: currentTime)
        guard transitionLabeling.segments.count != previousCount else { return }
        selectedPhaseID = transitionLabeling.segments.first {
            abs($0.startTime - currentTime) < 0.051
        }?.id
        labelingDidChange()
    }

    func beginPhaseNaming() {
        labelingPass = .phaseNames
        selectedPhaseID = transitionLabeling.segments.first { $0.phase == nil }?.id
            ?? transitionLabeling.segments.first?.id
        if let selectedSegment {
            jumpToSegment(selectedSegment)
        }
    }

    func resumeBoundaryMarking() {
        labelingPass = .boundaries
    }

    func assignSelectedPhase(_ phase: TrancePhase) {
        guard !isAnalyzerReviewMode, let selectedPhaseID else { return }
        let nextID = transitionLabeling.assign(phase, toSegmentID: selectedPhaseID)
        labelingDidChange()
        self.selectedPhaseID = nextID ?? selectedPhaseID
        if let nextID,
           let next = transitionLabeling.segments.first(where: { $0.id == nextID }) {
            jumpToSegment(next)
        }
    }

    func removePhase(at index: Int) {
        guard !isAnalyzerReviewMode,
              transitionLabeling.segments.indices.contains(index),
              index > 0 else { return }
        transitionLabeling.removeBoundary(startingSegmentID: transitionLabeling.segments[index].id)
        labelingDidChange()
    }

    func clearAllPhases() {
        guard !isAnalyzerReviewMode else { return }
        transitionLabeling = TransitionLabelingDraft(duration: draft.audioDuration, phases: [])
        labelingPass = .boundaries
        labelingDidChange()
    }

    func jumpToSegment(_ segment: TransitionLabelingDraft.Segment) {
        seek(to: segment.startTime)
        let frac = segment.startTime / duration
        let newStart = max(0, min(1 - viewSpan, frac - viewSpan / 2))
        viewStart = newStart
        viewEnd = newStart + viewSpan
    }

    func movePhasePoint(id: PhasePoint.ID, to time: TimeInterval) {
        guard !isAnalyzerReviewMode else { return }
        transitionLabeling.moveBoundary(startingSegmentID: id, to: time)
        labelingDidChange()
    }

    func setPhase(ofPointID id: PhasePoint.ID, to phase: TrancePhase) {
        guard !isAnalyzerReviewMode else { return }
        transitionLabeling.assign(phase, toSegmentID: id)
        labelingDidChange()
    }

    func deletePhasePoint(id: PhasePoint.ID) {
        guard !isAnalyzerReviewMode else { return }
        transitionLabeling.removeBoundary(startingSegmentID: id)
        labelingDidChange()
    }

    func selectPhase(id: UUID?) {
        selectedPhaseID = id
    }

    func loadTranscriptIfAvailable() async {
        guard !Task.isCancelled, transcription == nil else { return }

        if let bundled = BundledAudioTranscriptCatalog.shared.transcription(
            filename: draft.audioFilename,
            duration: draft.audioDuration
        ) {
            try? persistTranscript(bundled)
            applyTranscription(
                bundled,
                statusMessage: "Official transcript loaded from the bundled catalog."
            )
            return
        }

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
        transcriptStatusMessage = "Resolving transcript..."
        defer { isTranscriptLoading = false }

        do {
            let analyzer = makeTranscriptAnalyzer()
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
        guard let labeledPhases = transitionLabeling.labeledPhases else {
            analyzerDiagnostics = nil
            diagnosticsStatusMessage = "Name every segment before comparing predictions against your labels."
            diagnosticsErrorMessage = nil
            diagnosticsAreStale = true
            return
        }

        isDiagnosticsLoading = true
        diagnosticsProgress = 0
        diagnosticsErrorMessage = nil
        diagnosticsStatusMessage = "Running analyzer comparison… 0%"

        var draftSnapshot = draft
        draftSnapshot.phases = labeledPhases
        let durationSnapshot = duration
        let requestID = UUID()
        diagnosticsRequestID = requestID
        let progressHandler: @Sendable (Double) async -> Void = { [weak self] progress in
            await self?.reportDiagnosticsProgress(progress, requestID: requestID)
        }
        let task: Task<AnalyzerDiagnostics?, Never> = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return nil }
            let knowledge = CorpusPhaseKnowledgeCache.shared.knowledge()
            let keywordAnalyzer = HypnosisPhaseAnalyzer(corpusKnowledge: knowledge)
            let wordTimestamps = HypnosisPhaseAnalyzer.approximateWordTimestamps(
                from: transcription.segments
            )
            let keywordPhases = keywordAnalyzer.analyze(
                wordTimestamps: wordTimestamps,
                transcription: transcription,
                techniqueDetection: nil
            )
            guard !Task.isCancelled else { return nil }
            let chunkedPhases = await ChunkedPhaseAnalyzer.analyze(
                wordTimestamps: wordTimestamps,
                duration: transcription.duration,
                onProgress: progressHandler
            )
            guard !Task.isCancelled else { return nil }
            let selection = keywordAnalyzer.selectPreferredPhases(
                keywordPhases: keywordPhases,
                chunkedPhases: chunkedPhases,
                transcription: transcription,
                techniqueDetection: nil
            )
            let techniqueDetection = TechniqueDetectionResult(techniques: [], markers: [])

            return Self.buildAnalyzerDiagnostics(
                draft: draftSnapshot,
                duration: durationSnapshot,
                transcription: transcription,
                keywordPhases: keywordPhases,
                chunkedPhases: chunkedPhases,
                selectedPhases: selection.phases,
                usedChunkedAnalyzer: selection.usedChunkedAnalyzer,
                techniqueDetection: techniqueDetection
            )
        }
        diagnosticsTask = task
        let result = await task.value
        guard diagnosticsRequestID == requestID else { return }

        diagnosticsTask = nil
        diagnosticsRequestID = nil
        isDiagnosticsLoading = false
        diagnosticsProgress = nil
        guard let result else {
            diagnosticsStatusMessage = "Analyzer comparison cancelled."
            return
        }
        analyzerDiagnostics = result
        diagnosticsStatusMessage = "Analyzer comparison ready."
        diagnosticsAreStale = false
    }

    func cancelAnalyzerDiagnostics() {
        cancelAnalyzerDiagnostics(showStatus: true)
    }

    private func cancelAnalyzerDiagnostics(showStatus: Bool) {
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        diagnosticsRequestID = nil
        isDiagnosticsLoading = false
        diagnosticsProgress = nil
        if showStatus {
            diagnosticsStatusMessage = "Analyzer comparison cancelled."
        }
    }

    private func reportDiagnosticsProgress(_ progress: Double, requestID: UUID) {
        guard diagnosticsRequestID == requestID, isDiagnosticsLoading else { return }
        let boundedProgress = min(max(progress, 0), 1)
        diagnosticsProgress = boundedProgress
        diagnosticsStatusMessage = "Running analyzer comparison… \(Int((boundedProgress * 100).rounded()))%"
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

        let suggestionTask = Task.detached(priority: .userInitiated) {
            let knowledge = CorpusPhaseKnowledgeCache.shared.knowledge()
            let analyzer = HypnosisPhaseAnalyzer(corpusKnowledge: knowledge)
            return analyzer.suggestPhaseTimeline(for: transcription)
        }
        let suggestionTimeline = await suggestionTask.value
        suggestedPhaseTimeline = suggestionTimeline

        if suggestionTimeline.segments.isEmpty {
            suggestionStatusMessage = "No strong phase proposal could be built from this transcript yet."
        } else {
            suggestionStatusMessage = "Suggested \(suggestionTimeline.segments.count) phase segments from phrase evidence."
        }
    }

    func analyzeSemanticWindows(
        examples: [SemanticPhaseAnalyzer.Example]? = nil,
        configuration: SemanticPhaseAnalyzer.Configuration = .init()
    ) async {
        guard let transcription else {
            semanticPhaseAnalysis = nil
            semanticPhaseStatusMessage = "Generate a transcript before comparing semantic windows."
            semanticPhaseErrorMessage = nil
            return
        }

        semanticPhaseAnalysisTask?.cancel()
        let requestID = UUID()
        semanticPhaseAnalysisRequestID = requestID
        isSemanticPhaseAnalysisRunning = true
        semanticPhaseErrorMessage = nil
        semanticPhaseStatusMessage = "Comparing transcript meaning with hand-labeled examples…"

        let corpusDirectory = corpus.analyzerDatasetDirectory.deletingLastPathComponent()
        let fileID = fileID
        let analysisTask = Task.detached(priority: .userInitiated) {
            let resolvedExamples = try examples ?? SemanticPhaseExampleStore.load(
                from: corpusDirectory,
                excluding: fileID
            )
            let analyzer = SemanticPhaseAnalyzer(
                examples: resolvedExamples,
                configuration: configuration
            )
            return try analyzer.analyze(transcription: transcription)
        }
        semanticPhaseAnalysisTask = analysisTask

        do {
            let analysis = try await analysisTask.value
            guard semanticPhaseAnalysisRequestID == requestID else { return }
            semanticPhaseAnalysis = analysis
            if analysis.exampleCount == 0 {
                semanticPhaseStatusMessage = "No hand-labeled transcript examples are available yet."
            } else if analysis.windows.isEmpty {
                semanticPhaseStatusMessage = "No transcript windows could be compared."
            } else {
                semanticPhaseStatusMessage = "Compared \(analysis.windows.count) windows with \(analysis.exampleCount) hand-labeled examples."
            }
        } catch is CancellationError {
            guard semanticPhaseAnalysisRequestID == requestID else { return }
            semanticPhaseStatusMessage = nil
        } catch {
            guard semanticPhaseAnalysisRequestID == requestID else { return }
            semanticPhaseStatusMessage = "Semantic-window analysis failed."
            semanticPhaseErrorMessage = error.localizedDescription
        }

        if semanticPhaseAnalysisRequestID == requestID {
            semanticPhaseAnalysisTask = nil
            semanticPhaseAnalysisRequestID = nil
            isSemanticPhaseAnalysisRunning = false
        }
    }

    func cancelSemanticPhaseAnalysis() {
        semanticPhaseAnalysisTask?.cancel()
        semanticPhaseAnalysisTask = nil
        semanticPhaseAnalysisRequestID = nil
        isSemanticPhaseAnalysisRunning = false
        semanticPhaseStatusMessage = nil
    }

    func jumpToSemanticSegment(_ segment: SemanticPhaseAnalyzer.Segment) {
        seek(to: segment.startTime)
        let fraction = segment.startTime / duration
        let newStart = max(0, min(1 - viewSpan, fraction - viewSpan / 2))
        viewStart = newStart
        viewEnd = newStart + viewSpan
    }

    func jumpToSuggestedPhase(_ segment: SuggestedPhaseSegment) {
        seek(to: segment.startTime)
        let frac = segment.startTime / duration
        let newStart = max(0, min(1 - viewSpan, frac - viewSpan / 2))
        viewStart = newStart
        viewEnd = newStart + viewSpan
    }

    @discardableResult
    func save() async -> Bool {
        guard !isSaving else { return false }
        guard let labeledPhases = transitionLabeling.labeledPhases else {
            alertMessage = transitionLabeling.readinessIssue?.message
                ?? "The phase timeline is not ready to save."
            return false
        }
        autosaveTask?.cancel()
        autosaveTask = nil
        let work = makeWorkInProgress(labeledPhases: labeledPhases)
        pendingWork = work
        recoveryStore.stage(work, in: recoveryDirectory)
        await persist(work, commitCompletedTimeline: true, presentsErrors: true)
        return saveState == .saved && pendingWork == nil
    }

    func setExpectedFrequencyBand(_ band: LabeledFile.FrequencyBand) {
        guard !isAnalyzerReviewMode,
              draft.expectedFrequencyBand.lower != band.lower
                || draft.expectedFrequencyBand.upper != band.upper else { return }
        draft.expectedFrequencyBand = band
        metadataDidChange()
    }

    func setLabelerNotes(_ notes: String) {
        guard !isAnalyzerReviewMode, draft.labelerNotes != notes else { return }
        draft.labelerNotes = notes
        metadataDidChange()
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
        case .preTalk, .induction: return 0.28
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

    func phaseDepth(_ phase: TrancePhase?) -> Double {
        phase.map(phaseDepth) ?? 0.5
    }

    func phaseColor(_ phase: TrancePhase) -> Color {
        switch phase {
        case .preTalk, .induction: return .blue
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

    func phaseColor(_ phase: TrancePhase?) -> Color {
        phase.map(phaseColor) ?? .secondary
    }

    func phaseDisplayName(_ phase: TrancePhase?) -> String {
        phase?.displayName ?? "Unassigned"
    }

    func keyboardShortcutLabel(for index: Int) -> String? {
        guard (0..<9).contains(index) else { return nil }
        return String(index + 1)
    }

    private func labelingDidChange() {
        diagnosticsAreStale = true
        analyzerDiagnostics = nil
        diagnosticsStatusMessage = nil
        diagnosticsErrorMessage = nil
        syncSelectedPhase()
        rebuildTranscriptInsights()
        stageWorkInProgress()
    }

    private func metadataDidChange() {
        diagnosticsAreStale = true
        stageWorkInProgress()
    }

    private func stageWorkInProgress() {
        let work = makeWorkInProgress()
        pendingWork = work
        recoveryStore.stage(work, in: recoveryDirectory)
        saveState = .unsaved
        saveFailureMessage = nil
        scheduleAutosave(for: work)
    }

    private func scheduleAutosave(for work: LabelingWorkInProgress) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(600))
            } catch {
                return
            }
            guard let self, self.pendingWork?.revision == work.revision else { return }
            await self.persist(work, commitCompletedTimeline: true, presentsErrors: false)
        }
    }

    private func makeWorkInProgress(
        labeledPhases: [LabeledFile.LabeledPhase]? = nil
    ) -> LabelingWorkInProgress {
        var file = draft
        if let labeledPhases {
            file.phases = labeledPhases
        }
        return LabelingWorkInProgress(
            file: file,
            labeling: transitionLabeling,
            candidateReviews: candidateReviewRecords,
            analyzerReviewBaseline: analyzerReviewBaseline
        )
    }

    private func persistAnalyzerReviewState() {
        let work = makeWorkInProgress()
        recoveryStore.stage(work, in: recoveryDirectory)
        analyzerReviewPersistenceTask?.cancel()
        analyzerReviewPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                try await self.recoveryStore.persist(work, in: self.recoveryDirectory)
            } catch is CancellationError {
                return
            } catch {
                self?.alertMessage = "Could not save analyzer review: \(error.localizedDescription)"
            }
        }
    }

    private func persist(
        _ work: LabelingWorkInProgress,
        commitCompletedTimeline: Bool,
        presentsErrors: Bool
    ) async {
        guard pendingWork?.revision == work.revision else { return }
        savingRevision = work.revision
        isSaving = true
        saveState = .saving

        defer {
            if savingRevision == work.revision {
                savingRevision = nil
                isSaving = false
            }
        }

        do {
            try await recoveryStore.persist(work, in: recoveryDirectory)

            if commitCompletedTimeline,
               let labeledPhases = work.labeling.labeledPhases {
                var toSave = work.fileMetadata
                toSave.phases = labeledPhases
                toSave.expectedContentType = .hypnosis
                toSave.labeledAt = work.updatedAt
                let saved = try await corpus.save(toSave)

                guard pendingWork?.revision == work.revision else { return }
                draft = saved
                pendingWork = nil
                saveState = .saved
                saveFailureMessage = nil
                alertMessage = nil
                syncSelectedPhase()
                rebuildTranscriptInsights()
            } else if pendingWork?.revision == work.revision {
                saveState = .draftSaved
                saveFailureMessage = nil
            }
        } catch {
            guard pendingWork?.revision == work.revision else { return }
            saveState = .failed
            saveFailureMessage = error.localizedDescription
            if presentsErrors {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func syncSelectedPhase() {
        guard !transitionLabeling.segments.isEmpty else {
            selectedPhaseID = nil
            return
        }

        if let selectedPhaseID,
           transitionLabeling.segments.contains(where: { $0.id == selectedPhaseID }) {
            return
        }

        selectedPhaseID = transitionLabeling.segments.first?.id
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
        phase.labelingPhase
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
        semanticPhaseAnalysisTask?.cancel()
        semanticPhaseAnalysisTask = nil
        semanticPhaseAnalysisRequestID = nil
        semanticPhaseAnalysis = nil
        isSemanticPhaseAnalysisRunning = false
        semanticPhaseErrorMessage = nil
        semanticPhaseStatusMessage = "Run semantic windows to compare meaning with hand-labeled examples."
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
            uniqueKeysWithValues: transitionLabeling.segments.compactMap { segment in
                guard let insight = Self.makeTranscriptInsight(
                    id: segment.id,
                    phase: segment.phase,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    transcription: transcription
                ) else {
                    return nil
                }
                return (segment.id, insight)
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
