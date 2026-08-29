//
//  CableFileImportService.swift
//  Ilumionate
//

import Foundation

typealias CableImportWait = @Sendable (Duration) async throws -> Void

/// Admits files copied into the Finder-visible inbox. The actor serializes
/// scans so launch, foreground, and a manual refresh cannot import one drop
/// more than once.
actor CableFileImportService {
    /// Where a file was found. The root is shared with other subsystems, so an
    /// unrecognised file there belongs to somebody else; in the dedicated inbox
    /// the same file is a failed import worth surfacing.
    fileprivate enum Source: Sendable, Equatable {
        case root
        case dedicated
    }

    private let rootInboxURL: URL
    private let dedicatedInboxURL: URL?
    private let textInboxURL: URL?
    private let reviewURL: URL
    private let importedURL: URL
    private let managedAudioURL: URL
    private let readerAdmission: ReaderInboxAdmission
    private let libraryStorage: AudioLibraryStorage
    private let stabilityDelay: Duration
    /// How long a file must have sat untouched before it may be moved.
    ///
    /// Two snapshots a second apart are not enough. Finder copies a batch one
    /// file at a time, and a file that finished moments ago looks identical in
    /// both snapshots — moving it out from under an in-flight transfer makes
    /// the whole drag fail with "required file cannot be found".
    private let minimumSettleAge: Duration
    private let now: @Sendable () -> Date
    private let wait: CableImportWait

    init(
        rootInboxURL: URL = AppStoragePaths.cableRootInbox,
        dedicatedInboxURL: URL? = AppStoragePaths.cableDedicatedInbox,
        textInboxURL: URL? = AppStoragePaths.cableTextInbox,
        reviewURL: URL = AppStoragePaths.cableReview,
        importedURL: URL = AppStoragePaths.cableImported,
        managedAudioURL: URL = AppStoragePaths.managedAudio,
        readerAdmission: ReaderInboxAdmission = ReaderInboxAdmission(),
        libraryStorage: AudioLibraryStorage = .standard,
        stabilityDelay: Duration = .seconds(1),
        minimumSettleAge: Duration = .seconds(5),
        now: @escaping @Sendable () -> Date = { Date() },
        wait: @escaping CableImportWait = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.rootInboxURL = rootInboxURL
        self.dedicatedInboxURL = dedicatedInboxURL
        self.textInboxURL = textInboxURL
        self.reviewURL = reviewURL
        self.importedURL = importedURL
        self.managedAudioURL = managedAudioURL
        self.readerAdmission = readerAdmission
        self.libraryStorage = libraryStorage
        self.stabilityDelay = stabilityDelay
        self.minimumSettleAge = minimumSettleAge
        self.now = now
        self.wait = wait
    }

    func importAvailableFiles() async -> CableFileImportResult {
        var result = CableFileImportResult()

        do {
            try prepareDirectories()
            let first = try snapshots()
            guard first.isEmpty == false else { return result }

            try await wait(stabilityDelay)
            let second = try snapshots()
            // Per-file age is not enough on its own. A twenty-file copy runs
            // for a minute, so the first file is already "old" while the last
            // is still arriving — and moving the first mid-batch is what makes
            // Finder report "required file cannot be found". While anything in
            // the directory is still changing, the whole batch waits.
            if let newest = second.values.compactMap(\.modificationDate).max(),
               now().timeIntervalSince(newest) < TimeInterval(minimumSettleAge.components.seconds) {
                result.pending = second.values
                    .map(\.url.lastPathComponent)
                    .sorted()
                return result
            }

            let library = AudioLibraryStore.load(storage: libraryStorage)
            var duplicateIndex = DuplicateAudioIndex(library)
            // `migrateLegacyAudio` sweeps `.documents` entries into managed
            // storage, but its ordering against a cable scan is not guaranteed.
            // A file a library row still points at must not be moved, or the
            // row is left addressing nothing and playback breaks silently.
            //
            // Compared by resolved URL, not filename: a *new* drop that merely
            // shares a name with a managed entry resolves to a different path,
            // so it still reaches duplicate detection.
            let registeredURLs = Set(library.map(\.url.standardizedFileURL))

            for snapshot in first.values.sorted(by: { $0.url.path < $1.url.path }) {
                guard !Task.isCancelled else { break }
                guard second[snapshot.url] == snapshot else {
                    result.pending.append(snapshot.url.lastPathComponent)
                    continue
                }

                guard hasSettled(snapshot) else {
                    result.pending.append(snapshot.url.lastPathComponent)
                    continue
                }

                switch CableInboxFileKind(url: snapshot.url) {
                case .unrecognized:
                    // At the root this is somebody else's file, not a failed
                    // import. Moving it would be the bug.
                    if snapshot.source == .dedicated {
                        recordRejection(
                            snapshot.url,
                            category: "Unsupported Files",
                            result: &result
                        )
                    }
                    continue

                case .readerDocument:
                    let outcome = await admitReaderDocument(at: snapshot.url)
                    if let document = outcome.document {
                        result.importedDocuments.append(document)
                    }
                    if let failure = outcome.failure {
                        result.failures.append(failure)
                    }
                    if outcome.rejected {
                        recordRejection(
                            snapshot.url,
                            category: "Invalid Documents",
                            result: &result
                        )
                    }
                    if outcome.duplicate {
                        do {
                            try preserveForReview(snapshot.url, category: "Duplicates")
                            result.duplicates.append(snapshot.url.lastPathComponent)
                        } catch {
                            result.failures.append(CableFileImportFailure(
                                filename: snapshot.url.lastPathComponent,
                                message: error.localizedDescription
                            ))
                        }
                    }
                    continue

                case .audio:
                    // Reader documents copy extracted text into their own store
                    // and never address the inbox URL. This ownership guard is
                    // therefore audio-only.
                    guard !registeredURLs.contains(snapshot.url.standardizedFileURL) else {
                        continue
                    }
                }

                guard looksLikeAudio(at: snapshot.url) else {
                    recordRejection(
                        snapshot.url,
                        category: "Invalid Audio",
                        result: &result
                    )
                    continue
                }

                do {
                    let outcome = try await AudioImportWorker.prepareAudioFile(
                        from: snapshot.url,
                        targetFilename: snapshot.url.lastPathComponent,
                        transferMode: .move,
                        durationTimeout: .seconds(5),
                        documentsURL: managedAudioURL,
                        existing: duplicateIndex,
                        storageLocation: .managed
                    )

                    switch outcome {
                    case .alreadyInLibrary:
                        try preserveForReview(snapshot.url, category: "Duplicates")
                        result.duplicates.append(snapshot.url.lastPathComponent)
                    case .imported(let audioFile):
                        guard let library = await AudioLibraryStore.add(
                            audioFile,
                            storage: libraryStorage
                        ) else {
                            rollback(audioFile, to: snapshot.url)
                            result.failures.append(CableFileImportFailure(
                                filename: snapshot.url.lastPathComponent,
                                message: "The library could not be saved. The file was left where it was found."
                            ))
                            continue
                        }
                        duplicateIndex = DuplicateAudioIndex(library)
                        result.imported.append(audioFile)
                    }
                } catch {
                    result.failures.append(CableFileImportFailure(
                        filename: snapshot.url.lastPathComponent,
                        message: error.localizedDescription
                    ))
                }
            }
        } catch is CancellationError {
            return result
        } catch {
            result.failures.append(CableFileImportFailure(
                filename: rootInboxURL.lastPathComponent,
                message: error.localizedDescription
            ))
        }

        return result
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(
            at: rootInboxURL,
            withIntermediateDirectories: true
        )
        if let dedicatedInboxURL {
            try FileManager.default.createDirectory(
                at: dedicatedInboxURL,
                withIntermediateDirectories: true
            )
        }
        if let textInboxURL {
            try FileManager.default.createDirectory(
                at: textInboxURL,
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(
            at: managedAudioURL,
            withIntermediateDirectories: true
        )
    }

    /// Directory names at the Documents root that belong to the app rather than
    /// to intake. Everything else is descended into: dragging twenty files
    /// usually means dragging the folder holding them, and a flatly
    /// non-recursive scan would make that batch invisible.
    private static let appOwnedDirectoryNames: Set<String> = [
        "TrainingCorpus",
        "TrainingOutput",
        "GeneratedSessions",
        "Inbox",            // iOS places externally-opened documents here
        "_Imported"         // this service's own output; descending re-imports it forever
    ]

    private var excludedRootDirectoryNames: Set<String> {
        var names = Self.appOwnedDirectoryNames
        names.insert(reviewURL.lastPathComponent)
        names.insert(importedURL.lastPathComponent)
        // Each dedicated inbox is walked as its own source, with its own
        // rejection policy. Descending into one from the root would relabel it.
        if let dedicatedInboxURL {
            names.insert(dedicatedInboxURL.lastPathComponent)
        }
        if let textInboxURL {
            names.insert(textInboxURL.lastPathComponent)
        }
        return names
    }

    private func snapshots() throws -> [URL: CableFileSnapshot] {
        var found = try snapshots(
            in: rootInboxURL,
            source: .root,
            excluding: excludedRootDirectoryNames
        )
        for inbox in [dedicatedInboxURL, textInboxURL].compactMap({ $0 }) {
            let nested = try snapshots(
                in: inbox,
                source: .dedicated,
                excluding: [reviewURL.lastPathComponent, importedURL.lastPathComponent]
            )
            found.merge(nested) { current, _ in current }
        }
        return found
    }

    /// Walks a source directory, refusing to enter any directory named in
    /// `excluding`. Exclusion is by name rather than depth so a user's folder of
    /// audio is admitted while app-owned storage is left strictly alone.
    private func snapshots(
        in directoryURL: URL,
        source: Source,
        excluding excludedDirectoryNames: Set<String>
    ) throws -> [URL: CableFileSnapshot] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var found: [URL: CableFileSnapshot] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                if excludedDirectoryNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            found[url] = CableFileSnapshot(
                url: url,
                source: source,
                byteCount: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate
            )
        }
        return found
    }

    /// A file with no modification date is treated as unsettled: without
    /// evidence that it is finished, leaving it alone is the safe direction.
    private func hasSettled(_ snapshot: CableFileSnapshot) -> Bool {
        guard let modified = snapshot.modificationDate else { return false }
        return now().timeIntervalSince(modified) >= TimeInterval(minimumSettleAge.components.seconds)
    }

    private func looksLikeAudio(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 12) else { return false }
        return AudioDownloadValidation.looksLikeAudio(prefix)
    }

    /// Moves a successfully imported document's source out of the inbox and
    /// into the visible archive. Called *after* the store has the text, so a
    /// failure here leaves a file the next scan re-imports idempotently rather
    /// than one that is lost.
    private func archiveImported(_ sourceURL: URL) throws {
        try FileManager.default.createDirectory(
            at: importedURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(
            at: sourceURL,
            to: uniqueURL(for: sourceURL.lastPathComponent, in: importedURL)
        )
    }

    private func admitReaderDocument(
        at sourceURL: URL
    ) async -> (document: ReadingDocument?, failure: CableFileImportFailure?, rejected: Bool, duplicate: Bool) {
        switch await readerAdmission.admit(sourceURL) {
        case .imported(let document):
            do {
                try archiveImported(sourceURL)
                return (document, nil, false, false)
            } catch {
                return (document, CableFileImportFailure(
                    filename: sourceURL.lastPathComponent,
                    message: "Imported, but the file could not be moved to _Imported: \(error.localizedDescription)"
                ), false, false)
            }
        case .duplicate:
            return (nil, nil, false, true)
        case .rejected:
            return (nil, nil, true, false)
        case .failed(let message):
            return (nil, CableFileImportFailure(
                filename: sourceURL.lastPathComponent,
                message: message
            ), false, false)
        }
    }

    private func preserveForReview(_ sourceURL: URL, category: String) throws {
        let directory = reviewURL
            .appending(path: category, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(
            at: sourceURL,
            to: uniqueURL(for: sourceURL.lastPathComponent, in: directory)
        )
    }

    private func recordRejection(
        _ sourceURL: URL,
        category: String,
        result: inout CableFileImportResult
    ) {
        do {
            try preserveForReview(sourceURL, category: category)
            result.rejected.append(sourceURL.lastPathComponent)
        } catch {
            result.failures.append(CableFileImportFailure(
                filename: sourceURL.lastPathComponent,
                message: "Could not move the rejected file into Needs Review: \(error.localizedDescription)"
            ))
        }
    }

    private func uniqueURL(for filename: String, in directory: URL) -> URL {
        let original = directory.appending(path: filename)
        var candidate = original
        var counter = 1

        while FileManager.default.fileExists(atPath: candidate.path) {
            let base = original.deletingPathExtension().lastPathComponent
            let ext = original.pathExtension
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            candidate = directory.appending(path: "\(base) (\(counter))\(suffix)")
            counter += 1
        }
        return candidate
    }

    private func rollback(_ audioFile: AudioFile, to sourceURL: URL) {
        let storedURL = managedAudioURL.appending(path: audioFile.filename)
        do {
            try FileManager.default.createDirectory(
                at: sourceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: storedURL, to: sourceURL)
        } catch {
            // The managed copy is deliberately retained rather than deleted.
            // Losing a file is worse than leaving an orphan for recovery.
        }
    }
}

private nonisolated struct CableFileSnapshot: Sendable, Equatable {
    let url: URL
    let source: CableFileImportService.Source
    let byteCount: Int64
    let modificationDate: Date?
}
