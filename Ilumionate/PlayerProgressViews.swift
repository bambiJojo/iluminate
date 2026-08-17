//
//  PlayerProgressViews.swift
//  Ilumionate
//
//  Fast-changing playback time is intentionally read inside these leaves. If
//  UnifiedPlayerView reads it directly, its entire full-screen hierarchy is
//  invalidated by the 10 Hz playback clock.
//

import SwiftUI

struct PlayerElapsedTime: View {
    let viewModel: UnifiedPlayerViewModel

    var body: some View {
        Text(viewModel.formatTime(viewModel.currentTime))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(viewModel.secondaryLabelColor.opacity(0.6))
    }
}

struct PlayerElapsedDuration: View {
    let viewModel: UnifiedPlayerViewModel

    var body: some View {
        Text(
            viewModel.formatTime(viewModel.currentTime)
                + " / "
                + viewModel.formatTime(viewModel.duration)
        )
        .font(TranceTypography.caption)
        .foregroundStyle(viewModel.secondaryLabelColor)
        .monospacedDigit()
    }
}

struct PlayerScrubLine: View {
    @Bindable var viewModel: UnifiedPlayerViewModel
    @Binding var isScrubbing: Bool
    let onInteraction: () -> Void

    var body: some View {
        ScrubWhisperLine(
            fraction: viewModel.progress,
            prominent: true,
            onScrub: { _ in
                if isScrubbing == false { isScrubbing = true }
                onInteraction()
            },
            onScrubEnd: { fraction in
                viewModel.seekByProgress(fraction)
                isScrubbing = false
            }
        ) { fraction in
            Text(
                viewModel.formatTime(fraction * viewModel.duration)
                    + " / "
                    + viewModel.formatTime(viewModel.duration)
            )
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(viewModel.labelColor)
        }
        .padding(.horizontal, TranceSpacing.screen)
    }
}
