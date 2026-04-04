//
//  PlayerTransportSection.swift
//  Ilumionate
//
//  Play/pause button, skip 15s, prev/next controls for the unified player.
//

import SwiftUI

// MARK: - Player Button Style

/// Provides scale-down press feedback for transport buttons.
struct PlayerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Transport Section

struct PlayerTransportSection: View {
    @Bindable var viewModel: UnifiedPlayerViewModel

    var body: some View {
        HStack(spacing: 32) {
            // Previous track (playlist) or skip back 15s (audio)
            if viewModel.mode.hasTrackNavigation {
                Button("Previous", systemImage: "backward.fill") {
                    Task { await viewModel.skipPrevious() }
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(viewModel.labelColor)
                .disabled(viewModel.isFirstTrack && viewModel.currentTime < 3)
                .buttonStyle(PlayerButtonStyle())
            } else if viewModel.mode.hasSkipControls {
                Button("Back 15s", systemImage: "gobackward.15") {
                    viewModel.skipBack15()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(viewModel.labelColor)
                .buttonStyle(PlayerButtonStyle())
            }

            // Play / Pause
            Button {
                viewModel.togglePlayPause()
            } label: {
                playPauseIcon
            }
            .buttonStyle(PlayPauseButtonStyle())

            // Next track (playlist) or skip forward 15s (audio)
            if viewModel.mode.hasTrackNavigation {
                Button("Next", systemImage: "forward.fill") {
                    Task { await viewModel.skipNext() }
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(viewModel.labelColor)
                .disabled(viewModel.isLastTrack)
                .buttonStyle(PlayerButtonStyle())
            } else if viewModel.mode.hasSkipControls {
                Button("Forward 15s", systemImage: "goforward.15") {
                    viewModel.skipForward15()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(viewModel.labelColor)
                .buttonStyle(PlayerButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var playPauseIcon: some View {
        if viewModel.useDarkChrome {
            Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(
                        color: TranceShadow.button.color,
                        radius: TranceShadow.button.radius,
                        x: TranceShadow.button.x,
                        y: TranceShadow.button.y
                    )

                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: viewModel.isPlaying ? 0 : 2)
            }
            .scaleEffect(viewModel.isPlaying ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isPlaying)
        }
    }
}

// MARK: - Play/Pause Button Style

/// Provides a spring-bounce press effect for the play/pause button.
private struct PlayPauseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
