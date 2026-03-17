//
//  PlayerTransportSection.swift
//  Ilumionate
//
//  Play/pause button, skip 15s, prev/next controls for the unified player.
//

import SwiftUI

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
            } else if viewModel.mode.hasSkipControls {
                Button("Back 15s", systemImage: "gobackward.15") {
                    viewModel.skipBack15()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(viewModel.labelColor)
            }

            // Play / Pause
            Button {
                viewModel.togglePlayPause()
            } label: {
                playPauseIcon
            }

            // Next track (playlist) or skip forward 15s (audio)
            if viewModel.mode.hasTrackNavigation {
                Button("Next", systemImage: "forward.fill") {
                    Task { await viewModel.skipNext() }
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(viewModel.labelColor)
                .disabled(viewModel.isLastTrack)
            } else if viewModel.mode.hasSkipControls {
                Button("Forward 15s", systemImage: "goforward.15") {
                    viewModel.skipForward15()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(viewModel.labelColor)
            }
        }
    }

    @ViewBuilder
    private var playPauseIcon: some View {
        if viewModel.useDarkChrome {
            Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.white)
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
                    .offset(x: viewModel.isPlaying ? 0 : 2)
            }
            .scaleEffect(viewModel.isPlaying ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isPlaying)
        }
    }
}
