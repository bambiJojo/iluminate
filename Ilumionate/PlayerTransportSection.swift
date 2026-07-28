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
    /// Restarts the controls idle timer — see `PlayerControlTray.onInteraction`.
    var onInteraction: () -> Void = {}

    var body: some View {
        HStack(spacing: 28) {
            if viewModel.mode.hasTrackNavigation {
                ClusterGhostButton(label: "Previous", systemImage: "backward.fill") {
                    onInteraction()
                    Task { await viewModel.skipPrevious() }
                }
                .disabled(viewModel.isFirstTrack && viewModel.currentTime < 3)
            } else if viewModel.mode.hasSkipControls {
                ClusterGhostButton(label: "Back 15 seconds", systemImage: "gobackward.15") {
                    onInteraction()
                    viewModel.skipBack15()
                }
            }

            ClusterPlayButton(
                label: viewModel.isPlaying ? "Pause" : "Play",
                systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill"
            ) {
                onInteraction()
                viewModel.togglePlayPause()
            }

            if viewModel.mode.hasTrackNavigation {
                ClusterGhostButton(label: "Next", systemImage: "forward.fill") {
                    onInteraction()
                    Task { await viewModel.skipNext() }
                }
                .disabled(viewModel.isLastTrack)
            } else if viewModel.mode.hasSkipControls {
                ClusterGhostButton(label: "Forward 15 seconds", systemImage: "goforward.15") {
                    onInteraction()
                    viewModel.skipForward15()
                }
            }
        }
    }
}
