//
//  PlaylistTrackBinding.swift
//  Ilumionate
//
//  Resolving a playlist item back to the library entry it stands for.
//
//  A `PlaylistItem` records only `audioFileId`, so a playlist is tied to the
//  library by UUID alone — and that identity is less stable than it looks. A
//  stored `AudioFile` that fails to decode is dropped by `AudioLibraryStore`,
//  and the next repairing load rediscovers the same audio sitting in Documents
//  and registers it under a **new** UUID. Re-importing a track does the same.
//
//  The Library then shows a healthy entry the listener can analyze, while every
//  playlist still pointing at the retired UUID resolves to nothing: the track
//  renders with the unknown-content tint (which is the same teal as `.music`,
//  so it reads as "not analyzed"), and Whole Journey stays disabled with no way
//  to tell which track is at fault.
//
//  Falling back to the filename re-attaches those orphaned items.
//

import Foundation

nonisolated enum PlaylistTrackBinding {

    /// The library entry an item stands for: the id it recorded while that still
    /// exists, otherwise whichever entry holds the same audio file.
    static func resolve(_ item: PlaylistItem, in audioFiles: [AudioFile]) -> AudioFile? {
        if let byIdentifier = audioFiles.first(where: { $0.id == item.audioFileId }) {
            return byIdentifier
        }

        let key = normalizedName(item.filename)
        guard key.isEmpty == false else { return nil }

        let candidates = audioFiles.filter { normalizedName($0.filename) == key }
        // A retired entry can outlive its replacement in the stored list.
        // Healing to the copy without analysis would leave the track looking
        // unanalyzed, which is the whole failure this exists to end.
        return candidates.first(where: \.isAnalyzed) ?? candidates.first
    }

    /// Items re-pointed at the entries they resolve to, so a healed link is
    /// persisted the next time the playlist is saved.
    ///
    /// The item keeps its own `id`, filename and duration — only the library
    /// reference moves, so ordering, artwork and the timeline are untouched.
    ///
    /// - Parameter remapping: retired identifier → surviving identifier, as
    ///   produced by a duplicate merge. Applied before resolution, because the
    ///   retired entry is already gone from `audioFiles` and would otherwise
    ///   fall through to the filename heuristic.
    static func rebinding(
        _ items: [PlaylistItem],
        to audioFiles: [AudioFile],
        remapping: [UUID: UUID] = [:]
    ) -> [PlaylistItem] {
        items.map { item in
            let remapped = remapping[item.audioFileId] ?? item.audioFileId
            let probe = remapped == item.audioFileId
                ? item
                : PlaylistItem(
                    id: item.id,
                    audioFileId: remapped,
                    filename: item.filename,
                    duration: item.duration
                )

            guard let file = resolve(probe, in: audioFiles),
                  file.id != item.audioFileId else {
                return probe
            }
            return PlaylistItem(
                id: item.id,
                audioFileId: file.id,
                filename: item.filename,
                duration: item.duration
            )
        }
    }

    /// Library entries keyed for repeated lookups, without matching cost per row.
    static func resolvedFiles(
        for items: [PlaylistItem],
        in audioFiles: [AudioFile]
    ) -> [UUID: AudioFile] {
        items.reduce(into: [:]) { resolved, item in
            resolved[item.id] = resolve(item, in: audioFiles)
        }
    }

    private static func normalizedName(_ filename: String) -> String {
        URL(filePath: filename).lastPathComponent.lowercased()
    }
}
