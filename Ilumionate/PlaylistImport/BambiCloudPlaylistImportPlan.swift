//
//  BambiCloudPlaylistImportPlan.swift
//  Ilumionate
//

import Foundation

/// A reviewable mapping from remote playlist tracks to audio already in the
/// user's library.
struct BambiCloudPlaylistImportPlan {
    struct Row: Identifiable {
        /// Raw type deliberately absent: `.possibleDuplicate` carries the
        /// library file it may duplicate, and `rawValue` had no readers.
        enum Status: Equatable {
            case exact
            case probable
            case needsReview
            case missing
            case manual
            case downloaded
            /// Strong but circumstantial evidence the user already has this.
            case possibleDuplicate(existing: AudioFile.ID)
        }

        /// Identity belongs to the position in the playlist, not the track: a
        /// playlist may legitimately list the same track more than once, and
        /// keying rows by track collapses those into one — SwiftUI renders
        /// undefined results and every per-row action hits only the first copy.
        let id = UUID()
        let track: BambiCloudPlaylist.Track
        var status: Status
        var selectedAudioFileID: AudioFile.ID?
        let suggestedAudioFileIDs: [AudioFile.ID]
    }

    let sourcePlaylist: BambiCloudPlaylist
    private(set) var availableAudioFiles: [AudioFile]
    var rows: [Row]

    /// Tracks the user could fill in by downloading the publisher's own copy.
    var downloadableRows: [Row] {
        rows.filter { $0.selectedAudioFileID == nil && $0.track.audioURL != nil }
    }

    var matchedCount: Int {
        rows.count { $0.selectedAudioFileID != nil }
    }

    var unresolvedCount: Int {
        rows.count - matchedCount
    }

    mutating func select(
        audioFileID: AudioFile.ID?,
        forRow rowID: Row.ID
    ) {
        guard audioFileID == nil
                || availableAudioFiles.contains(where: { $0.id == audioFileID })
        else {
            return
        }

        guard let index = rows.firstIndex(where: { $0.id == rowID }) else {
            return
        }
        let trackID = rows[index].track.id

        if let audioFileID {
            // One file must not stand in for two different tracks — but repeats
            // of the same track are meant to share it.
            for other in rows.indices
            where rows[other].selectedAudioFileID == audioFileID
                && rows[other].track.id != trackID {
                rows[other].selectedAudioFileID = nil
                rows[other].status = .needsReview
            }
        }

        rows[index].selectedAudioFileID = audioFileID
        rows[index].status = audioFileID == nil ? .missing : .manual
    }

    /// Marks a row filled from audio the library already held.
    ///
    /// `select` reports `.manual` because it is the user's own choice; a
    /// duplicate resolved automatically is an exact match, and reads as one.
    mutating func markResolvedAsExisting(rowID: Row.ID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }),
              rows[index].selectedAudioFileID != nil else {
            return
        }
        rows[index].status = .exact
    }

    /// Flags a row as probably already in the library, without acting on it.
    /// The user chooses between the existing file and a fresh download.
    mutating func markPossibleDuplicate(existing: AudioFile.ID, forRow rowID: Row.ID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].status = .possibleDuplicate(existing: existing)
    }

    /// Adds a freshly downloaded file to the library snapshot and assigns it to
    /// the row it was fetched for — and to any other unfilled row listing the
    /// same track, so a repeated track is not downloaded twice.
    mutating func adopt(
        downloadedFile: AudioFile,
        forRow rowID: Row.ID
    ) {
        if !availableAudioFiles.contains(where: { $0.id == downloadedFile.id }) {
            availableAudioFiles.append(downloadedFile)
        }

        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let trackID = rows[index].track.id

        for candidate in rows.indices
        where rows[candidate].track.id == trackID
            && (candidate == index || rows[candidate].selectedAudioFileID == nil) {
            rows[candidate].selectedAudioFileID = downloadedFile.id
            rows[candidate].status = .downloaded
        }
    }

    func makePlaylist() -> Playlist? {
        let filesByID = Dictionary(
            uniqueKeysWithValues: availableAudioFiles.map { ($0.id, $0) }
        )
        let items = rows.compactMap { row -> PlaylistItem? in
            guard let selectedID = row.selectedAudioFileID,
                  let audioFile = filesByID[selectedID] else {
                return nil
            }
            return PlaylistItem(
                audioFileId: audioFile.id,
                filename: audioFile.filename,
                duration: audioFile.duration
            )
        }
        guard !items.isEmpty else { return nil }

        return Playlist(
            name: sourcePlaylist.name,
            items: items,
            smartTransitions: true
        )
    }
}
