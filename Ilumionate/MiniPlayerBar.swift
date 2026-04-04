//
//  MiniPlayerBar.swift
//  Ilumionate
//
//  Compact now-playing bar that appears above the tab bar when a session
//  is active. Tapping it re-presents the full UnifiedPlayerView.
//

import SwiftUI

struct MiniPlayerBar: View {

    var nowPlaying: NowPlayingState
    var onTap: () -> Void

    // MARK: - Constants

    private let barHeight: CGFloat = 56

    // MARK: - Body

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .top) {
                // Thin progress tint along the top edge
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.roseGold)
                        .frame(
                            width: proxy.size.width * nowPlaying.progress,
                            height: 2
                        )
                        .animation(.linear(duration: 0.3), value: nowPlaying.progress)
                }
                .frame(height: 2)

                // Content row
                HStack(spacing: TranceSpacing.list) {
                    // Track title + state
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlaying.currentTitle)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Text(statusLabel)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    // Play / Pause indicator
                    Image(systemName: nowPlaying.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.roseGold)
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, TranceSpacing.card)
                .frame(height: barHeight)
            }
            .frame(height: barHeight)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: TranceRadius.glassCard))
            .overlay {
                RoundedRectangle(cornerRadius: TranceRadius.glassCard)
                    .stroke(Color.glassBorder, lineWidth: 1)
            }
            .shadow(
                color: TranceShadow.card.color.opacity(0.15),
                radius: 10,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Now playing: \(nowPlaying.currentTitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to return to the full player")
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    private var statusLabel: String {
        switch nowPlaying.playbackState {
        case .playing:   "Playing"
        case .paused:    "Paused"
        case .countdown: "Starting..."
        case .complete:  "Completed"
        case .idle:      "Ready"
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var state = NowPlayingState.shared

        var body: some View {
            ZStack(alignment: .bottom) {
                Color.bgPrimary.ignoresSafeArea()

                VStack {
                    Spacer()
                    MiniPlayerBar(nowPlaying: state) {
                        print("Tapped mini player")
                    }
                }
                .padding(.bottom, 80)
            }
            .onAppear {
                state.activate(
                    mode: .flashMode(
                        frequency: 10, intensity: 0.8,
                        colorTemperature: 3000,
                        pattern: .sine,
                        binauralEnabled: false,
                        binauralCarrier: 200,
                        binauralVolume: 0.5
                    ),
                    title: "Deep Theta Session",
                    engine: LightEngine()
                )
                state.updateProgress(0.35)
            }
        }
    }

    return PreviewWrapper()
}
