//
//  PlaylistLibraryView.swift
//  Ilumionate
//
//  Browse, manage, and launch playlists
//

import SwiftUI

struct PlaylistLibraryView: View {

    let engine: LightEngine
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [Playlist] = []
    @State private var showingEditor = false
    @State private var editingPlaylist: Playlist?
    @State private var playingPlaylist: Playlist?

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    ContentUnavailableView {
                        Label("No Playlists", systemImage: "music.note.list")
                    } description: {
                        Text("Create a playlist to play multiple audio sessions in sequence.")
                    } actions: {
                        Button("Create Playlist") {
                            createNewPlaylist()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(playlists) { playlist in
                            PlaylistRow(playlist: playlist,
                                        onPlay: { playPlaylist(playlist) },
                                        onEdit: { editPlaylist(playlist) })
                        }
                        .onDelete(perform: deletePlaylists)
                    }
                }
            }
            .navigationTitle("Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createNewPlaylist()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                playlists = PlaylistStore.load()
            }
            .sheet(isPresented: $showingEditor) {
                if var playlist = editingPlaylist {
                    let isNew = !playlists.contains(where: { $0.id == playlist.id })
                    PlaylistEditorView(
                        playlist: Binding(
                            get: { playlist },
                            set: { playlist = $0 }
                        ),
                        isNew: isNew,
                        onSave: { saved in
                            savePlaylist(saved)
                        }
                    )
                }
            }
            .fullScreenCover(item: $playingPlaylist) { playlist in
                PlaylistPlayerView(playlist: playlist, engine: engine)
            }
        }
    }

    // MARK: - Actions

    private func createNewPlaylist() {
        editingPlaylist = Playlist(name: "")
        showingEditor = true
    }

    private func editPlaylist(_ playlist: Playlist) {
        editingPlaylist = playlist
        showingEditor = true
    }

    private func savePlaylist(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
        } else {
            playlists.append(playlist)
        }
        PlaylistStore.save(playlists)
    }

    private func deletePlaylists(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        PlaylistStore.save(playlists)
    }

    private func playPlaylist(_ playlist: Playlist) {
        guard !playlist.isEmpty else { return }
        playingPlaylist = playlist
    }
}

// MARK: - Playlist Row

struct PlaylistRow: View {
    let playlist: Playlist
    var onPlay: () -> Void
    var onEdit: () -> Void

    var body: some View {
        Button {
            onEdit()
        } label: {
            HStack(spacing: 12) {
                // Playlist info
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        Label("\(playlist.itemCount) tracks", systemImage: "music.note")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Label(playlist.totalDurationFormatted, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if playlist.smartTransitions {
                            Label("Crossfade", systemImage: "arrow.trianglehead.merge")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Spacer()

                // Play button
                if !playlist.isEmpty {
                    Button {
                        onPlay()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
