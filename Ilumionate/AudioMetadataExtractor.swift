//
//  AudioMetadataExtractor.swift
//  Ilumionate
//

import AVFoundation
import Foundation

nonisolated enum AudioMetadataExtractor {
    @concurrent
    static func metadata(from url: URL) async -> AudioTrackMetadata? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }

        // AVMetadataItem is not Sendable, so the values must be loaded
        // sequentially instead of sharing the item array across child tasks.
        let title = await stringValue(for: .commonIdentifierTitle, in: items)
        let artist = await stringValue(for: .commonIdentifierArtist, in: items)
        let album = await stringValue(for: .commonIdentifierAlbumName, in: items)
        let genre = await stringValue(for: .commonIdentifierType, in: items)

        let metadata = AudioTrackMetadata(
            embeddedTitle: title,
            creator: artist,
            album: album,
            genre: genre
        )
        return metadata.isEmpty ? nil : metadata
    }

    private static func stringValue(
        for identifier: AVMetadataIdentifier,
        in items: [AVMetadataItem]
    ) async -> String? {
        guard let item = AVMetadataItem.metadataItems(
            from: items,
            filteredByIdentifier: identifier
        ).first else {
            return nil
        }

        return AudioTrackMetadata.cleaned(try? await item.load(.stringValue))
    }
}
