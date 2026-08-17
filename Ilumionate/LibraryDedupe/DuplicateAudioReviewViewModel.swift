//
//  DuplicateAudioReviewViewModel.swift
//  Ilumionate
//

import Foundation
import Observation

@MainActor
@Observable
final class DuplicateAudioReviewViewModel {

    /// The library as it would be after merging, and what has to leave disk.
    struct Resolution: Sendable {
        /// The whole library, with each merged group collapsed to its keeper.
        let audioFiles: [AudioFile]
        /// Keepers that changed, for logging and for the confirmation message.
        let merged: [AudioFile]
        /// Entries whose files must be staged for deletion.
        let removed: [AudioFile]
        /// Retired identifier → surviving identifier, for playlist rebinding.
        let remap: [AudioFile.ID: AudioFile.ID]
    }

    private(set) var groups: [DuplicateAudioGroup]
    private var deselected: Set<DuplicateAudioGroup.ID> = []

    private let audioFiles: [AudioFile]

    init(audioFiles: [AudioFile]) {
        self.audioFiles = audioFiles
        groups = DuplicateAudioGroup.groups(in: audioFiles)
    }

    var hasDuplicates: Bool { !groups.isEmpty }

    /// How many library rows would go away if the current selection is applied.
    var removableCount: Int {
        selectedGroups.reduce(0) { $0 + $1.redundant.count }
    }

    func isSelected(_ groupID: DuplicateAudioGroup.ID) -> Bool {
        !deselected.contains(groupID)
    }

    func setSelected(_ isSelected: Bool, groupID: DuplicateAudioGroup.ID) {
        if isSelected {
            deselected.remove(groupID)
        } else {
            deselected.insert(groupID)
        }
    }

    private var selectedGroups: [DuplicateAudioGroup] {
        groups.filter { isSelected($0.id) }
    }

    func resolution() -> Resolution {
        let selected = selectedGroups
        guard !selected.isEmpty else {
            return Resolution(audioFiles: audioFiles, merged: [], removed: [], remap: [:])
        }

        let mergedByKeeperID = Dictionary(
            uniqueKeysWithValues: selected.map { ($0.keeper.id, $0.merged()) }
        )
        let removedIDs = Set(selected.flatMap { $0.redundant.map(\.id) })

        let updated = audioFiles.compactMap { file -> AudioFile? in
            if removedIDs.contains(file.id) { return nil }
            return mergedByKeeperID[file.id] ?? file
        }

        return Resolution(
            audioFiles: updated,
            merged: Array(mergedByKeeperID.values),
            removed: selected.flatMap(\.redundant),
            remap: DuplicateAudioGroup.remap(for: selected)
        )
    }
}
