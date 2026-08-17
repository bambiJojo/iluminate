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
}
