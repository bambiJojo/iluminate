//
//  PlayerTrackListSheet.swift
//  Ilumionate
//
//  Playlist track list sheet for the unified player.
//

import SwiftUI

struct PlayerTrackListSheet: View {
    let viewModel: UnifiedPlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.playlistItems.enumerated(), id: \.element.id) { index, item in
                    Button {
                        dismiss()
                        Task { await viewModel.jumpToTrack(at: index) }
                    } label: {
                        HStack {
                            if index == viewModel.currentTrackIndex {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(.blue)
                                    .frame(width: 24)
                            } else {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.filename)
                                    .font(.body)
                                    .foregroundStyle(index == viewModel.currentTrackIndex ? .blue : .primary)
                                    .lineLimit(1)

                                Text(item.durationFormatted)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if index == viewModel.currentTrackIndex {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.blue)
                                    .symbolEffect(.variableColor.iterative)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
