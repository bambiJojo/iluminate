//
//  RemoteAudioSource.swift
//  Ilumionate
//
//  Where a library file came from, when it was fetched rather than imported.
//
//  Without this, a second playlist sharing tracks with the first has nothing to
//  match on but the track's title, and a title that fails the importer's
//  similarity threshold becomes a download the user already has.
//

import Foundation

nonisolated struct RemoteAudioSource: Codable, Sendable, Equatable {
    /// The publisher, so two services cannot collide on a track identifier.
    let service: String
    /// The publisher's own identifier for the track. Survives every rename.
    let trackID: String
    let url: URL

    static let bambiCloudService = "bambicloud"
}
