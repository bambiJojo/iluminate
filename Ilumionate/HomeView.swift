//
//  HomeView.swift
//  Ilumionate
//
//  Trance design Home dashboard with category icons and glass cards
//

import SwiftUI

struct HomeView: View {
    @Binding var showingAudioLibrary: Bool
    @Binding var showingSessionPlayer: Bool
    @Binding var selectedSession: LightSession?

    let sessions: [LightSession]
    let onRefresh: (() -> Void)?

    @State private var animateCards = false
    @State private var isRefreshing = false

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
                // Greeting section
                greetingSection

                // Category icons
                categoryIconsSection

                // Continue Session card (if available)
                if let lastSession = sessions.first {
                    continueSessionCard(session: lastSession)
                }

                // Quick Start section
                quickStartSection

                // Your Library section
                yourLibrarySection
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.bottom, 100) // space for tab bar
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
    }

    // MARK: - Greeting Section

    private var greetingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                Text(currentGreeting)
                    .font(TranceTypography.greeting)
                    .foregroundColor(.textPrimary)

                Text("Byron")
                    .font(TranceTypography.greetingAccent)
                    .foregroundColor(.roseGold)
            }

            Spacer()

            // Profile circle
            Circle()
                .fill(
                    LinearGradient(colors: [.roseGold, .blush],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Text("B")
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
            CategoryIcon(emoji: "🌙", label: "Sleep", haloColor: .bwDelta)
            CategoryIcon(emoji: "🎯", label: "Focus", haloColor: .bwAlpha)
            CategoryIcon(emoji: "⚡", label: "Energy", haloColor: .bwBeta)
            CategoryIcon(emoji: "🧘", label: "Relax", haloColor: .bwTheta)
            CategoryIcon(emoji: "🌀", label: "Trance", haloColor: .bwGamma)
        }
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.1), value: animateCards)
    }

    // MARK: - Continue Session Card

    private func continueSessionCard(session: LightSession) -> some View {
        GlassCard(label: "Continue Session") {
            Button {
                selectedSession = session
                showingSessionPlayer = true
            } label: {
                HStack(spacing: TranceSpacing.list) {
                    // Waveform preview
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

                        Text("18:24 remaining")
                            .font(TranceTypography.caption)
                            .foregroundColor(.textSecondary)
                    }

                    Spacer()

                    ProgressRingView(progress: 0.6)
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
                // Alpha (8-12 Hz)
                quickStartMiniCard(
                    title: "Alpha",
                    subtitle: "8-12 Hz",
                    color: .bwAlpha
                )

                // Theta (4-8 Hz)
                quickStartMiniCard(
                    title: "Theta",
                    subtitle: "4-8 Hz",
                    color: .bwTheta
                )
            }
        }
        .opacity(animateCards ? 1 : 0)
        .offset(y: animateCards ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.3), value: animateCards)
    }

    private func quickStartMiniCard(title: String, subtitle: String, color: Color) -> some View {
        Button {
            // Quick start action
            TranceHaptics.shared.medium()
        } label: {
            VStack(spacing: TranceSpacing.micro) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
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
                // Import audio button
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

                // Library thumbnails if available
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
            .padding(.horizontal, 2) // Prevent clipping
        }
    }

    private func libraryThumbnail(session: LightSession, color: Color) -> some View {
        VStack(spacing: TranceSpacing.micro) {
            RoundedRectangle(cornerRadius: TranceRadius.thumbnail)
                .fill(
                    LinearGradient(colors: [color, color.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 72, height: 72)
                .overlay(
                    Text(String(session.displayName.prefix(1)))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                )

            Text(session.displayName)
                .font(.system(size: 10))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
    }

    // MARK: - Helper Properties

    private var currentGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12:
            return "Good morning,"
        case 12..<17:
            return "Good afternoon,"
        case 17..<21:
            return "Good evening,"
        default:
            return "Good night,"
        }
    }

    private func generateSampleWaveform() -> [CGFloat] {
        return [0.3, 0.7, 0.4, 0.8, 0.2, 0.6, 0.9, 0.1, 0.5, 0.8, 0.3, 0.7, 0.4, 0.6, 0.2, 0.9]
    }

    private let sessionColors: [Color] = [
        .bwAlpha, .bwBeta, .bwTheta, .bwDelta, .bwGamma,
        .phaseInduction, .phaseDeepener, .phaseSuggestion
    ]

    // MARK: - Actions

    private func handleRefresh() async {
        isRefreshing = true
        TranceHaptics.shared.light()

        // Simulate refresh delay with haptic feedback
        try? await Task.sleep(for: .seconds(0.8))

        // Call the refresh handler if provided
        onRefresh?()

        isRefreshing = false
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