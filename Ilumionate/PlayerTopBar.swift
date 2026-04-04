//
//  PlayerTopBar.swift
//  Ilumionate
//
//  Top bar for the unified player: close, title/subtitle, minimize.
//

import SwiftUI

struct PlayerTopBar: View {
    let viewModel: UnifiedPlayerViewModel
    let onClose: () -> Void
    let onMinimize: () -> Void

    var body: some View {
        HStack {
            Button("Close", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(viewModel.labelColor)
                .buttonStyle(PlayerButtonStyle())

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.mode.title)
                    .font(TranceTypography.trackTitle)
                    .foregroundStyle(viewModel.labelColor)
                    .lineLimit(1)

                subtitle
            }

            Spacer()

            Button("Minimize to mini player", systemImage: "chevron.down", action: onMinimize)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(viewModel.secondaryLabelColor)
                .buttonStyle(PlayerButtonStyle())
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.statusBar)
    }

    @ViewBuilder
    private var subtitle: some View {
        if viewModel.mode.hasPhaseIndicator {
            PhasePill(phase: viewModel.currentPhase)
        } else if viewModel.mode.hasFrequencyDisplay {
            HStack(spacing: 6) {
                Text("\(viewModel.flashFrequency, format: .number.precision(.fractionLength(1))) Hz")
                    .font(TranceTypography.caption)
                    .foregroundStyle(viewModel.secondaryLabelColor)
                if case .flashMode(_, _, let colorTemp, _, _, _, _) = viewModel.mode {
                    Text("·")
                        .foregroundStyle(viewModel.secondaryLabelColor.opacity(0.5))
                    Text("\(colorTemp)K")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.fromKelvin(colorTemp))
                }
            }
        } else if viewModel.mode.hasTrackNavigation {
            Text("\(viewModel.currentTrackIndex + 1) of \(viewModel.trackCount) — \(viewModel.currentTrackName)")
                .font(TranceTypography.caption)
                .foregroundStyle(viewModel.secondaryLabelColor)
                .lineLimit(1)
        } else {
            Text(viewModel.formatTime(viewModel.currentTime) + " / " + viewModel.formatTime(viewModel.duration))
                .font(TranceTypography.caption)
                .foregroundStyle(viewModel.secondaryLabelColor)
                .monospacedDigit()
        }
    }
}
