//
//  PlayerTitleBlock.swift
//  Ilumionate
//
//  Title + context subtitle (phase pill / frequency / track / time) shown
//  under the hero orb in finite-duration modes, and inside the top bar
//  in full-screen light modes.
//

import SwiftUI

struct PlayerTitleBlock: View {
    let viewModel: UnifiedPlayerViewModel

    var body: some View {
        VStack(spacing: TranceSpacing.micro) {
            Text(viewModel.mode.title)
                .font(TranceTypography.trackTitle)
                .foregroundStyle(viewModel.labelColor)
                .lineLimit(1)

            subtitle
        }
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
