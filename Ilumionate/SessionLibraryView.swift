//
//  SessionLibraryView.swift
//  Ilumionate
//
//  Session Library in Trance Design System
//

import SwiftUI

struct SessionLibraryView: View {
    var engine: LightEngine
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [LightSession] = []
    @State private var selectedSession: LightSession?
    @State private var showingSessionPlayer = false
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary
                    .ignoresSafeArea()

                if sessions.isEmpty {
                    emptyView
                } else {
                    sessionListView
                }
            }
            .navigationTitle("Session Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .onAppear {
                loadSessions()
            }
            .fullScreenCover(item: $selectedSession) { session in
                SessionPlayerView(session: session, engine: engine)
            }
            .fullScreenCover(isPresented: $showingSessionPlayer) {
                if let session = selectedSession {
                    SessionPlayerView(session: session, engine: engine)
                }
            }
            .searchable(text: $searchText, prompt: "Search sessions...")
        }
    }

    // MARK: - Subviews

    private var emptyView: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.lavender)

            Text("No Sessions Found")
                .font(TranceTypography.screenTitle)
                .foregroundColor(.textPrimary)

            Text("Try importing audio or using built-in sessions.")
                .font(TranceTypography.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var sessionListView: some View {
        ScrollView {
            LazyVStack(spacing: TranceSpacing.cardMargin) {
                ForEach(filteredSessions) { session in
                    Button {
                        selectedSession = session
                        showingSessionPlayer = true
                    } label: {
                        SessionListCard(session: session)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.vertical, TranceSpacing.cardMargin)
        }
    }

    // MARK: - Computed

    private var filteredSessions: [LightSession] {
        if searchText.isEmpty {
            return sessions
        }
        return sessions.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Loading

    private func loadSessions() {
        sessions = []
        let sessionNames = LightScoreReader.discoverBundledSessions()

        for name in sessionNames {
            do {
                let session = try LightScoreReader.loadSession(named: name)
                sessions.append(session)
            } catch {
                print("Failed to load session '\(name)': \(error)")
            }
        }
    }
}

// MARK: - Components

struct SessionListCard: View {
    let session: LightSession

    var body: some View {
        GlassCard {
            HStack(spacing: TranceSpacing.list) {
                // Thumbnail
                RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                    .fill(
                        LinearGradient(
                            colors: [sessionColor, sessionColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: sessionIcon)
                            .foregroundColor(.white)
                            .font(.system(size: 24))
                    )

                // Info
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(session.displayName)
                        .font(TranceTypography.sectionTitle)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: TranceSpacing.list) {
                        Label(session.durationFormatted, systemImage: "clock")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)

                        Label("\(session.light_score.count) frames", systemImage: "waveform")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(sessionColor)
            }
            .padding(.vertical, TranceSpacing.inner)
        }
    }

    private var sessionColor: Color {
        let name = session.displayName.lowercased()
        if name.contains("relax") || name.contains("sleep") { return .bwDelta }
        if name.contains("focus") { return .bwAlpha }
        if name.contains("energy") { return .bwBeta }
        if name.contains("trance") || name.contains("hypnosis") { return .bwTheta }
        return .roseGold
    }

    private var sessionIcon: String {
        let name = session.displayName.lowercased()
        if name.contains("relax") || name.contains("sleep") { return "moon.fill" }
        if name.contains("focus") { return "target" }
        if name.contains("energy") { return "bolt.fill" }
        if name.contains("trance") || name.contains("hypnosis") { return "sparkles" }
        return "play.fill"
    }
}
