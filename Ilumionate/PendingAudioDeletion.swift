//
//  PendingAudioDeletion.swift
//  Ilumionate
//
//  Holds just-deleted audio files in a staging directory so a delete can be
//  undone. Staging lives outside Documents on purpose: AudioLibraryStore scans
//  Documents on every load and re-registers anything it finds there, so a file
//  left in place during the undo window would reappear in the library.
//

import Foundation
import os

/// One file held for possible undo, with everything needed to put it back.
struct StagedAudioFile: Sendable, Identifiable {
    let file: AudioFile
    /// Recorded rather than recomputed. `AudioFile.url` derives from `filename`,
    /// and training/migration flows store absolute paths pointing outside
    /// Documents — recomputing would restore some files to the wrong place.
    let originalURL: URL
    /// Index in `audioFiles` before removal, so undo restores order, not just presence.
    let originalIndex: Int

    var id: AudioFile.ID { file.id }
}

@MainActor
@Observable
final class PendingAudioDeletion {
    static let shared = PendingAudioDeletion()

    /// The batch currently held for undo. Empty means nothing is pending.
    private(set) var staged: [StagedAudioFile] = []

    private let stagingRoot: URL
    private let fileManager: FileManager
    private let deleteGeneratedSession: @MainActor (AudioFile) -> Void

    init(
        stagingRoot: URL = URL.applicationSupportDirectory
            .appending(path: "PendingAudioDeletion", directoryHint: .isDirectory),
        fileManager: FileManager = .default,
        deleteGeneratedSession: @escaping @MainActor (AudioFile) -> Void = {
            GeneratedSessionStore.shared.delete(for: $0)
        }
    ) {
        self.stagingRoot = stagingRoot
        self.fileManager = fileManager
        self.deleteGeneratedSession = deleteGeneratedSession
    }

    // MARK: - Staging

    /// Moves each file into staging. Any previously staged batch is committed
    /// first — only one batch is ever recoverable.
    ///
    /// - Returns: the entries that actually moved. A file that could not be
    ///   staged must stay in the library; dropping its row while the file
    ///   survives in Documents would resurrect it on the next library scan.
    @discardableResult
    func stage(_ entries: [StagedAudioFile]) -> [StagedAudioFile] {
        commit()

        var succeeded: [StagedAudioFile] = []
        for entry in entries {
            let folder = folderURL(for: entry)
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appending(path: entry.originalURL.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: entry.originalURL, to: destination)
                succeeded.append(entry)
            } catch {
                try? fileManager.removeItem(at: folder)
                Log.audio.error(
                    "Could not stage \(entry.file.filename, privacy: .public) for deletion: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        staged = succeeded
        return succeeded
    }

    // MARK: - Undo

    /// Moves every staged file back to its original location.
    ///
    /// - Returns: the entries that came back, ascending by `originalIndex` so a
    ///   caller can re-insert them in order. A file that failed to move back is
    ///   omitted — re-inserting a row whose file is gone yields a library entry
    ///   that cannot play.
    @discardableResult
    func restore() -> [StagedAudioFile] {
        var recovered: [StagedAudioFile] = []
        for entry in staged {
            let source = folderURL(for: entry).appending(path: entry.originalURL.lastPathComponent)
            do {
                try fileManager.createDirectory(
                    at: entry.originalURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: source, to: entry.originalURL)
                recovered.append(entry)
            } catch {
                Log.audio.error(
                    "Could not restore \(entry.file.filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            try? fileManager.removeItem(at: folderURL(for: entry))
        }

        staged = []
        return recovered.sorted { $0.originalIndex < $1.originalIndex }
    }

    // MARK: - Commit

    /// Destroys the staged batch for real: the staged copies and each file's
    /// generated light session. Called by the undo timer, banner dismissal,
    /// the library disappearing, or the next `stage(_:)`.
    func commit() {
        guard !staged.isEmpty else { return }

        for entry in staged {
            do {
                try fileManager.removeItem(at: folderURL(for: entry))
            } catch {
                // sweepOrphans() reclaims this at next launch.
                Log.audio.error(
                    "Could not remove staged \(entry.file.filename, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
            deleteGeneratedSession(entry.file)
            Log.audio.info("🗑 Deleted: \(entry.file.filename, privacy: .public)")
        }

        staged = []
    }

    // MARK: - Helpers

    /// One folder per file ID, so two files sharing a last path component
    /// cannot collide in staging.
    private func folderURL(for entry: StagedAudioFile) -> URL {
        stagingRoot.appending(path: entry.file.id.uuidString, directoryHint: .isDirectory)
    }
}
