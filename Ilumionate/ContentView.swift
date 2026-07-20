//
//  ContentView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import SwiftUI
import os

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - State Management (Trance navigation system)
    @State private var selectedTab: TranceTab = .home
    @State private var engine = LightEngine()
    @State private var sessions: [LightSession] = []
    @State private var audioFiles: [AudioFile] = []
    @State private var selectedSession: LightSession?
    @State private var showingAudioLibrary = false
    @State private var showingSessionPlayer = false
    @State private var showingOnboarding = false
    @State private var showingAnalyticsConsentPrompt = false
    @State private var showingResumedPlayer = false
    @State private var isLoading = true
    @State private var showingAnalysisQueue = false
    @State private var readerSharedImportTrigger = 0
    @State private var readerQuickStartTrigger = 0
    @State private var nowPlaying = NowPlayingState.shared
    @State private var analysisManager = AnalysisStateManager.shared

    // Synced to engine on appear and on change
    @AppStorage("userFrequencyMultiplier") private var userFrequencyMultiplierPref = 1.0
    @AppStorage("appearanceMode") private var appearanceModeRaw = ThemeMode.system.rawValue

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
                            onRefresh: loadSessions,
                            onOpenReader: { selectedTab = .read }
                        )
                    }
                    .transition(.opacity)
                } else if selectedTab == .library {
                    // LibraryView owns its own NavigationStack
                    LibraryView(
                        engine: engine,
                        onContinueReading: {
                            selectedTab = .read
                            readerQuickStartTrigger += 1
                        }
                    )
                        .transition(.opacity)
                } else if selectedTab == .read {
                    TextTranceRootView(
                        sharedImportTrigger: readerSharedImportTrigger,
                        quickStartTrigger: readerQuickStartTrigger
                    )
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
                } else if let failure = analysisManager.failedAnalyses.last {
                    AnalysisRecoveryStatusOverlay(failure: failure) {
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
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: analysisManager.failedAnalyses.count)
        }
        .task {
            await analysisManager.restoreManualRecoveries()
            loadSessions()
            await loadAudioFiles()
            checkForFirstLaunch()
            checkForAnalyticsConsentPrompt()
            engine.userFrequencyMultiplier = userFrequencyMultiplierPref
            UsageAnalytics.shared.appBecameActive()
            UsageAnalytics.shared.screen(screen(for: selectedTab))
        }
        .onChange(of: userFrequencyMultiplierPref) { _, newValue in
            engine.userFrequencyMultiplier = newValue
        }
        .onChange(of: selectedTab) { _, newTab in
            UsageAnalytics.shared.screen(screen(for: newTab))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                UsageAnalytics.shared.appBecameActive()
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
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
                AnalyzerView(engine: engine)
            }
        }
        .alert("Help Improve LumeSync", isPresented: $showingAnalyticsConsentPrompt) {
            Button("Not Now", role: .cancel) {
                UsageAnalytics.shared.setEnabled(false)
            }
            Button("Share Anonymous Analytics") {
                UsageAnalytics.shared.setEnabled(true)
            }
        } message: {
            Text("Share anonymous usage analytics so we can understand what works, find problems, and improve the app. This never includes audio, transcripts, generated session text, imported documents, or reading-source URLs.")
        }
        .preferredColorScheme(ThemeMode(persisted: appearanceModeRaw).colorScheme)
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
                Log.ui.info("❌ Failed to load session '\(name)': \(error)")
            }
        }
        sessions = loaded
        isLoading = false
    }

    private func loadAudioFiles() async {
        audioFiles = await AudioLibraryStore.loadRepairingStoredFiles()
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

    private func checkForAnalyticsConsentPrompt() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard hasCompletedOnboarding, !UsageAnalytics.shared.hasAnsweredConsent else { return }

        Task {
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                showingAnalyticsConsentPrompt = true
            }
        }
    }

    private func screen(for tab: TranceTab) -> AnalyticsScreen {
        switch tab {
        case .home:    .home
        case .library: .library
        case .read:    .read
        case .create:  .create
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "ilumionate",
              url.host(percentEncoded: false) == "shared-import" else {
            return
        }
        selectedTab = .read
        readerSharedImportTrigger += 1
    }
}

#Preview {
    ContentView()
}
