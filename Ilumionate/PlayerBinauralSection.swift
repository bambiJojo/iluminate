//
//  PlayerBinauralSection.swift
//  Ilumionate
//
//  Binaural beats toggle for flash mode.
//

import SwiftUI

struct PlayerBinauralSection: View {
    @Bindable var viewModel: UnifiedPlayerViewModel

    var body: some View {
        Button {
            viewModel.toggleBinaural()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: viewModel.binauralActive ? "headphones" : "headphones.circle")
                    .font(.system(size: 24, weight: .light))
                Text(viewModel.binauralActive ? "Binaural On" : "Binaural Off")
                    .font(TranceTypography.caption)
            }
            .foregroundStyle(viewModel.binauralActive ? Color.roseGold : Color.white.opacity(0.8))
        }
    }
}
