//
//  AnalysisCenterModel.swift
//  Ilumionate
//
//  Single owner of the published [AnalysisTask] snapshot. Created at the app
//  root and injected into every analysis surface; no surface builds its own.
//

import Foundation

/// The disk- and store-backed half of the projection input. The progress half
/// (`activeAnalysis`, `modelDownload`) is held separately so a progress tick
/// never triggers a disk read.
nonisolated struct AnalysisStructuralInput: Equatable, Sendable {
    let libraryFiles: [AudioFile]
    let queue: [UUID]
    let failures: [UUID: AnalysisFailureSnapshot]
    let checkpoints: [UUID: AnalysisCheckpointSnapshot]
    let ready: [UUID: AnalysisReadySnapshot]

    static let empty = AnalysisStructuralInput(
        libraryFiles: [], queue: [], failures: [:], checkpoints: [:], ready: [:]
    )
}

@MainActor
@Observable
final class AnalysisCenterModel {

    /// `nil` until the first publication, so surfaces can tell "still loading"
    /// from "nothing to show" and the pill does not flash an empty state.
    private(set) var tasks: [AnalysisTask]?

    private var structure: AnalysisStructuralInput = .empty
    private var activeAnalysis: ActiveAnalysisSnapshot?
    private var modelDownload: ModelDownloadProgress?

    private var coordinator: AnalysisRefreshCoordinator<AnalysisStructuralInput>!

    init(loadStructure: @escaping () async -> AnalysisStructuralInput) {
        // Observers are installed before any load starts, so an invalidation
        // racing bootstrap is recorded rather than lost.
        coordinator = AnalysisRefreshCoordinator(
            load: loadStructure,
            commit: { [weak self] structure in
                guard let self else { return }
                self.structure = structure
                // Republish merges the *live* progress fields, never the values
                // captured when the pass began.
                self.republish()
            }
        )
    }

    // MARK: Refresh

    func invalidateStructure() {
        coordinator.invalidate()
    }

    /// Test support: request a refresh and wait for it to settle.
    func refreshAndWait() async {
        coordinator.invalidate()
        await coordinator.drain()
    }

    /// High-frequency path. Never touches disk.
    func updateProgress(active: ActiveAnalysisSnapshot?, download: ModelDownloadProgress?) {
        activeAnalysis = active
        modelDownload = download
        republish()
    }

    private func republish() {
        tasks = AnalysisTaskProjection.tasks(from: AnalysisTaskProjectionInput(
            libraryFiles: structure.libraryFiles,
            activeAnalysis: activeAnalysis,
            modelDownload: modelDownload,
            queue: structure.queue,
            failures: structure.failures,
            checkpoints: structure.checkpoints,
            ready: structure.ready
        ))
    }

    // MARK: Selectors

    private var queuePositions: [UUID: Int] {
        var positions: [UUID: Int] = [:]
        for (index, id) in structure.queue.enumerated() where positions[id] == nil {
            positions[id] = index + 1
        }
        return positions
    }

    /// Everything the pill may represent: live work plus failures that need a
    /// decision. Dismissed failures are excluded.
    var pillCandidates: [AnalysisTask] {
        guard let tasks else { return [] }
        let positions = queuePositions
        return tasks.filter { task in
            switch task.state {
            case .preparing, .running, .queued:
                return true
            case .paused, .failed, .ready:
                return AnalysisTaskProjection.needsDecision(task, queuePositions: positions)
            }
        }
    }

    /// The pill's headline: live progress, because it is transient and
    /// self-resolving. A failure is a standing decision and gets the chip.
    var activeTask: AnalysisTask? {
        tasks?.first { task in
            switch task.state {
            case .preparing, .running: return true
            default: return false
            }
        }
    }

    var queuedCount: Int {
        guard let tasks else { return 0 }
        return tasks.count { if case .queued = $0.state { return true } else { return false } }
    }

    var attentionCount: Int {
        guard let tasks else { return 0 }
        let positions = queuePositions
        return tasks.count { AnalysisTaskProjection.needsDecision($0, queuePositions: positions) }
    }

    func task(for audioFileID: UUID) -> AnalysisTask? {
        tasks?.first { $0.id == audioFileID }
    }
}
