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

    let fileID: LabeledFile.ID
    let orderedPhases: [TrancePhase] = [
        .preTalk, .induction, .deepening, .therapy,
        .suggestions, .conditioning, .emergence
    ]

    var draft: LabeledFile
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var viewStart: Double = 0
    var viewEnd: Double = 1
    var lastMagnification: Double = 1
    var draggingPointID: PhasePoint.ID?
    var alertMessage: String?
    var isSaving = false

    private let corpus: TrainingCorpusManager
    private var player: AVAudioPlayer?
    private var positionTask: Task<Void, Never>?

    init(file: LabeledFile, corpus: TrainingCorpusManager) {
        self.fileID = file.id
        self.draft = file
        self.corpus = corpus
        normalizePhases()
    }

    var duration: TimeInterval { max(draft.audioDuration, 1) }
    var viewSpan: Double { max(0.001, viewEnd - viewStart) }
    var phasePoints: [PhasePoint] {
        draft.phases.map { phase in
            PhasePoint(id: phase.id, phase: phase.phase, time: phase.startTime)
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

    func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            normalizePhases()
            var toSave = draft
            toSave.labeledAt = Date()
            let saved = try await corpus.save(toSave)
            draft = saved
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
        case .induction:    return 0.40
        case .deepening:    return 0.75
        case .therapy:      return 0.90
        case .suggestions:  return 0.65
        case .conditioning: return 0.45
        case .emergence:    return 0.15
        case .transitional: return 0.40
        }
    }

    func phaseColor(_ phase: TrancePhase) -> Color {
        switch phase {
        case .preTalk:      return .indigo
        case .induction:    return .blue
        case .deepening:    return .teal
        case .therapy:      return .purple
        case .suggestions:  return .pink
        case .conditioning: return .orange
        case .emergence:    return .green
        case .transitional: return .gray
        }
    }

    private func normalizePhases() {
        guard !draft.phases.isEmpty else { return }

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
    }
}
