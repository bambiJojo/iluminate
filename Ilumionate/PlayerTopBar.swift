//
//  PlayerTopBar.swift
//  Ilumionate
//
//  Top bar for the unified player: close, optional title/subtitle, minimize.
//  Hero modes show the title under the orb (PlayerTitleBlock) instead.
//

import SwiftUI

struct PlayerTopBar: View {
    let viewModel: UnifiedPlayerViewModel
    var showsTitle = true
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

            if showsTitle {
                PlayerTitleBlock(viewModel: viewModel)
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
}
