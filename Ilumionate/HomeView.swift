//
//  HomeView.swift
//  Ilumionate
//
//  Trance design Home dashboard with category icons and glass cards
//

import SwiftUI

// MARK: - Brainwave Category

enum BrainwaveCategory: String, CaseIterable {
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
    @Binding var showingSessionPlayer: Bool
    @Binding var selectedSession: LightSession?

    let sessions: [LightSession]
    let onRefresh: (() -> Void)?

    @State private var animateCards = false
    @State private var isRefreshing = false
    @State private var showingCategorySheet = false
    @State private var activeCategoryFilter: BrainwaveCategory?

    // Persist user name and last session progress
    @AppStorage("userName") private var userName = ""
    @AppStorage("lastSessionId") private var lastSessionId = ""
    @AppStorage("lastSessionProgress") private var lastSessionProgress: Double = 0.0

    init(showingAudioLibrary: Binding<Bool>,
         showingSessionPlayer: Binding<Bool>,
         selectedSession: Binding<LightSession?>,
         sessions: [LightSession],
         onRefresh: (() -> Void)? = nil) {
        self._showingAudioLibrary = showingAudioLibrary
        self._showingSessionPlayer = showingSessionPlayer
        self._selectedSession = selectedSession
        self.sessions = sessions
        self.onRefresh = onRefresh
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.content) {
                greetingSection
                categoryIconsSection

                // Only show Continue Session card when we have real progress
                if lastSessionProgress > 0,
                   let lastSession = sessions.first(where: { $0.id.uuidString == lastSessionId }) ?? sessions.first {
                    continueSessionCard(session: lastSession)
                }

                quickStartSection
                yourLibrarySection
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, 100)
        }
        .refreshable {
            await handleRefresh()
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateCards = true
            }
        }
        // Category filter sheet
        .sheet(isPresented: $showingCategorySheet) {
            if let category = activeCategoryFilter {
                CategorySessionSheet(
                    category: category,
                    sessions: sessions,
                    onSelect: { session in
                        showingCategorySheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            selectedSession = session
                            showingSessionPlayer = true
                        }
                    }
                )
            }
        }
    }

    // MARK: - Greeting Section

    private var greetingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                Text(currentGreeting)
                    .font(TranceTypography.greeting)
                    .foregroundColor(.textPrimary)

                Text(displayName)
                    .font(TranceTypography.greetingAccent)
                    .foregroundColor(.roseGold)
            }

            Spacer()

            // Profile circle — shows first initial
            Circle()
                .fill(
                    LinearGradient(colors: [.roseGold, .blush],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Text(profileInitial)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                )
                .shadow(
                    color: TranceShadow.elevated.color,
                    radius: TranceShadow.elevated.radius,
                    x: TranceShadow.elevated.x,
                    y: TranceShadow.elevated.y
                )
        }
        .padding(.top, TranceSpacing.statusBar)
    }

    // MARK: - Category Icons Section

    private var categoryIconsSection: some View {
        HStack(spacing: TranceSpacing.content) {
            ForEach(BrainwaveCategory.allCases, id: \.rawValue) { category in
                Button {
                    TranceHaptics.shared.light()
                    activeCategoryFilter = category
                    showingCategorySheet = true
                } label: {
                    CategoryIcon(emoji: category.emoji, label: category.rawValue, haloColor: category.haloColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.1), value: animateCards)
    }

    // MARK: - Continue Session Card

    private func continueSessionCard(session: LightSession) -> some View {
        let progress = lastSessionProgress
        let elapsed = session.duration_sec * progress
        let remaining = max(0, session.duration_sec - elapsed)
        let remainingText = formatTime(remaining) + " remaining"

        return GlassCard(label: "Continue Session") {
            Button {
                TranceHaptics.shared.medium()
                selectedSession = session
                showingSessionPlayer = true
            } label: {
                HStack(spacing: TranceSpacing.list) {
                    WaveformView(
                        samples: generateSampleWaveform(),
                        color: .roseGold
                    )
                    .frame(width: 120, height: 30)

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(session.displayName)
                            .font(TranceTypography.body)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        Text(remainingText)
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    ProgressRingView(progress: progress)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.2), value: animateCards)
    }

    // MARK: - Quick Start Section

    private var quickStartSection: some View {
        GlassCard(label: "Quick Start") {
            HStack(spacing: TranceSpacing.list) {
                quickStartMiniCard(title: "Alpha", subtitle: "10 Hz · Focus", color: .bwAlpha) {
                    launchQuickSession(name: "Alpha Focus", frequency: 10.0, durationMinutes: 10, color: .bwAlpha)
                }
                quickStartMiniCard(title: "Theta", subtitle: "6 Hz · Relax", color: .bwTheta) {
                    launchQuickSession(name: "Theta Relax", frequency: 6.0, durationMinutes: 15, color: .bwTheta)
                }
                quickStartMiniCard(title: "Delta", subtitle: "2 Hz · Sleep", color: .bwDelta) {
                    launchQuickSession(name: "Delta Sleep", frequency: 2.0, durationMinutes: 20, color: .bwDelta)
                }
            }
        }
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.3), value: animateCards)
    }

    private func quickStartMiniCard(title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: TranceSpacing.micro) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TranceSpacing.inner)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.thumbnail))
            .overlay(
                RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Your Library Section

    private var yourLibrarySection: some View {
        GlassCard(label: "Your Library") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Button {
                    showingAudioLibrary = true
                } label: {
                    HStack(spacing: TranceSpacing.list) {
                        Circle()
                            .fill(Color.phaseInduction)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                            )

                        VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                            Text("Import Audio")
                                .font(TranceTypography.body)
                                .foregroundColor(.textPrimary)

                            Text("Create custom sessions")
                                .font(TranceTypography.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textLight)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                if !sessions.isEmpty {
                    libraryThumbnailsRow
                }
            }
        }
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.4), value: animateCards)
    }

    private var libraryThumbnailsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TranceSpacing.small) {
                ForEach(Array(sessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                    libraryThumbnail(session: session, color: sessionColors[index % sessionColors.count])
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func libraryThumbnail(session: LightSession, color: Color) -> some View {
        Button {
            TranceHaptics.shared.light()
            selectedSession = session
            showingSessionPlayer = true
        } label: {
            VStack(spacing: TranceSpacing.micro) {
                RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                    .fill(
                        LinearGradient(colors: [color, color.opacity(0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    )
                    .overlay(alignment: .topTrailing) {
                        Text(String(session.displayName.prefix(1)))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(4)
                    }

                Text(session.displayName)
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helper Properties

    private var displayName: String {
        userName.isEmpty ? "Friend" : userName
    }

    private var profileInitial: String {
        userName.first.map(String.init) ?? "?"
    }

    private var currentGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning,"
        case 12..<17: return "Good afternoon,"
        case 17..<21: return "Good evening,"
        default:      return "Good night,"
        }
    }

    private func generateSampleWaveform() -> [CGFloat] {
        [0.3, 0.7, 0.4, 0.8, 0.2, 0.6, 0.9, 0.1, 0.5, 0.8, 0.3, 0.7, 0.4, 0.6, 0.2, 0.9]
    }

    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private let sessionColors: [Color] = [
        .bwAlpha, .bwBeta, .bwTheta, .bwDelta, .bwGamma,
        .phaseInduction, .phaseDeepener, .phaseSuggestion
    ]

    // MARK: - Actions

    private func launchQuickSession(name: String, frequency: Double, durationMinutes: Int, color: Color) {
        TranceHaptics.shared.medium()
        let duration = Double(durationMinutes * 60)
        let session = LightSession(
            session_name: name,
            duration_sec: duration,
            light_score: [
                LightMoment(time: 0,        frequency: frequency * 1.5, intensity: 0.5, waveform: .sine),
                LightMoment(time: duration * 0.1, frequency: frequency, intensity: 0.7, waveform: .sine, ramp_duration: 15),
                LightMoment(time: duration * 0.8, frequency: frequency, intensity: 0.8, waveform: .softPulse),
                LightMoment(time: duration * 0.95, frequency: frequency * 0.7, intensity: 0.3, waveform: .sine, ramp_duration: 20)
            ]
        )
        selectedSession = session
        showingSessionPlayer = true
    }

    private func handleRefresh() async {
        isRefreshing = true
        TranceHaptics.shared.light()
        try? await Task.sleep(for: .seconds(0.8))
        onRefresh?()
        isRefreshing = false
    }
}

// MARK: - Category Session Sheet

struct CategorySessionSheet: View {
    let category: BrainwaveCategory
    let sessions: [LightSession]
    let onSelect: (LightSession) -> Void

    @Environment(\.dismiss) private var dismiss

    private var filteredSessions: [LightSession] {
        let range = category.frequencyRange
        let filtered = sessions.filter { session in
            guard let firstMoment = session.light_score.min(by: { $0.time < $1.time }) else { return false }
            return range.contains(firstMoment.frequency)
        }
        // "Trance" shows all; also fall back to all if no match
        return (category == .trance || filtered.isEmpty) ? sessions : filtered
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                if filteredSessions.isEmpty {
                    VStack(spacing: TranceSpacing.card) {
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 52, weight: .ultraLight))
                            .foregroundColor(category.haloColor)
                        Text("No \(category.rawValue) sessions yet")
                            .font(TranceTypography.body)
                            .foregroundColor(.textSecondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: TranceSpacing.cardMargin) {
                            ForEach(filteredSessions) { session in
                                Button {
                                    onSelect(session)
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
            }
            .navigationTitle("\(category.emoji) \(category.rawValue)")
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
        }
    }
}

// MARK: - Preview

#Preview {
    struct HomeViewPreview: View {
        @State private var showingAudioLibrary = false
        @State private var showingSessionPlayer = false
        @State private var selectedSession: LightSession?

        var body: some View {
            HomeView(
                showingAudioLibrary: $showingAudioLibrary,
                showingSessionPlayer: $showingSessionPlayer,
                selectedSession: $selectedSession,
                sessions: [],
                onRefresh: nil
            )
        }
    }

    return HomeViewPreview()
}