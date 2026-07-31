//
//  PendingLargeDownload.swift
//  Ilumionate
//

import Foundation

/// A download held back until the user confirms the size, either a single
/// oversized track or a whole batch.
struct PendingLargeDownload: Identifiable {
    enum Scope {
        /// Carries the row it came from, so a repeated track resolves back to
        /// the exact row the user tapped.
        case row(id: UUID, name: String)
        case allMissing(trackCount: Int)
    }

    let id = UUID()
    let scope: Scope
    /// Nil when the server did not report a size.
    let byteCount: Int64?

    var title: String {
        switch scope {
        case .row(_, let name): name
        case .allMissing(let trackCount): "Download \(trackCount) Tracks"
        }
    }

    var message: String {
        let size = byteCount.map(PlaylistTrackDownloadError.formatted)

        switch scope {
        case .row:
            if let size {
                return "This track is \(size). Download it to your library?"
            }
            return "The size of this track is unknown. Download it to your library?"
        case .allMissing(let trackCount):
            if let size {
                return "Downloading \(trackCount) tracks will use about \(size). Continue?"
            }
            return "Download \(trackCount) tracks to your library?"
        }
    }
}
