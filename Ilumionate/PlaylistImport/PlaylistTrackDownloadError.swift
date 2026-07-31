//
//  PlaylistTrackDownloadError.swift
//  Ilumionate
//

import Foundation

nonisolated enum PlaylistTrackDownloadError: LocalizedError, Equatable, Sendable {
    case noSourceAvailable
    case unsupportedSource
    /// Not a refusal — the file is big enough that the user should decide.
    case confirmationRequired(byteCount: Int64)
    case networkUnavailable
    case couldNotSave

    var errorDescription: String? {
        switch self {
        case .noSourceAvailable:
            "This track does not publish a file to download."
        case .unsupportedSource:
            "This track's file is hosted somewhere the app will not download from."
        case .confirmationRequired(let byteCount):
            "This track is \(Self.formatted(byteCount)). Confirm the download to continue."
        case .networkUnavailable:
            "The download failed. Check your connection and try again."
        case .couldNotSave:
            "The track downloaded but could not be saved to your library."
        }
    }

    static func formatted(_ byteCount: Int64) -> String {
        byteCount.formatted(.byteCount(style: .file))
    }
}
