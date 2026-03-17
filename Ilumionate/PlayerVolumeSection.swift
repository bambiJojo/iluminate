//
//  PlayerVolumeSection.swift
//  Ilumionate
//
//  Volume slider for the unified player.
//

import SwiftUI

struct PlayerVolumeSection: View {
    @Bindable var viewModel: UnifiedPlayerViewModel

    var body: some View {
        GlassCard(label: "VOLUME") {
            HStack {
                Image(systemName: "speaker.fill")
                    .font(.caption)
                    .foregroundStyle(viewModel.secondaryLabelColor)

                Slider(
                    value: Binding(
                        get: { Double(viewModel.volume) },
                        set: { viewModel.setVolume(Float($0)) }
                    ),
                    in: 0...1
                )
                .tint(viewModel.accentColor)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption)
                    .foregroundStyle(viewModel.secondaryLabelColor)

                Text("\(Int(viewModel.volume * 100))%")
                    .font(TranceTypography.caption)
                    .foregroundStyle(viewModel.secondaryLabelColor)
                    .frame(width: 32)
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }
}
