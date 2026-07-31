//
//  PlaylistLinkImportError.swift
//  Ilumionate
//

import Foundation

nonisolated enum PlaylistLinkImportError: LocalizedError, Equatable, Sendable {
    case invalidLink
    case unsupportedLink
    case invalidResponse
    case playlistNotFound
    case emptyPlaylist
    case responseTooLarge
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidLink:
            "Paste a complete playlist link and try again."
        case .unsupportedLink:
            "This playlist link is not supported."
        case .invalidResponse:
            "The playlist service returned information the app could not read."
        case .playlistNotFound:
            "This playlist could not be found or is not publicly available."
        case .emptyPlaylist:
            "This shared playlist does not contain any tracks."
        case .responseTooLarge:
            "The shared playlist is too large to import safely."
        case .networkUnavailable:
            "The playlist service is unavailable. Check your connection and try again."
        }
    }
}
