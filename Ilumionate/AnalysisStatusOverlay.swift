//
//  AnalysisStatusOverlay.swift
//  Ilumionate
//
//  Compact overlay bar shown when AI analysis is actively running.
//  Tapping opens the full Analysis Queue management sheet.
//

import SwiftUI

struct AnalysisStatusOverlay: View {

    let analysis: ActiveAnalysis
    let queueCount: Int
    let onTap: () -> Void

    var body: some View {
        Button {
            TranceHaptics.shared.light()
            onTap()
        } label: {
            HStack(spacing: TranceSpacing.inner) {
                // Animated activity indicator
                ProgressView()
                    .tint(.roseGold)
                    .scaleEffect(0.8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.audioFile.displayName)
                        .font(TranceTypography.caption)
                        .bold()
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Text(stageLabel)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                // Progress percentage
                Text(analysis.progress, format: .percent.precision(.fractionLength(0)))
                    .font(TranceTypography.caption)
                    .bold()
                    .foregroundStyle(Color.roseGold)
                    .monospacedDigit()

                if queueCount > 0 {
                    Text("+\(queueCount)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.roseGold.opacity(0.8))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, TranceSpacing.card)
            .padding(.vertical, TranceSpacing.inner)
            .background(.ultraThinMaterial)
            .background(Color.bgCard)
            .clipShape(.rect(cornerRadius: TranceRadius.tabItem))
            .overlay(
                RoundedRectangle(cornerRadius: TranceRadius.tabItem)
                    .strokeBorder(Color.roseGold.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, TranceSpacing.screen)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Analyzing \(analysis.audioFile.displayName), \(Int(analysis.progress * 100)) percent complete")
        .accessibilityAddTraits(.isButton)
    }

    private var stageLabel: String {
        switch analysis.stage {
        case .starting:           "Starting..."
        case .transcribing:       "Transcribing audio..."
        case .analyzing:          "AI analyzing content..."
        case .generatingSession:  "Generating light session..."
        case .complete:           "Complete"
        case .failed:             "Failed"
        }
    }
}
