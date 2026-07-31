//
//  LocalAudioMatchPicker.swift
//  Ilumionate
//

import SwiftUI

struct LocalAudioMatchPicker: View {
    let track: BambiCloudPlaylist.Track
    let audioFiles: [AudioFile]
    let suggestedAudioFileIDs: [AudioFile.ID]
    let selectedAudioFileID: AudioFile.ID?
    let onSelect: (AudioFile.ID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Button(
                    "Leave Unmatched",
                    systemImage: selectedAudioFileID == nil
                        ? "checkmark.circle.fill"
                        : "circle",
                    action: clearSelection
                )
                .foregroundStyle(.textSecondary)

                if filteredFiles.isEmpty {
                    Group {
                        if searchText.isEmpty {
                            ContentUnavailableView(
                                "No Local Audio",
                                systemImage: "waveform.slash",
                                description: Text("Add audio to your library to match this track.")
                            )
                        } else {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredFiles) { audioFile in
                        Button {
                            select(audioFile)
                        } label: {
                            LocalAudioMatchPickerRow(
                                audioFile: audioFile,
                                isSuggested: suggestedAudioFileIDs.contains(audioFile.id),
                                isSelected: selectedAudioFileID == audioFile.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .platformInsetGroupedListStyle()
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary)
            .navigationTitle(track.name)
            .platformInlineNavigationTitle()
            .searchable(text: $searchText, prompt: "Search local audio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private var filteredFiles: [AudioFile] {
        let matching = if searchText.isEmpty {
            audioFiles
        } else {
            audioFiles.filter {
                $0.displayName.localizedStandardContains(searchText)
                    || $0.filename.localizedStandardContains(searchText)
            }
        }

        let suggestedOrder = Dictionary(
            uniqueKeysWithValues: suggestedAudioFileIDs.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        return matching.sorted { lhs, rhs in
            let lhsRank = suggestedOrder[lhs.id] ?? Int.max
            let rhsRank = suggestedOrder[rhs.id] ?? Int.max
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName)
                == .orderedAscending
        }
    }

    private func select(_ audioFile: AudioFile) {
        onSelect(audioFile.id)
        dismiss()
    }

    private func clearSelection() {
        onSelect(nil)
        dismiss()
    }
}
