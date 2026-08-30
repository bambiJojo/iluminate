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

    init(loadStructure: @escaping @MainActor () async -> AnalysisStructuralInput) {
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

// MARK: - Production wiring

extension AnalysisCenterModel {

    /// The live model. Disk work — the library load and the generated-session
    /// enumeration — happens off the main actor; only the bundled-catalog match
    /// and the manager's published collections are read on it.
    static func live(manager: AnalysisStateManager = .shared) -> AnalysisCenterModel {
        AnalysisCenterModel {
            let files = await AudioLibraryStore.loadRepairingStoredFiles()
            let (checkpoints, durableFailures) = await manager.recoverySnapshot()

            // Off the main actor: one JSON decode per file that has a score.
            let sessionStore = GeneratedSessionStore.shared
            var ready = AnalysisTaskInputAssembler.generatedReadySnapshots(
                for: files, store: sessionStore
            )

            let (queue, runtimeFailures, goldReady) = await MainActor.run {
                let queue = AnalysisTaskInputAssembler.deduplicate(
                    queue: manager.analysisQueue.map(\.id)
                )
                let runtime = Dictionary(
                    uniqueKeysWithValues: manager.failedAnalyses.map {
                        ($0.audioFile.id, AnalysisTaskInputAssembler.failureSnapshot(from: $0))
                    }
                )
                // Bundled gold scores have no file on disk, so the off-actor
                // pass cannot see them. Fold them in here; the match is cached
                // in-memory and never touches disk.
                var gold: [UUID: AnalysisReadySnapshot] = [:]
                for file in files where ready[file.id] == nil {
                    guard let session = sessionStore.goldSessionIfAny(for: file) else { continue }
                    gold[file.id] = AnalysisReadySnapshot(
                        sessionID: session.id,
                        readyAt: file.createdDate
                    )
                }
                return (queue, runtime, gold)
            }
            ready.merge(goldReady) { current, _ in current }

            return AnalysisStructuralInput(
                libraryFiles: files,
                queue: queue,
                failures: AnalysisFailureMerge.merge(
                    durable: durableFailures, runtime: runtimeFailures
                ),
                checkpoints: checkpoints,
                ready: ready
            )
        }
    }
}
