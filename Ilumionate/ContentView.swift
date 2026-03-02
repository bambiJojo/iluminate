//
//  ContentView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import SwiftUI

struct ContentView: View {

    @State private var engine = LightEngine()
    @State private var sessions: [LightSession] = []
    @State private var selectedSession: LightSession?
    @State private var showingAudioLibrary = false
    @State private var showingPlaylists = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions Found",
                        systemImage: "waveform.circle",
                        description: Text("Add JSON session files to your app bundle.\n\nMake sure they have target membership enabled.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            // Custom Audio Session Card
                            CreateCustomSessionCard()
                                .onTapGesture {
                                    showingAudioLibrary = true
                                }

                            // Playlists Card
                            PlaylistsCard()
                                .onTapGesture {
                                    showingPlaylists = true
                                }

                            // Pre-programmed sessions
                            ForEach(sessions) { session in
                                SessionCardView(session: session)
                                    .onTapGesture {
                                        print("🎯 Tapped session: \(session.displayName)")
                                        selectedSession = session
                                        print("✅ Set selectedSession to: \(session.displayName)")
                                    }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAudioLibrary = true
                    } label: {
                        Label("Create Session", systemImage: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .onAppear {
                loadSessions()
            }
        }
        .fullScreenCover(item: $selectedSession) { session in
            SessionPlayerView(session: session, engine: engine)
                .onAppear { print("📺 fullScreenCover is presenting session: \(session.displayName)") }
        }
        .sheet(isPresented: $showingAudioLibrary) {
            AudioLibraryView(engine: engine)
        }
        .sheet(isPresented: $showingPlaylists) {
            PlaylistLibraryView(engine: engine)
        }
    }

    private func loadSessions() {
        sessions = []

        print("🔍 Discovering bundled sessions...")
        let sessionNames = LightScoreReader.discoverBundledSessions()
        print("📦 Found \(sessionNames.count) session files: \(sessionNames)")

        for name in sessionNames {
            do {
                print("📖 Loading session: \(name)")
                let session = try LightScoreReader.loadSession(named: name)
                sessions.append(session)
                print("✅ Loaded: \(session.displayName)")
            } catch {
                print("❌ Failed to load session '\(name)': \(error)")
            }
        }

        print("🎉 Successfully loaded \(sessions.count) sessions")
    }
}

// MARK: - Session Card View

struct SessionCardView: View {
    let session: LightSession

    var body: some View {
        VStack(spacing: 0) {
            // Icon area
            ZStack {
                // Background gradient based on session type
                backgroundGradient
                    .ignoresSafeArea()

                // Icon
                Image(systemName: sessionIcon)
                    .font(.system(size: 50))
                    .foregroundStyle(.white)
            }
            .frame(height: 120)

            // Info area
            VStack(alignment: .leading, spacing: 8) {
                Text(session.displayName)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack {
                    Label(session.durationFormatted, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Label("\(session.light_score.count)", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Session Styling

    private var backgroundGradient: LinearGradient {
        let name = session.displayName.lowercased()

        if name.contains("relax") || name.contains("wind") || name.contains("sleep") {
            // Relaxation - Deep blues and purples
            return LinearGradient(
                colors: [Color(red: 0.2, green: 0.3, blue: 0.6), Color(red: 0.4, green: 0.2, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if name.contains("focus") || name.contains("trance") || name.contains("concentration") {
            // Focus - Teals and greens
            return LinearGradient(
                colors: [Color(red: 0.2, green: 0.5, blue: 0.6), Color(red: 0.3, green: 0.6, blue: 0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if name.contains("energy") || name.contains("morning") || name.contains("wake") {
            // Energy - Oranges and yellows
            return LinearGradient(
                colors: [Color(red: 0.9, green: 0.5, blue: 0.2), Color(red: 0.95, green: 0.7, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if name.contains("bilateral") || name.contains("wave") {
            // Bilateral - Purples and pinks
            return LinearGradient(
                colors: [Color(red: 0.6, green: 0.3, blue: 0.7), Color(red: 0.8, green: 0.3, blue: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if name.contains("hypnagogic") || name.contains("drift") || name.contains("theta") {
            // Deep states - Dark blues and indigos
            return LinearGradient(
                colors: [Color(red: 0.2, green: 0.2, blue: 0.5), Color(red: 0.3, green: 0.2, blue: 0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            // Default - Blues
            return LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var sessionIcon: String {
        let name = session.displayName.lowercased()

        if name.contains("relax") || name.contains("wind") {
            return "leaf.fill"
        } else if name.contains("sleep") || name.contains("hypnagogic") || name.contains("drift") {
            return "moon.stars.fill"
        } else if name.contains("focus") || name.contains("concentration") {
            return "scope"
        } else if name.contains("trance") {
            return "circle.hexagongrid.fill"
        } else if name.contains("energy") || name.contains("morning") || name.contains("wake") {
            return "sun.max.fill"
        } else if name.contains("bilateral") || name.contains("wave") {
            return "arrow.left.and.right"
        } else {
            return "waveform"
        }
    }
}

// MARK: - Create Custom Session Card

struct CreateCustomSessionCard: View {
    var body: some View {
        VStack(spacing: 0) {
            // Icon area with special gradient
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.3, green: 0.6, blue: 0.9),
                        Color(red: 0.5, green: 0.3, blue: 0.8)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

                    Text("Create Custom")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(height: 120)

            // Info area
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Audio Session")
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack {
                    Label("Upload Audio", systemImage: "mic.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Playlists Card

struct PlaylistsCard: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.6, green: 0.3, blue: 0.8),
                        Color(red: 0.4, green: 0.2, blue: 0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 50))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

                    Text("Playlists")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 8) {
                Text("Session Playlists")
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack {
                    Label("Sequential Play", systemImage: "list.number")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    ContentView()
}
