//
//  AudioLibraryStorage.swift
//  Ilumionate
//
//  Where the audio library lives on disk.
//
//  It used to live in `UserDefaults`, as one JSON value under the `audioFiles`
//  key. That worked until `AudioFile` began carrying a full transcript and a
//  complete `AnalysisResult`: iOS caps a single `UserDefaults` value at 4 MiB
//  and rejects anything larger. `UserDefaults.set(_:forKey:)` returns `Void`
//  and cannot report the rejection, so a library past the ceiling dropped every
//  write in silence — finished analyses, play counts, newly imported files.
//
//  A file has no such ceiling and can report a failed write. See ERRORS.md
//  ERR-005 for the device log that surfaced it.
//

import Foundation

/// `UserDefaults` is thread-safe but Foundation does not mark it `Sendable`.
/// It is only ever read here, once, to migrate a library written by an older
/// build.
nonisolated struct AudioLibraryStorage: @unchecked Sendable {
    let fileURL: URL
    /// The old store. `nil` disables migration, which is what tests covering
    /// the file path alone want.
    let legacyDefaults: UserDefaults?

    init(fileURL: URL, legacyDefaults: UserDefaults?) {
        self.fileURL = fileURL
        self.legacyDefaults = legacyDefaults
    }

    /// Application Support, matching `PendingAudioDeletion` and the analysis
    /// cache. Not `Documents`: `AudioLibraryStore` scans that directory for
    /// unregistered audio on every load, and a stray JSON file there is noise
    /// at best.
    static let standard = AudioLibraryStorage(
        fileURL: URL.applicationSupportDirectory
            .appending(path: "AudioLibrary", directoryHint: .isDirectory)
            .appending(path: "library.json"),
        legacyDefaults: .standard
    )
}
