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
    let audioFiles: [AudioFile]
    let onRefresh: (() -> Void)?

    @State private var animateCards = false
    @State private var isRefreshing = false
    @State private var showingProfile = false

    // Persist user name and last session progress
    @AppStorage("userName") private var userName = ""
    @AppStorage("lastSessionId") private var lastSessionId = ""
    @AppStorage("lastSessionProgress") private var lastSessionProgress: Double = 0.0

    init(showingAudioLibrary: Binding<Bool>,
         showingSessionPlayer: Binding<Bool>,
         selectedSession: Binding<LightSession?>,
         sessions: [LightSession],
         audioFiles: [AudioFile] = [],
         onRefresh: (() -> Void)? = nil) {
        self._showingAudioLibrary = showingAudioLibrary
        self._showingSessionPlayer = showingSessionPlayer
        self._selectedSession = selectedSession
        self.sessions = sessions
        self.audioFiles = audioFiles
        self.onRefresh = onRefresh
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.content) {
                greetingSection

                if lastSessionProgress > 0,
                   let lastSession = sessions.first(where: { $0.id.uuidString == lastSessionId }) ?? sessions.first {
                    continueSessionCard(session: lastSession)
                }

                quickStartSection
                recentAudioSection
                mindMachineSection
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
        .sheet(isPresented: $showingProfile) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Profile & Settings")
                    .navigationBarTitleDisplayMode(.large)
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

            // Profile circle — taps to open settings
            Button {
                TranceHaptics.shared.light()
                showingProfile = true
            } label: {
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
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, TranceSpacing.statusBar)
    }

    // MARK: - Category Icons Section

//    private var categoryIconsSection: some View {
//        HStack(spacing: TranceSpacing.content) {
//            ForEach(BrainwaveCategory.allCases, id: \.rawValue) { category in
//                Button {
//                    TranceHaptics.shared.light()
//                    activeCategoryFilter = category
//                    showingCategorySheet = true
//                } label: {
//                    CategoryIcon(emoji: category.emoji, label: category.rawValue, haloColor: category.haloColor)
//                }
//                .buttonStyle(PlainButtonStyle())
//            }
//        }
//        .opacity(animateCards ? 1 : 0)
//        .offset(y: animateCards ? 0 : 20)
//        .animation(.easeOut(duration: 0.6).delay(0.1), value: animateCards)
//    }

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

    // MARK: - Recent Audio Section

    private var recentAudioSection: some View {
        GlassCard(label: "Recent Audio") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                if recentAudioFiles.isEmpty {
                    // Empty state row
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
                                Text("Add your own hypnosis files")
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
                } else {
                    ForEach(Array(recentAudioFiles.enumerated()), id: \.element.id) { index, file in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.glassBorder.opacity(0.3))
                                .frame(height: 1)
                        }
                        audioFileRow(file: file, index: index)
                    }

                    // "See all" link
                    Button {
                        showingAudioLibrary = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("See all \(audioFiles.count) files")
                                .font(TranceTypography.caption)
                                .foregroundColor(.roseGold)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.roseGold)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(audioFiles.count > 3 ? 1 : 0)
                }
            }
        }
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.4), value: animateCards)
    }

    private func audioFileRow(file: AudioFile, index: Int) -> some View {
        HStack(spacing: TranceSpacing.list) {
            // Track number / icon
            ZStack {
                RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                    .fill(sessionColors[index % sessionColors.count].opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: file.isAnalyzed ? "waveform.circle.fill" : "waveform.circle")
                    .font(.system(size: 20))
                    .foregroundColor(sessionColors[index % sessionColors.count])
            }

            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                Text(file.displayName)
                    .font(TranceTypography.body)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                HStack(spacing: TranceSpacing.small) {
                    Text(file.durationFormatted)
                        .font(TranceTypography.caption)
                        .foregroundColor(.textSecondary)

                    if file.isAnalyzed {
                        Text("· Analyzed")
                            .font(TranceTypography.caption)
                            .foregroundColor(.roseGold)
                    }
                }
            }

            Spacer()

            Image(systemName: "play.circle")
                .font(.system(size: 22))
                .foregroundColor(.textLight)
        }
    }

    private var recentAudioFiles: [AudioFile] {
        Array(audioFiles.sorted { $0.createdDate > $1.createdDate }.prefix(3))
    }

    // MARK: - Mind Machine Section

    private var mindMachineSection: some View {
        GlassCard(label: "Mind Machine") {
            VStack(spacing: TranceSpacing.list) {
                Text("Brainwave Presets")
                    .font(TranceTypography.caption)
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: TranceSpacing.list) {
                    mindMachinePresetCard(
                        emoji: "🧘",
                        title: "Theta",
                        subtitle: "6 Hz · Deep Relax",
                        color: .bwTheta
                    ) {
                        launchQuickSession(name: "Theta Relax", frequency: 6.0, durationMinutes: 15, color: .bwTheta)
                    }

                    mindMachinePresetCard(
                        emoji: "🎯",
                        title: "Alpha",
                        subtitle: "10 Hz · Focus",
                        color: .bwAlpha
                    ) {
                        launchQuickSession(name: "Alpha Focus", frequency: 10.0, durationMinutes: 10, color: .bwAlpha)
                    }

                    mindMachinePresetCard(
                        emoji: "🌙",
                        title: "Delta",
                        subtitle: "2 Hz · Sleep",
                        color: .bwDelta
                    ) {
                        launchQuickSession(name: "Delta Sleep", frequency: 2.0, durationMinutes: 20, color: .bwDelta)
                    }
                }

                // Built-in sessions row (up to 3)
                if !sessions.isEmpty {
                    Rectangle()
                        .fill(Color.glassBorder.opacity(0.3))
                        .frame(height: 1)

                    ForEach(Array(sessions.prefix(3).enumerated()), id: \.element.id) { index, session in
                        Button {
                            TranceHaptics.shared.light()
                            selectedSession = session
                            showingSessionPlayer = true
                        } label: {
                            HStack(spacing: TranceSpacing.list) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                                        .fill(sessionColors[index % sessionColors.count].opacity(0.15))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 18))
                                        .foregroundColor(sessionColors[index % sessionColors.count])
                                }

                                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                                    Text(session.displayName)
                                        .font(TranceTypography.body)
                                        .foregroundColor(.textPrimary)
                                        .lineLimit(1)
                                    Text(session.durationFormatted)
                                        .font(TranceTypography.caption)
                                        .foregroundColor(.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "play.circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(.textLight)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.5), value: animateCards)
    }

    private func mindMachinePresetCard(emoji: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: TranceSpacing.micro) {
                Text(emoji)
                    .font(.system(size: 24))

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Text(subtitle)
                    .font(.system(size: 10))
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
