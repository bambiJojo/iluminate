//
//  MiniPlayerBar.swift
//  Ilumionate
//
//  Compact now-playing bar that appears above the tab bar when a session
//  is active. Tapping it re-presents the full UnifiedPlayerView; the transport
//  control on its trailing edge plays and pauses in place.
//

import SwiftUI
import os

struct MiniPlayerBar: View {

    var nowPlaying: NowPlayingState
    var onTap: () -> Void
    /// Toggles playback without leaving the current screen. Omitted when nothing
    /// can act on it, so the control is absent rather than present and inert.
    var onPlayPause: (() -> Void)?

    // MARK: - Constants

    private let barHeight: CGFloat = 56
    /// Tap target for the transport control, at the HIG minimum.
    private let controlDiameter: CGFloat = 44

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
                    // Mini orb — identity anchor for the bar
                    LumeOrb(
                        size: .mini,
                        isPaused: nowPlaying.playbackState != .playing
                    )

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

                    // Room for the transport control, which is layered above this
                    // button rather than nested inside it — a Button inside another
                    // Button's label never receives the tap.
                    if onPlayPause != nil {
                        Color.clear
                            .frame(width: controlDiameter, height: controlDiameter)
                    }
                }
                .padding(.horizontal, TranceSpacing.card)
                .frame(height: barHeight)
            }
            .frame(height: barHeight)
            .liminalGlass(.roundedRect(cornerRadius: TranceRadius.glassCard))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Now playing: \(nowPlaying.currentTitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to return to the full player")
        .overlay(alignment: .trailing) {
            if let onPlayPause {
                playPauseButton(action: onPlayPause)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Transport

    private var isPlaying: Bool { nowPlaying.playbackState == .playing }

    private func playPauseButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.roseGold)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: controlDiameter, height: controlDiameter)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(nowPlaying.playbackState == .countdown)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .padding(.trailing, TranceSpacing.card)
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
                        Log.ui.info("Tapped mini player")
                    } onPlayPause: {
                        Log.ui.info("Toggled playback from mini player")
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
