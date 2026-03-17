//
//  PlayerScrubberSection.swift
//  Ilumionate
//
//  Progress scrubber with time labels for the unified player.
//

import SwiftUI

struct PlayerScrubberSection: View {
    @Bindable var viewModel: UnifiedPlayerViewModel

    var body: some View {
        VStack(spacing: TranceSpacing.small) {
            AudioScrubber(progress: .constant(viewModel.progress)) { newProgress in
                viewModel.seekByProgress(newProgress)
            }

            HStack {
                Text(viewModel.formatTime(viewModel.currentTime))
                    .font(TranceTypography.caption)
                    .foregroundStyle(viewModel.secondaryLabelColor)
                    .monospacedDigit()
                Spacer()
                Text(viewModel.formatTime(viewModel.duration))
                    .font(TranceTypography.caption)
                    .foregroundStyle(viewModel.secondaryLabelColor)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }
}
