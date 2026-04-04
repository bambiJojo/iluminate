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
    @State private var audioFiles: [AudioFile] = []
    @State private var selectedSession: LightSession?
    @State private var showingAudioLibrary = false
    @State private var showingSessionPlayer = false
    @State private var showingOnboarding = false
    @State private var showingResumedPlayer = false
    @State private var isLoading = true
    @State private var showingAnalysisQueue = false
    @State private var nowPlaying = NowPlayingState.shared
    @State private var analysisManager = AnalysisStateManager.shared

    // Appearance — mirrors SettingsView's AppStorage key
    @AppStorage("appearanceMode") private var appearanceModeRaw = "system"

    // Synced to engine on appear and on change
    @AppStorage("userFrequencyMultiplier") private var userFrequencyMultiplierPref = 1.0

    private var preferredScheme: ColorScheme? {
        switch appearanceModeRaw {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content area — fills full screen; bottom padding reserves space for floating bar.
            // Using if/else-if inside a ZStack so SwiftUI sees the view being inserted/removed
            // and can apply the .transition crossfade during the animation.
            // ZStack + .animation drives the 0.25 s opacity crossfade whenever
            // selectedTab changes. Each branch carries .transition(.opacity) so
            // SwiftUI fades out the leaving view and fades in the arriving view.
            ZStack {
                if selectedTab == .home {
                    NavigationStack {
                        HomeView(
                            showingAudioLibrary: $showingAudioLibrary,
                            showingSessionPlayer: $showingSessionPlayer,
                            selectedSession: $selectedSession,
                            sessions: sessions,
                            audioFiles: audioFiles,
                            engine: engine,
                            onRefresh: loadSessions
                        )
                    }
                    .transition(.opacity)
                } else if selectedTab == .library {
                    // LibraryView owns its own NavigationStack
                    LibraryView(engine: engine)
                        .environment(FolderStore.shared)
                        .transition(.opacity)
                } else if selectedTab == .create {
                    NavigationStack {
                        MindMachineView(engine: engine, sessions: sessions)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: selectedTab)

            // Analysis overlay + Mini-player + tab bar stack
            VStack(spacing: TranceSpacing.inner) {
                if let analysis = analysisManager.currentAnalysis {
                    AnalysisStatusOverlay(
                        analysis: analysis,
                        queueCount: analysisManager.analysisQueue.count
                    ) {
                        showingAnalysisQueue = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if nowPlaying.isActive {
                    MiniPlayerBar(nowPlaying: nowPlaying) {
                        showingResumedPlayer = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                TranceTabBar(selected: $selectedTab)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: nowPlaying.isActive)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: analysisManager.currentAnalysis)
        }
        .onAppear {
            loadSessions()
            loadAudioFiles()
            checkForFirstLaunch()
            engine.userFrequencyMultiplier = userFrequencyMultiplierPref
        }
        .onChange(of: userFrequencyMultiplierPref) { _, newValue in
            engine.userFrequencyMultiplier = newValue
        }
        .fullScreenCover(item: $selectedSession) { session in
            UnifiedPlayerView(mode: .session(session: session, audioFile: nil), engine: engine)
        }
        .sheet(isPresented: $showingAudioLibrary) {
            AudioLibraryView(engine: engine)
        }
        .fullScreenCover(isPresented: $showingResumedPlayer) {
            if let resumedViewModel = nowPlaying.viewModel {
                UnifiedPlayerView(viewModel: resumedViewModel)
            } else if let mode = nowPlaying.currentMode, let playerEngine = nowPlaying.engine {
                UnifiedPlayerView(mode: mode, engine: playerEngine)
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $showingAnalysisQueue) {
            NavigationStack {
                AnalyzerView()
            }
        }
        .preferredColorScheme(preferredScheme)
    }

    // MARK: - Actions

    private func loadSessions() {
        isLoading = true
        let sessionNames = LightScoreReader.discoverBundledSessions()
        var loaded: [LightSession] = []
        for name in sessionNames {
            do {
                let session = try LightScoreReader.loadSession(named: name)
                loaded.append(session)
            } catch {
                print("❌ Failed to load session '\(name)': \(error)")
            }
        }
        sessions = loaded
        isLoading = false
    }

    private func loadAudioFiles() {
        // Read audio files from the same UserDefaults key AudioLibraryView uses
        if let data = UserDefaults.standard.data(forKey: "audioFiles"),
           let files = try? JSONDecoder().decode([AudioFile].self, from: data) {
            audioFiles = files
        }
    }

    private func checkForFirstLaunch() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            // Use modern async/await for better performance
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                await MainActor.run {
                    showingOnboarding = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
