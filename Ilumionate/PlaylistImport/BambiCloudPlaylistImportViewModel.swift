//
//  BambiCloudPlaylistImportViewModel.swift
//  Ilumionate
//

import Foundation
import Observation

@MainActor
@Observable
final class BambiCloudPlaylistImportViewModel {
    var linkText = ""
    private(set) var plan: BambiCloudPlaylistImportPlan?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var availableAudioFiles: [AudioFile]
    // Keyed by row, not track: a playlist can repeat a track, and per-track
    // keys made the second copy's button a silent no-op.
    private(set) var downloadingRowIDs: Set<BambiCloudPlaylistImportPlan.Row.ID> = []
    private(set) var downloadErrors: [BambiCloudPlaylistImportPlan.Row.ID: String] = [:]
    var pendingDownload: PendingLargeDownload?

    private let client: BambiCloudPlaylistClient
    private let importer: BambiCloudPlaylistImporter
    private let downloader: PlaylistTrackDownloader
    private let analysisQueue: @MainActor (AudioFile) async -> Void
    private let isAutoAnalyseEnabled: @MainActor () -> Bool

    init(
        availableAudioFiles: [AudioFile],
        client: BambiCloudPlaylistClient = BambiCloudPlaylistClient(),
        importer: BambiCloudPlaylistImporter = BambiCloudPlaylistImporter(),
        downloader: PlaylistTrackDownloader = PlaylistTrackDownloader(),
        isAutoAnalyseEnabled: @escaping @MainActor () -> Bool = {
            AnalysisPreferences.shared.autoAnalyzeOnImport
        },
        analysisQueue: @escaping @MainActor (AudioFile) async -> Void = { audioFile in
            await AnalysisStateManager.shared.queueForAnalysis(audioFile)
        }
    ) {
        self.availableAudioFiles = availableAudioFiles
        self.client = client
        self.importer = importer
        self.downloader = downloader
        self.isAutoAnalyseEnabled = isAutoAnalyseEnabled
        self.analysisQueue = analysisQueue
    }

    var canLoad: Bool {
        !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
    }

    var canImport: Bool {
        (plan?.matchedCount ?? 0) > 0
    }

    func loadPlaylist() async {
        guard canLoad else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let playlist = try await client.fetchPlaylist(from: linkText)
            guard !playlist.tracks.isEmpty else {
                throw PlaylistLinkImportError.emptyPlaylist
            }
            plan = importer.makePlan(
                for: playlist,
                availableAudioFiles: availableAudioFiles
            )
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
                ?? PlaylistLinkImportError.invalidResponse.localizedDescription
        } catch {
            errorMessage = PlaylistLinkImportError.invalidResponse.localizedDescription
        }
    }

    func select(
        audioFileID: AudioFile.ID?,
        forRow rowID: BambiCloudPlaylistImportPlan.Row.ID
    ) {
        plan?.select(audioFileID: audioFileID, forRow: rowID)
    }

    var downloadableCount: Int {
        plan?.downloadableRows.count ?? 0
    }

    func isDownloading(_ rowID: BambiCloudPlaylistImportPlan.Row.ID) -> Bool {
        downloadingRowIDs.contains(rowID)
    }

    /// Entry point for the per-track Download button.
    ///
    /// Three outcomes before a single byte is fetched: the library already has
    /// this (bind and stop), the library probably has this (ask), or the file
    /// is large enough to be worth confirming.
    func requestDownload(of row: BambiCloudPlaylistImportPlan.Row) async {
        guard !downloadingRowIDs.contains(row.id) else { return }

        downloadErrors[row.id] = nil

        let size = try? await downloader.expectedSize(of: row.track)
        let verdict = DuplicateAudioIndex(availableAudioFiles).verdict(
            for: DuplicateAudioCandidate(
                remoteSource: row.track.audioURL.map { url in
                    RemoteAudioSource(
                        service: RemoteAudioSource.bambiCloudService,
                        trackID: row.track.id.uuidString,
                        url: url
                    )
                },
                fileSize: size,
                duration: row.track.duration,
                title: row.track.name
            )
        )

        switch verdict {
        case .identical(let existingID):
            plan?.select(audioFileID: existingID, forRow: row.id)
            plan?.markResolvedAsExisting(rowID: row.id)
            return
        case .likely(let existingID, _):
            plan?.markPossibleDuplicate(existing: existingID, forRow: row.id)
            return
        case .distinct:
            break
        }

        if let size, size > PlaylistTrackDownloader.confirmationThresholdBytes {
            pendingDownload = PendingLargeDownload(
                scope: .row(id: row.id, name: row.track.name),
                byteCount: size
            )
            return
        }

        await downloadRow(row)
    }

    /// The user chose to fetch a fresh copy despite the likely match.
    func downloadAnyway(_ row: BambiCloudPlaylistImportPlan.Row) async {
        await downloadRow(row, allowingLargeFile: true)
    }

    func requestDownloadOfAllMissingTracks() async {
        let rows = plan?.downloadableRows ?? []
        guard !rows.isEmpty else { return }

        var total: Int64 = 0
        var sawAnySize = false
        for row in rows {
            if let size = try? await downloader.expectedSize(of: row.track), size > 0 {
                total += size
                sawAnySize = true
            }
        }

        pendingDownload = PendingLargeDownload(
            scope: .allMissing(trackCount: rows.count),
            byteCount: sawAnySize ? total : nil
        )
    }

    /// Runs whatever the user just approved, with the size ceiling lifted.
    ///
    /// Takes the request as an argument because `alert(item:)` clears the
    /// binding before the button action runs — reading it back here finds nil.
    func confirmDownload(_ pending: PendingLargeDownload) async {
        pendingDownload = nil

        switch pending.scope {
        case .row(let id, _):
            guard let row = plan?.rows.first(where: { $0.id == id }) else { return }
            await downloadRow(row, allowingLargeFile: true)
        case .allMissing:
            for row in plan?.downloadableRows ?? [] {
                await downloadRow(row, allowingLargeFile: true)
            }
        }
    }

    func cancelPendingDownload() {
        pendingDownload = nil
    }

    /// Fills a row the matcher could not resolve — from the library when the
    /// track is already there, and from the publisher only when it is not.
    func downloadRow(
        _ row: BambiCloudPlaylistImportPlan.Row,
        allowingLargeFile: Bool = false
    ) async {
        guard !downloadingRowIDs.contains(row.id) else { return }

        let index = DuplicateAudioIndex(availableAudioFiles)

        // Free, and it runs before any request: a track fetched from a previous
        // playlist is recognised by the publisher's own identifier.
        if let audioURL = row.track.audioURL {
            let verdict = index.verdict(
                for: DuplicateAudioCandidate(
                    remoteSource: RemoteAudioSource(
                        service: RemoteAudioSource.bambiCloudService,
                        trackID: row.track.id.uuidString,
                        url: audioURL
                    ),
                    duration: row.track.duration,
                    title: row.track.name
                )
            )
            if case .identical(let existingID) = verdict {
                plan?.select(audioFileID: existingID, forRow: row.id)
                plan?.markResolvedAsExisting(rowID: row.id)
                return
            }
        }

        downloadingRowIDs.insert(row.id)
        downloadErrors[row.id] = nil
        defer { downloadingRowIDs.remove(row.id) }

        do {
            let outcome = try await downloader.download(
                row.track,
                allowingLargeFile: allowingLargeFile,
                existing: index
            )

            switch outcome {
            case .alreadyInLibrary(let existingID):
                plan?.select(audioFileID: existingID, forRow: row.id)
                plan?.markResolvedAsExisting(rowID: row.id)

            case .saved(let audioFile):
                await AudioLibraryStore.add(audioFile)

                availableAudioFiles.insert(audioFile, at: 0)
                plan?.adopt(downloadedFile: audioFile, forRow: row.id)
                await queueForAnalysis(audioFile)
            }
        } catch PlaylistTrackDownloadError.confirmationRequired(let byteCount) {
            // The server under-reported the size up front; ask rather than fail.
            pendingDownload = PendingLargeDownload(
                scope: .row(id: row.id, name: row.track.name),
                byteCount: byteCount
            )
        } catch let error as PlaylistTrackDownloadError {
            downloadErrors[row.id] = error.errorDescription
        } catch {
            downloadErrors[row.id] = PlaylistTrackDownloadError
                .networkUnavailable
                .localizedDescription
        }
    }

    /// A freshly downloaded track has no light session yet, so it goes into the
    /// analyser the same way a file imported through the library browser does —
    /// including honouring the user's auto-analyse preference.
    private func queueForAnalysis(_ audioFile: AudioFile) async {
        guard isAutoAnalyseEnabled() else { return }
        await analysisQueue(audioFile)
    }

    #if DEBUG
    /// Seeds a plan without a network round trip, for tests.
    func adoptPlanForTesting(_ plan: BambiCloudPlaylistImportPlan) {
        self.plan = plan
    }
    #endif

    func startOver() {
        plan = nil
        errorMessage = nil
        downloadErrors.removeAll()
    }

    func makePlaylist() -> Playlist? {
        plan?.makePlaylist()
    }
}
