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

    /// Namespaces a track identifier by publisher.
    ///
    /// Derived from the address rather than looked up in a table of known
    /// services: the app deliberately has no notion of which sites exist, and a
    /// user can import from any of them. Over-splitting is harmless — two
    /// namespaces for one publisher only means provenance stops corroborating a
    /// duplicate, and the content fingerprint still catches it.
    static func service(for url: URL) -> String {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
