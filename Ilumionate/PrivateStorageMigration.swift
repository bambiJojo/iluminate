//
//  PrivateStorageMigration.swift
//  Ilumionate
//

import Foundation
import os

/// Moves private implementation data out of the Finder-visible Documents
/// directory without making a failed migration a data-loss event.
nonisolated enum PrivateStorageMigration {
    /// Returns the URL callers should use. The destination wins once present;
    /// otherwise the legacy item is moved after its parent directory exists.
    /// A failed move deliberately returns the legacy URL so the current build
    /// can continue using the only intact copy.
    static func migrateItemIfNeeded(
        from legacyURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        if fileManager.fileExists(atPath: destinationURL.path) {
            // Both exist. Returning the destination and walking away would leave
            // the legacy copy readable in Documents forever, which defeats the
            // point of migrating it. It is set aside rather than deleted —
            // losing data is worse than keeping an orphan. See ERRORS.md ERR-024.
            if fileManager.fileExists(atPath: legacyURL.path) {
                setAsideLegacyItem(at: legacyURL, near: destinationURL, fileManager: fileManager)
            }
            return destinationURL
        }
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return destinationURL
        }

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacyURL, to: destinationURL)
            Log.general.info(
                "Moved private app data out of Documents: \(legacyURL.lastPathComponent, privacy: .public)"
            )
            return destinationURL
        } catch {
            Log.general.error(
                "Could not move \(legacyURL.lastPathComponent, privacy: .public) out of Documents: \(error.localizedDescription, privacy: .public)"
            )
            return legacyURL
        }
    }

    /// Moves a superseded legacy item next to the destination under a
    /// non-colliding name, so it leaves Documents without being destroyed.
    ///
    /// A failure here is logged and swallowed: the caller already has a usable
    /// destination, and refusing to return it because cleanup failed would break
    /// a working app over a housekeeping problem.
    private static func setAsideLegacyItem(
        at legacyURL: URL,
        near destinationURL: URL,
        fileManager: FileManager
    ) {
        let directory = destinationURL.deletingLastPathComponent()
        let base = destinationURL.deletingPathExtension().lastPathComponent
        let ext = destinationURL.pathExtension
        let suffix = ext.isEmpty ? "" : ".\(ext)"

        var candidate = directory.appending(path: "\(base) (Recovered)\(suffix)")
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base) (Recovered \(counter))\(suffix)")
            counter += 1
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: legacyURL, to: candidate)
            Log.general.info(
                "Set aside a superseded copy of \(legacyURL.lastPathComponent, privacy: .public) that was still in Documents"
            )
        } catch {
            Log.general.error(
                "Could not clear the superseded \(legacyURL.lastPathComponent, privacy: .public) from Documents: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
