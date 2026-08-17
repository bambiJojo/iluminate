//
//  ContentView.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/7/26.
//

import SwiftUI
import os

enum AppNavigationPresentation: Equatable {
    case compactTabs
    case macSidebar
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    let navigationPresentation: AppNavigationPresentation

    // MARK: - State Management (Trance navigation system)
    @State private var selectedTab: TranceTab = .home
    @State private var engine = LightEngine()
    @State private var sessions: [LightSession] = []
    /// Observe the shared library snapshot directly. Keeping a second array in
    /// ContentView left the launch-time decode alive after Library refreshed
    /// the cache, retaining an entire duplicate set of transcript statistics.
    @State private var audioLibraryCache = AudioLibraryCache.shared
    @State private var selectedSession: LightSession?
    @State private var showingOnboarding = false
    @State private var showingAnalyticsConsentPrompt = false
    @State private var showingResumedPlayer = false
    @State private var isLoading = true
    @State private var showingAnalysisQueue = false
    @State private var readerSharedImportTrigger = 0
    @State private var readerQuickStartTrigger = 0
    @State private var createKindRequestToken = 0
    @State private var createRequestedKind: CreateSessionKind?
    @State private var nowPlaying = NowPlayingState.shared
    @State private var analysisManager = AnalysisStateManager.shared
    /// Single owner of the analysis task snapshot. Every analysis surface
    /// filters this one list; none rebuilds state of its own.
    @State private var analysisCenter = AnalysisCenterModel.live()

    // Synced to engine on appear and on change
    @AppStorage("userFrequencyMultiplier") private var userFrequencyMultiplierPref = 1.0
    @AppStorage("appearanceMode") private var appearanceModeRaw = ThemeMode.system.rawValue

    init(navigationPresentation: AppNavigationPresentation = .compactTabs) {
        self.navigationPresentation = navigationPresentation
    }

    var body: some View {
        mainLayout
        .environment(analysisCenter)
        .task {
            await analysisManager.prepareCachedResults()
            await analysisManager.restoreManualRecoveries()
            // Bootstrap ordering: recoveries and checkpoints are restored above,
            // so the first published snapshot already reflects them rather than
            // arriving empty and then correcting itself.
            analysisCenter.invalidateStructure()
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
                BackgroundAnalysisScheduler.shared.resumeWhenForegrounded()
            }
        }
        // Structural invalidation is driven by observing the state itself rather
        // than by calls placed in each mutating method. A new mutation site
        // cannot forget to notify, because there is nothing to remember.
        // Queue identity is mapped rather than counted so a reorder — which
        // changes every projected position — still invalidates.
        .onChange(of: analysisManager.analysisQueue.map(\.id)) { _, _ in
            analysisCenter.invalidateStructure()
        }
        .onChange(of: analysisManager.failedAnalyses.map(\.id)) { _, _ in
            analysisCenter.invalidateStructure()
        }
        .onChange(of: analysisManager.completedAnalyses.count) { _, _ in
            analysisCenter.invalidateStructure()
        }
        .onChange(of: analysisManager.partialResultsRevision) { _, _ in
            analysisCenter.invalidateStructure()
        }
        // The high-frequency path: progress only, never a disk read.
        .onChange(of: analysisManager.currentAnalysis?.snapshot) { _, snapshot in
            analysisCenter.updateProgress(active: snapshot, download: nil)
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .platformFullScreenCover(item: $selectedSession) { session in
            UnifiedPlayerView(mode: .session(session: session, audioFile: nil), engine: engine)
        }
        .platformFullScreenCover(isPresented: $showingResumedPlayer) {
            if let resumedViewModel = nowPlaying.viewModel {
                UnifiedPlayerView(viewModel: resumedViewModel)
            } else if let mode = nowPlaying.currentMode, let playerEngine = nowPlaying.engine {
                UnifiedPlayerView(mode: mode, engine: playerEngine)
            }
        }
        .platformFullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView()
        }
        .sheet(isPresented: $showingAnalysisQueue) {
            NavigationStack {
                AnalysisCenterView(engine: engine)
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

    @ViewBuilder
    private var mainLayout: some View {
        if navigationPresentation == .macSidebar {
            NavigationSplitView {
                List(selection: sidebarSelection) {
                    Section("LumeSync") {
                        ForEach(TranceTab.allCases, id: \.self) { tab in
                            Label(tab.title, systemImage: tab.sfSymbol)
                                .tag(tab)
                        }
                    }

                    #if os(macOS)
                    Section("Application") {
                        SettingsLink {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    #endif
                }
                .navigationTitle("LumeSync")
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            } detail: {
                ZStack(alignment: .bottom) {
                    featureContent
                    bottomChrome(showsTabBar: false)
                        .padding(TranceSpacing.inner)
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            ZStack(alignment: .bottom) {
                featureContent
                bottomChrome(showsTabBar: true)
            }
        }
    }

    private var sidebarSelection: Binding<TranceTab?> {
        Binding(
            get: { selectedTab },
            set: { if let newValue = $0 { selectedTab = newValue } }
        )
    }

    @ViewBuilder
    private var featureContent: some View {
        ZStack {
            if selectedTab == .home {
                NavigationStack {
                    HomeView(
                        selectedSession: $selectedSession,
                        sessions: sessions,
                        audioFiles: audioLibraryCache.files,
                        engine: engine,
                        onRefresh: loadSessions,
                        onOpenLibrary: { selectedTab = .library },
                        onOpenReader: { selectedTab = .read },
                        onOpenCreate: openCreate,
                        onOpenNowPlaying: { showingResumedPlayer = true },
                        onContinueReading: openReaderQuickStart
                    )
                }
            } else if selectedTab == .library {
                LibraryView(engine: engine, builtInSessions: sessions)
            } else if selectedTab == .read {
                TextTranceRootView(
                    sharedImportTrigger: readerSharedImportTrigger,
                    quickStartTrigger: readerQuickStartTrigger
                )
            } else if selectedTab == .create {
                NavigationStack {
                    CreateView(
                        engine: engine,
                        kindRequestToken: createKindRequestToken,
                        requestedKind: createRequestedKind
                    )
                }
            }
        }
    }

    /// Home carries its own "Current" section, so the floating bar there would
    /// put the same track on screen twice. Every other tab keeps it.
    private var showsMiniPlayer: Bool {
        nowPlaying.isActive && selectedTab != .home
    }

    private func bottomChrome(showsTabBar: Bool) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: TranceSpacing.inner) {
                // Measured so screens can reserve space for it — its height
                // grows with the stage/estimate/reassurance text.
                Group {
                    // One pill, showing active work and outstanding failures at
                    // the same time. The two overlays this replaces shared a
                    // slot, so a failure was invisible while anything ran.
                    if analysisCenter.activeTask != nil || analysisCenter.attentionCount > 0 {
                        AnalysisStatusPill(
                            activeTask: analysisCenter.activeTask,
                            queuedCount: analysisCenter.queuedCount,
                            attentionCount: analysisCenter.attentionCount
                        ) {
                            showingAnalysisQueue = true
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    BottomChromeMetrics.shared.analysisOverlayHeight = height
                }

                if showsMiniPlayer {
                    MiniPlayerBar(nowPlaying: nowPlaying) {
                        showingResumedPlayer = true
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if showsTabBar {
                    TranceTabBar(selected: $selectedTab)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showsMiniPlayer)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: analysisManager.currentAnalysis)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: analysisManager.failedAnalyses.count)
        }
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

    /// Publishes through the shared cache so Library can paint its shelves
    /// immediately on first entry instead of waiting for its own load.
    private func loadAudioFiles() async {
        await audioLibraryCache.refresh()
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

    /// Sends the user to Create with a segment preselected. The token is bumped
    /// so tapping the same home door twice re-applies the kind instead of being
    /// swallowed as a no-op.
    private func openCreate(_ kind: CreateSessionKind) {
        createRequestedKind = kind
        createKindRequestToken += 1
        selectedTab = .create
    }

    /// Sends the user to the reader and re-arms its quick-start card. The
    /// trigger is bumped so asking twice in a row is not swallowed as a no-op.
    private func openReaderQuickStart() {
        selectedTab = .read
        readerQuickStartTrigger += 1
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
