//
//  PlayerProgressViews.swift
//  Ilumionate
//
//  Fast-changing playback time is intentionally read inside these leaves. If
//  UnifiedPlayerView reads it directly, its entire full-screen hierarchy is
//  invalidated by the 10 Hz playback clock.
//

import SwiftUI

/// Read-only time in the minimal overlay. Mirrors the style chosen on
/// `PlayerTimeLabel`; it is not tappable because the overlay is one
/// full-screen pull surface.
struct PlayerElapsedTime: View {
    let viewModel: UnifiedPlayerViewModel
    @AppStorage(AppSettingsManager.Key.playerTimeDisplayStyle) private var storedStyle: String?

    var body: some View {
        Text(
            PlayerTimeDisplayStyle(storedValue: storedStyle)
                .text(currentTime: viewModel.currentTime, duration: viewModel.duration)
        )
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(viewModel.secondaryLabelColor.opacity(0.6))
    }
}

/// Time in the full controls. Tapping cycles elapsed / remaining / percentage.
struct PlayerTimeLabel: View {
    let viewModel: UnifiedPlayerViewModel
    @AppStorage(AppSettingsManager.Key.playerTimeDisplayStyle) private var storedStyle: String?

    private var style: PlayerTimeDisplayStyle {
        PlayerTimeDisplayStyle(storedValue: storedStyle)
    }

    var body: some View {
        Button {
            storedStyle = style.next.rawValue
            TranceHaptics.shared.selection()
        } label: {
            Text(style.text(currentTime: viewModel.currentTime, duration: viewModel.duration))
                .font(TranceTypography.caption)
                .foregroundStyle(viewModel.secondaryLabelColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.displayName)
        .accessibilityValue(style.text(currentTime: viewModel.currentTime, duration: viewModel.duration))
        .accessibilityHint("Changes to \(style.next.displayName.lowercased())")
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
