//
//  PlayerBilateralSection.swift
//  Ilumionate
//
//  Bilateral toggle and drift rate controls for flash mode.
//

import SwiftUI

struct PlayerBilateralSection: View {
    @Bindable var viewModel: UnifiedPlayerViewModel

    var body: some View {
        VStack(spacing: TranceSpacing.list) {
            // Bilateral toggle
            HStack(spacing: 32) {
                Button {
                    viewModel.toggleBilateral()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: viewModel.bilateralMode ? "eyes.inverse" : "eye")
                            .font(.system(size: 24, weight: .light))
                        Text(viewModel.bilateralMode ? "Bilateral" : "Unified")
                            .font(TranceTypography.caption)
                    }
                    .foregroundStyle(viewModel.bilateralMode ? Color.roseGold : Color.white.opacity(0.8))
                }
            }

            // Drift controls (when bilateral active)
            if viewModel.bilateralMode {
                driftControl
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private var driftControl: some View {
        VStack(spacing: 10) {
            driftStateLabel

            HStack(spacing: 10) {
                driftRateButton("Slow", rate: 0.033, subtitle: "30 s")
                driftRateButton("Medium", rate: 0.05, subtitle: "20 s")
                driftRateButton("Fast", rate: 0.1, subtitle: "10 s")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(.rect(cornerRadius: 16))
    }

    private var driftStateLabel: some View {
        let separating = viewModel.bilateralDriftProgress < 0.5
        let icon = separating ? "arrow.left.and.right" : "arrow.right.and.line.vertical.and.arrow.left"
        let label = separating ? "Separating" : "Converging"
        return HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(TranceTypography.caption)
        }
        .foregroundStyle(Color.roseGold.opacity(0.9))
    }

    private func driftRateButton(_ title: String, rate: Double, subtitle: String) -> some View {
        let isSelected = abs(viewModel.bilateralDriftRate - rate) < 0.001
        return Button {
            viewModel.setDriftRate(rate)
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.roseGold.opacity(0.8) : Color.white.opacity(0.5))
            }
            .foregroundStyle(isSelected ? Color.roseGold : Color.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.white.opacity(isSelected ? 0.14 : 0.04))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.roseGold.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
