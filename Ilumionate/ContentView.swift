//
//  ContentView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import SwiftUI

struct ContentView: View {
    // MARK: - State Management (Trance navigation system)
    @State private var selectedTab: TranceTab = .home
    @State private var engine = LightEngine()
    @State private var sessions: [LightSession] = []
    @State private var selectedSession: LightSession?
    @State private var showingAudioLibrary = false
    @State private var showingSessionPlayer = false
    @State private var showingSettings = false
    @State private var showingOnboarding = false
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            Group {
                switch selectedTab {
                case .home:
                    NavigationStack {
                        HomeView(
                            showingAudioLibrary: $showingAudioLibrary,
                            showingSessionPlayer: $showingSessionPlayer,
                            selectedSession: $selectedSession,
                            sessions: sessions,
                            onRefresh: loadSessions
                        )
                        .navigationTitle("Home")
                        .navigationBarTitleDisplayMode(.inline)
                    }

                case .library:
                    NavigationStack {
                        AudioLibraryView(engine: engine)
                            .navigationTitle("Library")
                            .navigationBarTitleDisplayMode(.large)
                    }

                case .machine:
                    NavigationStack {
                        MindMachineView()
                    }
                    
                case .playlists:
                    // Playlist library relies on engine to launch playlist sessions
                    PlaylistLibraryView(engine: engine)

                case .store:
                    NavigationStack {
                        // Store view (placeholder for now)
                        VStack {
                            Text("Store")
                                .font(TranceTypography.screenTitle)
                                .foregroundColor(.textPrimary)
                            Text("Coming soon...")
                                .font(TranceTypography.body)
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bgPrimary)
                        .navigationTitle("Store")
                        .navigationBarTitleDisplayMode(.large)
                    }

                case .profile:
                    NavigationStack {
                        SettingsView()
                            .navigationTitle("Profile")
                            .navigationBarTitleDisplayMode(.large)
                    }
                }
            }

            // Tab bar
            TranceTabBar(selected: $selectedTab)
        }
        .onAppear {
            loadSessions()
            checkForFirstLaunch()
        }
        .fullScreenCover(isPresented: $showingSessionPlayer) {
            if let session = selectedSession {
                SessionPlayerView(session: session, engine: engine)
            }
        }
        .sheet(isPresented: $showingAudioLibrary) {
            AudioLibraryView(engine: engine)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView()
        }
    }

    // MARK: - Actions

    private func loadSessions() {
        isLoading = true
        sessions = []

        // Simulate loading delay for smoother UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let sessionNames = LightScoreReader.discoverBundledSessions()

            for name in sessionNames {
                do {
                    let session = try LightScoreReader.loadSession(named: name)
                    sessions.append(session)
                } catch {
                    print("❌ Failed to load session '\(name)': \(error)")
                }
            }

            isLoading = false
        }
    }

    private func checkForFirstLaunch() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            // Delay slightly to ensure the main view has loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                showingOnboarding = true
            }
        }
    }
}

#Preview {
    ContentView()
}
