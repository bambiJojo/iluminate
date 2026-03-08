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
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                
                Group {
                    if playlists.isEmpty {
                        enhancedEmptyPlaylistsView
                    } else {
                        enhancedPlaylistsView
                    }
                }
            }
            .navigationTitle("Playlist Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        TranceHaptics.shared.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                            .foregroundStyle(.primary)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        TranceHaptics.shared.light()
                        createNewPlaylist()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                            .font(.title2)
                            .foregroundStyle(Color.bwTheta)
                            .shadow(
                                color: Color.bwTheta.opacity(0.3),
                                radius: 4
                            )
                    }
                    .accessibilityLabel("Create New Playlist")
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

    // MARK: - View Components

    private var enhancedEmptyPlaylistsView: some View {
        VStack(spacing: TranceSpacing.screen) {
            // Enhanced Master Orb inspired playlist icon
            ZStack {
                // Outer breathing ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.lavender.opacity(0.6),
                                Color.roseDeep.opacity(0.8),
                                Color.warmAccent.opacity(0.4),
                                Color.lavender.opacity(0.6)
                            ],
                            center: .center
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 140, height: 140)

                // Inner pulsing background
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.roseGold.opacity(0.4),
                                Color.lavender.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 120, height: 120)

                // Central playlist icons with staggered animation
                ZStack {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: ["music.note.list", "waveform", "sparkles"][index])
                            .font(.system(size: CGFloat([40, 32, 24][index]), weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color.bwGamma,
                                        Color.roseDeep
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .offset(
                                x: CGFloat([0, 20, -15][index]),
                                y: CGFloat([0, -10, 15][index])
                            )
                            .opacity(1.0 - Double(index) * 0.25)
                    }
                }
            }

            // Enhanced typography section
            VStack(spacing: TranceSpacing.card) {
                Text("Your Playlist Library")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(.primary)

                VStack(spacing: TranceSpacing.list) {
                    Text("Create curated journeys from your")
                        .font(TranceTypography.body)
                        .foregroundStyle(.secondary)

                    Text("audio sessions and light experiences")
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.bwGamma)
                        .fontWeight(.semibold)
                }
                .multilineTextAlignment(.center)
            }

            // Enhanced create button
            VStack(spacing: TranceSpacing.card) {
                Button {
                    TranceHaptics.shared.medium()
                    createNewPlaylist()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 32, height: 32)

                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create Your First Playlist")
                                .font(TranceTypography.body)
                                .foregroundStyle(.white)

                            Text("Sequence sessions for deeper journeys")
                                .font(TranceTypography.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, TranceSpacing.cardMargin)
                    .padding(.vertical, TranceSpacing.card)
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.horizontal, TranceSpacing.cardMargin)

                // Helpful tips
                HStack(spacing: TranceSpacing.list) {
                    Image(systemName: "lightbulb.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.roseDeep)
                        .font(.caption)

                    Text("Playlists can crossfade between sessions for seamless experiences")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, TranceSpacing.cardMargin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var enhancedPlaylistsView: some View {
        ScrollView {
            LazyVStack(spacing: TranceSpacing.card) {
                // Header section with stats
                playlistStatsHeader
                    .padding(.horizontal, TranceSpacing.card)
                    .padding(.top, TranceSpacing.list)

                // Enhanced playlist cards
                ForEach(playlists) { playlist in
                    EnhancedPlaylistCard(
                        playlist: playlist,
                        onPlay: {
                            TranceHaptics.shared.medium()
                            playPlaylist(playlist)
                        },
                        onEdit: {
                            TranceHaptics.shared.light()
                            editPlaylist(playlist)
                        },
                        onDelete: {
                            TranceHaptics.shared.medium()
                            if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
                                deletePlaylists(at: IndexSet(integer: index))
                            }
                        }
                    )
                    .padding(.horizontal, TranceSpacing.card)
                }

                // Bottom spacing
                Spacer(minLength: TranceSpacing.screen)
            }
            .padding(.vertical, TranceSpacing.list)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Playlist Stats Header

    private var playlistStatsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Collection")
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(.primary)

                HStack(spacing: 16) {
                    Label("\(playlists.count) playlists", systemImage: "music.note.list")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.secondary)

                    let totalTracks = playlists.reduce(0) { $0 + $1.itemCount }
                    if totalTracks > 0 {
                        Label("\(totalTracks) tracks", systemImage: "waveform")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.roseDeep)
                    }
                }
            }

            Spacer()

            // Quick stats with beautiful styling
            VStack(alignment: .trailing, spacing: 2) {
                let totalDuration = playlists.reduce(0.0) { $0 + $1.totalDuration }
                let hours = Int(totalDuration) / 3600
                let minutes = Int(totalDuration) % 3600 / 60

                Text("\(hours)h \(minutes)m")
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(Color.bwGamma)

                Text("Total time")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, TranceSpacing.card)
        .padding(.vertical, TranceSpacing.card)
        .background(
            RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                .fill(Color.white.opacity(0.8))
                .shadow(
                    color: Color.roseGold.opacity(0.3),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
    }
}

// MARK: - Enhanced Playlist Card

struct EnhancedPlaylistCard: View {
    let playlist: Playlist
    var onPlay: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var showingDeleteAlert = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Playlist info
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        Label("\(playlist.itemCount) tracks", systemImage: "music.note")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.secondary)

                        Label(playlist.totalDurationFormatted, systemImage: "clock")
                            .font(TranceTypography.caption)
                            .foregroundStyle(.secondary)

                        if playlist.smartTransitions {
                            Label("Crossfade", systemImage: "arrow.trianglehead.merge")
                                .font(TranceTypography.caption)
                                .foregroundStyle(Color.roseDeep)
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
                            .symbolRenderingMode(.hierarchical)
                            .font(.title)
                            .foregroundStyle(Color.bwGamma)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Action buttons
            HStack(spacing: 10) {
                Button("Edit") {
                    onEdit()
                }
                .buttonStyle(GlassButtonStyle())
                .frame(maxWidth: .infinity)

                if !playlist.isEmpty {
                    Button("Play") {
                        onPlay()
                    }
                    .buttonStyle(GlassButtonStyle())
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, TranceSpacing.list)
        .background(Color.white.opacity(0.7))
        .cornerRadius(TranceRadius.thumbnail)
    }
}
