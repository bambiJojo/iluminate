//
//  BambiCloudPlaylistClient.swift
//  Ilumionate
//

import Foundation

/// Loads the public metadata for a user-supplied BambiCloud playlist link.
///
/// This client never requests or downloads the audio URLs included in the
/// service response.
nonisolated struct BambiCloudPlaylistClient: Sendable {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private static let maximumResponseBytes = 2_000_000
    private let load: Loader

    init(session: URLSession = .shared) {
        load = { request in
            try await session.data(for: request)
        }
    }

    init(_ load: @escaping Loader) {
        self.load = load
    }

    func fetchPlaylist(from rawLink: String) async throws -> BambiCloudPlaylist {
        let link = try BambiCloudPlaylistLink(rawLink)
        var request = URLRequest(
            url: link.apiURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await load(request)
        } catch let error as PlaylistLinkImportError {
            throw error
        } catch {
            throw PlaylistLinkImportError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlaylistLinkImportError.invalidResponse
        }
        if httpResponse.statusCode == 404 {
            throw PlaylistLinkImportError.playlistNotFound
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PlaylistLinkImportError.networkUnavailable
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw PlaylistLinkImportError.responseTooLarge
        }

        return try BambiCloudPlaylist.decode(
            from: data,
            expectedID: link.playlistID
        )
    }
}
