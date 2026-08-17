//
//  CableAudioImportModel.swift
//  Ilumionate
//

import Observation

typealias CableAudioScan = @MainActor @Sendable () async -> CableAudioImportResult
typealias CableLibraryRefresh = @MainActor @Sendable () async -> Void

/// Main-actor presentation state for the Finder cable inbox. File-system work
/// remains serialized inside `CableAudioImportService`; this model only decides
/// when a result deserves UI and refreshes the app's existing library snapshot.
@MainActor
@Observable
final class CableAudioImportModel {
    private(set) var isScanning = false
    var presentedResult: CableAudioImportResult?

    private let scanOperation: CableAudioScan
    private let refreshLibrary: CableLibraryRefresh
    private let pendingRecheckDelay: Duration

    /// Finder reports a copy finished before the device has flushed it, so the
    /// first pass over a large batch can find every file still growing. Rather
    /// than promise "checked again later" and never look, recheck a bounded
    /// number of times.
    private static let maximumPendingRechecks = 3

    private var inFlight: Task<CableAudioImportResult, Never>?
    /// Remembered across scans so a later empty result can distinguish "nothing
    /// new" from "nothing ever arrived".
    private var importsThisSession = 0

    init(
        service: CableAudioImportService = CableAudioImportService(),
        refreshLibrary: @escaping CableLibraryRefresh = {
            await AudioLibraryCache.shared.refresh()
        },
        pendingRecheckDelay: Duration = .seconds(3)
    ) {
        scanOperation = { await service.importAvailableFiles() }
        self.refreshLibrary = refreshLibrary
        self.pendingRecheckDelay = pendingRecheckDelay
    }

    init(
        scan: @escaping CableAudioScan,
        refreshLibrary: @escaping CableLibraryRefresh,
        pendingRecheckDelay: Duration = .seconds(3)
    ) {
        scanOperation = scan
        self.refreshLibrary = refreshLibrary
        self.pendingRecheckDelay = pendingRecheckDelay
    }

    /// Automatic scans stay silent when the inbox is empty. A user-requested
    /// scan always reports back so the button never feels broken.
    ///
    /// A tap arriving while a scan runs waits for it and then runs a fresh
    /// pass. Dropping it — which is what a plain `isScanning` guard did — meant
    /// that tapping Check during the automatic foreground scan produced no
    /// result at all, and a large transfer looked like nothing happened.
    func scan(manual: Bool = false) async {
        if let running = inFlight {
            _ = await running.value
            guard manual else { return }
        }

        isScanning = true
        defer {
            isScanning = false
            inFlight = nil
        }

        var aggregate = CableAudioImportResult()
        var passes = 0

        while true {
            let pass = Task { @MainActor [scanOperation] in await scanOperation() }
            inFlight = pass
            aggregate.merge(await pass.value)
            passes += 1

            guard aggregate.pending.isEmpty == false,
                  passes <= Self.maximumPendingRechecks else { break }
            try? await Task.sleep(for: pendingRecheckDelay)
            guard !Task.isCancelled else { break }
        }

        importsThisSession += aggregate.imported.count
        aggregate.priorImportCount = importsThisSession - aggregate.imported.count

        if aggregate.imported.isEmpty == false {
            await refreshLibrary()
        }
        if aggregate.hasActivity || manual {
            presentedResult = aggregate
        }
    }

    func dismissResult() {
        presentedResult = nil
    }

    /// Clears the presented batch before queueing begins, preventing a second
    /// tap or a stale alert from scheduling the same files twice.
    func consumeImportedForAnalysis() -> [AudioFile] {
        let imported = presentedResult?.imported ?? []
        presentedResult = nil
        return imported
    }
}
