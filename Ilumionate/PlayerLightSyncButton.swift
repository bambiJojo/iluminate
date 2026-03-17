//
//  PlayerLightSyncButton.swift
//  Ilumionate
//
//  Analysis-aware light sync toggle for audio mode.
//

import SwiftUI

struct PlayerLightSyncButton: View {
    @Bindable var viewModel: UnifiedPlayerViewModel

    var body: some View {
        Button {
            viewModel.toggleLightSync()
        } label: {
            HStack(spacing: 8) {
                statusContent
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(viewModel.lightSyncEnabled ? Color.roseGold : viewModel.labelColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(viewModel.lightSyncEnabled ? Color.roseGold.opacity(0.15) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        viewModel.lightSyncEnabled ? Color.roseGold : Color.glassBorder,
                        lineWidth: 1
                    )
            )
            .clipShape(.rect(cornerRadius: 20))
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.lightSyncStatus {
        case .enabled:
            Image(systemName: "lightbulb.fill")
            Text("Light Sync On")
        case .ready:
            Image(systemName: "lightbulb")
            Text("Enable Light Sync")
        case .analyzing(let progress, let stage):
            ProgressView()
                .controlSize(.small)
                .tint(viewModel.accentColor)
            Text("\(stage) · \(Int(progress * 100))%")
        case .queued(let position):
            Image(systemName: "clock")
            Text(position == 1 ? "Next in queue" : "#\(position) in queue · Prioritize")
        case .unavailable:
            Image(systemName: "sparkles")
            Text("Analyze for Light Sync")
        }
    }
}
