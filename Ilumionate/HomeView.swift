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
    let engine: LightEngine
    let onRefresh: (() -> Void)?

    @State private var isRefreshing = false
    @State private var showingProfile = false
    @State var showingSessionLibrary = false
    @State private var playerFile: AudioFile?
    @State private var cardsVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Flash session state — for Mind Machine quick presets
    @State private var showingFlashMode = false
    @State private var flashFrequency: Double = 10.0
    @State private var flashIntensity: Double = 0.75
    @State private var flashKelvin: Int = 4000
    @State private var flashPattern: MindMachineModel.LightPattern = .sine
    @State private var flashBinauralEnabled = true
    @State private var flashBinauralCarrier: Double = 200
    @State private var flashBinauralVolume: Double = 0.5

    // Persist user name and last session progress
    @AppStorage("profileName") private var userName = ""
    @AppStorage("lastSessionId") private var lastSessionId = ""
    @AppStorage("lastSessionProgress") private var lastSessionProgress: Double = 0.0

    init(showingAudioLibrary: Binding<Bool>,
         showingSessionPlayer: Binding<Bool>,
         selectedSession: Binding<LightSession?>,
         sessions: [LightSession],
         audioFiles: [AudioFile] = [],
         engine: LightEngine,
         onRefresh: (() -> Void)? = nil) {
        self._showingAudioLibrary = showingAudioLibrary
        self._showingSessionPlayer = showingSessionPlayer
        self._selectedSession = selectedSession
        self.sessions = sessions
        self.audioFiles = audioFiles
        self.engine = engine
        self.onRefresh = onRefresh
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.content) {
                greetingSection
                    .cardEntrance(visible: cardsVisible, delay: 0.00, reduceMotion: reduceMotion)

                if lastSessionProgress > 0,
                   let lastSession = sessions.first(where: { $0.id.uuidString == lastSessionId }) ?? sessions.first {
                    continueSessionCard(session: lastSession)
                        .cardEntrance(visible: cardsVisible, delay: 0.08, reduceMotion: reduceMotion)
                }

                if !sessions.isEmpty {
                    featuredSessionsSection
                        .cardEntrance(visible: cardsVisible, delay: 0.12, reduceMotion: reduceMotion)
                }

                quickStartSection
                    .cardEntrance(visible: cardsVisible, delay: 0.18, reduceMotion: reduceMotion)
                recentAudioSection
                    .cardEntrance(visible: cardsVisible, delay: 0.22, reduceMotion: reduceMotion)
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, 100)
        }
        .refreshable {
            await handleRefresh()
        }
        .onAppear {
            // Reset before animating so re-entry (tab switch) always replays the entrance.
            cardsVisible = false
            Task {
                // One frame of invisible state lets SwiftUI capture the layout
                // before the spring kicks in.
                try? await Task.sleep(for: .milliseconds(30))
                cardsVisible = true
            }
        }
        .onDisappear { cardsVisible = false }
        .background(Color.bgPrimary.ignoresSafeArea())
        .sheet(isPresented: $showingProfile) {
            ProfileSettingsView()
        }
        .sheet(isPresented: $showingSessionLibrary) {
            SessionLibraryView(engine: engine)
        }
        .fullScreenCover(isPresented: $showingFlashMode) {
            UnifiedPlayerView(
                mode: .flashMode(
                    frequency: flashFrequency,
                    intensity: flashIntensity,
                    colorTemperature: flashKelvin,
                    pattern: flashPattern,
                    binauralEnabled: flashBinauralEnabled,
                    binauralCarrier: flashBinauralCarrier,
                    binauralVolume: flashBinauralVolume
                ),
                engine: engine
            )
        }
        .fullScreenCover(item: $playerFile) { file in
            UnifiedPlayerView(mode: .audioLight(audioFile: file), engine: engine)
        }
    }

    // MARK: - Greeting Section

    private var greetingSection: some View {
        HStack(alignment: .center) {
            // Left: branding + time-based greeting
            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                WordmarkView()

                Text("\(currentGreeting) \(displayName)")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // Right: profile avatar
            Button {
                TranceHaptics.shared.light()
                showingProfile = true
            } label: {
                Circle()
                    .fill(
                        LinearGradient(colors: [.roseGold, .blush],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(profileInitial)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .shadow(
                        color: TranceShadow.elevated.color,
                        radius: TranceShadow.elevated.radius,
                        x: TranceShadow.elevated.x,
                        y: TranceShadow.elevated.y
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, TranceSpacing.statusBar)
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
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)

                        Text(remainingText)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textSecondary)
                    }

                    Spacer()

                    ProgressRingView(progress: progress)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Quick Start Section

    private var quickStartSection: some View {
        GlassCard(label: "Quick Presets") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Label("Starts flash + binaural audio", systemImage: "headphones")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textSecondary)

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
        }
    }

    private func quickStartMiniCard(title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: TranceSpacing.micro) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)

                Label("Flash + Audio", systemImage: "headphones")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TranceSpacing.inner)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.thumbnail))
            .overlay {
                RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(.white)
                                }

                            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                                Text("Import Audio")
                                    .font(TranceTypography.body)
                                    .foregroundStyle(.textPrimary)
                                Text("Add your own hypnosis files")
                                    .font(TranceTypography.caption)
                                    .foregroundStyle(.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.textLight)
                        }
                    }
                    .buttonStyle(.plain)
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
                                .foregroundStyle(.roseGold)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.roseGold)
                        }
                    }
                    .buttonStyle(.plain)
                    .opacity(audioFiles.count > 3 ? 1 : 0)
                }
            }
        }
    }

    private func audioFileRow(file: AudioFile, index: Int) -> some View {
        Button {
            TranceHaptics.shared.medium()
            playerFile = file
        } label: {
            HStack(spacing: TranceSpacing.list) {
                ZStack {
                    RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                        .fill(sessionColors[index % sessionColors.count].opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: file.isAnalyzed ? "waveform.circle.fill" : "waveform.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(sessionColors[index % sessionColors.count])
                }

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(file.displayName)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: TranceSpacing.small) {
                        Text(file.durationFormatted)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textSecondary)
                        if file.isAnalyzed {
                            Text("· Light Sync Ready")
                                .font(TranceTypography.caption)
                                .foregroundStyle(.roseGold)
                        }
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.roseGold)
            }
        }
        .buttonStyle(.plain)
    }

    private var recentAudioFiles: [AudioFile] {
        Array(audioFiles.sorted { $0.createdDate > $1.createdDate }.prefix(3))
    }

    // MARK: - Helper Properties

    private var displayName: String {
        userName.isEmpty ? "Friend" : userName
    }

    private var profileInitial: String {
        userName.first.map(String.init) ?? "?"
    }

    private var currentGreeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
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
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    private let sessionColors: [Color] = [
        .bwAlpha, .bwBeta, .bwTheta, .bwDelta, .bwGamma,
        .phaseInduction, .phaseDeepener, .phaseSuggestion
    ]

    // MARK: - Actions

    private func launchQuickSession(
        name: String,
        frequency: Double,
        durationMinutes: Int,
        color: Color,
        bilateral: Bool = false
    ) {
        TranceHaptics.shared.heavy()
        flashFrequency = frequency
        flashIntensity = 0.75
        // Map brainwave to a comfortable Kelvin temperature
        switch frequency {
        case ..<4:   flashKelvin = 2700  // warm amber — delta/sleep
        case ..<8:   flashKelvin = 3200  // soft warm — theta/relax
        case ..<13:  flashKelvin = 4000  // neutral white — alpha/focus
        default:     flashKelvin = 5500  // cool daylight — beta/energy
        }
        flashPattern = bilateral ? .sine : .sine
        flashBinauralEnabled = true
        flashBinauralCarrier = 200
        flashBinauralVolume = 0.5
        showingFlashMode = true
    }

    private func handleRefresh() async {
        isRefreshing = true
        TranceHaptics.shared.light()
        try? await Task.sleep(for: .seconds(0.8))
        onRefresh?()
        isRefreshing = false
    }
}

// MARK: - Animated Wordmark

struct WordmarkView: View {
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var wavePhase: Double = 0

    // Fixed bar heights — a hand-crafted waveform silhouette
    private let bars: [CGFloat] = [
        0.25, 0.45, 0.60, 0.80, 0.55, 0.95, 0.70, 0.40,
        0.85, 0.60, 0.45, 0.75, 0.50, 0.35, 0.65, 0.90,
        0.55, 0.40, 0.70, 0.30
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Wordmark text with shimmer overlay
            shimmeringTitle

            // Micro waveform
            waveformBar
        }
    }

    // MARK: Shimmering Title

    private var shimmeringTitle: some View {
        Text("LumeSync")
            .font(.system(size: 28, weight: .thin, design: .rounded))
            .tracking(2)
            .foregroundStyle(
                LinearGradient(
                    colors: [.textPrimary, .roseGold, .bwTheta, .roseGold, .textPrimary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(0.9)
            )
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear,               location: 0.0),
                            .init(color: .white.opacity(0.12), location: 0.4),
                            .init(color: .white.opacity(0.18), location: 0.5),
                            .init(color: .white.opacity(0.12), location: 0.6),
                            .init(color: .clear,               location: 1.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: shimmerOffset * geo.size.width * 1.5)
                    .blendMode(.plusLighter)
                }
                .clipped()
            }
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 6.0)
                    .repeatForever(autoreverses: false)
                    .delay(2.0)
                ) {
                    shimmerOffset = 1.5
                }
            }
    }

    // MARK: Waveform Bar

    private var waveformBar: some View {
        TimelineView(.animation(minimumInterval: 1 / 12)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let count = bars.count
                let spacing: CGFloat = 3
                let barW: CGFloat = (size.width - CGFloat(count - 1) * spacing) / CGFloat(count)
                let maxH = size.height

                for (i, base) in bars.enumerated() {
                    let phase = t * 0.4 + Double(i) * 0.3
                    let breathe = 0.05 * sin(phase)
                    let h = CGFloat(clamp(Double(base) + breathe, 0.12, 1.0)) * maxH

                    let x = CGFloat(i) * (barW + spacing)
                    let rect = CGRect(x: x, y: maxH - h, width: barW, height: h)
                    let path = Path(roundedRect: rect, cornerRadius: barW / 2)

                    let t01 = Double(i) / Double(count - 1)
                    let color = Color(
                        red:   lerp(0.831, 0.690, t01),
                        green: lerp(0.471, 0.490, t01),
                        blue:  lerp(0.604, 0.784, t01)
                    ).opacity(lerp(0.35, 0.18, t01))

                    ctx.fill(path, with: .color(color))
                }
            }
        }
        .frame(width: 130, height: 12)
    }
}

// Small math helpers (file-private)
private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }
private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

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
                            .foregroundStyle(category.haloColor)
                        Text("No \(category.rawValue) sessions yet")
                            .font(TranceTypography.body)
                            .foregroundStyle(.textSecondary)
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
                                .buttonStyle(.plain)
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
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
        }
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
        @State private var showingSessionPlayer = false
        @State private var selectedSession: LightSession?
        @State private var engine = LightEngine()

        var body: some View {
            HomeView(
                showingAudioLibrary: $showingAudioLibrary,
                showingSessionPlayer: $showingSessionPlayer,
                selectedSession: $selectedSession,
                sessions: [],
                engine: engine,
                onRefresh: nil
            )
        }
    }

    return HomeViewPreview()
}
