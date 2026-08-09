//
//  HomeView.swift
//  Ilumionate
//
//  The launcher. Greeting, four doors, and a way back into whatever you were
//  last doing — nothing else.
//
//  This screen used to carry nine sections and six competing ways to start
//  something, because it was compensating for a tab bar whose four slots do not
//  match the four things the app actually is. The doors below are that
//  compensation, made explicit and made equal.
//

import SwiftUI

// MARK: - Brainwave Category

enum BrainwaveCategory: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case sleep  = "Sleep"
    case focus  = "Focus"
    case energy = "Energy"
    case relax  = "Relax"
    case trance = "Trance"

    var emoji: String {
        switch self {
        case .sleep:  return "🌙"
        case .focus:  return "🎯"
        case .energy: return "⚡"
        case .relax:  return "🧘"
        case .trance: return "🌀"
        }
    }

    var haloColor: Color {
        switch self {
        case .sleep:  return .bwDelta
        case .focus:  return .bwAlpha
        case .energy: return .bwBeta
        case .relax:  return .bwTheta
        case .trance: return .bwGamma
        }
    }

    /// Average frequency of the first moment that determines which category a session belongs to
    var frequencyRange: ClosedRange<Double> {
        switch self {
        case .sleep:  return 0.5...4.0    // Delta
        case .relax:  return 4.0...8.0    // Theta
        case .focus:  return 8.0...14.0   // Alpha
        case .energy: return 14.0...30.0  // Beta
        case .trance: return 0.5...40.0   // All
        }
    }
}

// MARK: - HomeView

struct HomeView: View {
    @Binding var showingAudioLibrary: Bool
    @Binding var selectedSession: LightSession?

    let sessions: [LightSession]
    let audioFiles: [AudioFile]
    let engine: LightEngine
    let onRefresh: (() -> Void)?
    let onOpenReader: () -> Void
    let onOpenCreate: (CreateSessionKind) -> Void

    @State private var showingProfile = false
    @State private var playerFile: AudioFile?
    @State private var cardsVisible = false
    @State private var progressStore = PlaybackProgressStore.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("profileName") private var userName = ""
    @AppStorage("listeningHistoryEnabled") private var historyEnabled = true

    private let history = SessionHistoryManager.shared

    var body: some View {
        ZStack {
            AuroraBackground(
                mood: PortalRecommender.category(
                    forHour: Calendar.current.component(.hour, from: .now)
                )
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: TranceSpacing.content) {
                    greeting
                        .cardEntrance(visible: cardsVisible, delay: 0.00, reduceMotion: reduceMotion)

                    HomeDoorsView(onSelect: open)
                        .cardEntrance(visible: cardsVisible, delay: 0.06, reduceMotion: reduceMotion)

                    if let resume {
                        HomeResumePill(state: resume) { open(resume) }
                            .cardEntrance(visible: cardsVisible, delay: 0.12, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.bottom, TranceSpacing.tabBarClearance)
            }
            .refreshable { await handleRefresh() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Settings", systemImage: "gearshape") {
                    TranceHaptics.shared.light()
                    showingProfile = true
                }
                .foregroundStyle(Color.roseGold)
            }
        }
        .onAppear {
            cardsVisible = false
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                cardsVisible = true
            }
        }
        .onDisappear { cardsVisible = false }
        .sheet(isPresented: $showingProfile) {
            ProfileSettingsView()
        }
        .platformFullScreenCover(item: $playerFile) { file in
            UnifiedPlayerView(mode: .audioLight(audioFile: file), engine: engine)
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(spacing: TranceSpacing.micro) {
            Text(portalGreeting)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.textSecondary)

            Text("Ready to descend?")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(Color.textPrimary)

            if let streakText {
                Text(streakText)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textLight)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TranceSpacing.statusBar)
    }

    /// Only shown once there is momentum worth protecting — a "0 day streak"
    /// is a discouragement, not a metric.
    private var streakText: String? {
        guard historyEnabled else { return nil }
        let streak = history.currentStreak
        guard streak > 0 else { return nil }
        return streak == 1 ? "1 day streak" : "\(streak) day streak"
    }

    private var currentGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<21: return "Good evening,"
        default:      return "Good night,"
        }
    }

    private var portalGreeting: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            return currentGreeting.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        }
        return "\(currentGreeting) \(name)"
    }

    // MARK: - Resume

    private var resume: HomeResumeState? {
        HomeResumeState(snapshot: progressStore.snapshots.first)
    }

    // MARK: - Actions

    private func open(_ door: HomeDoor) {
        TranceHaptics.shared.light()
        UsageAnalytics.shared.homeCoreActionSelected(door.analyticsAction)
        switch door.route {
        case .audioLibrary:
            showingAudioLibrary = true
        case .reader:
            onOpenReader()
        case .create(let kind):
            onOpenCreate(kind)
        }
    }

    private func open(_ state: HomeResumeState) {
        TranceHaptics.shared.medium()
        switch state.kind {
        case .audio:
            playerFile = audioFiles.first { $0.id.uuidString == state.contentID }
        case .session:
            selectedSession = sessions.first { $0.id.uuidString == state.contentID }
        }
    }

    private func handleRefresh() async {
        TranceHaptics.shared.light()
        try? await Task.sleep(for: .seconds(0.8))
        onRefresh?()
    }
}

// MARK: - Card Entrance Modifier

private extension View {
    /// Slides the view up from a 20-pt offset while fading in.
    /// When `reduceMotion` is true the slide is suppressed and a quick fade
    /// is used instead, honoring the user's accessibility preference.
    func cardEntrance(visible: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .offset(y: (visible || reduceMotion) ? 0 : 20)
            .animation(
                reduceMotion
                    ? .easeIn(duration: 0.15).delay(delay)
                    : .spring(response: 0.55, dampingFraction: 0.82).delay(delay),
                value: visible
            )
    }
}

// MARK: - Preview

#Preview {
    struct HomeViewPreview: View {
        @State private var showingAudioLibrary = false
        @State private var selectedSession: LightSession?
        @State private var engine = LightEngine()

        var body: some View {
            NavigationStack {
                HomeView(
                    showingAudioLibrary: $showingAudioLibrary,
                    selectedSession: $selectedSession,
                    sessions: [],
                    audioFiles: [],
                    engine: engine,
                    onRefresh: nil,
                    onOpenReader: {},
                    onOpenCreate: { _ in }
                )
            }
        }
    }

    return HomeViewPreview()
}
