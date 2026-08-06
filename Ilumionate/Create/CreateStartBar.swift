//
//  CreateStartBar.swift
//  Ilumionate
//
//  The bottom bar of the Create tab: what you are about to start, and the
//  button that starts it. Reads from the kind, so it says the right thing for a
//  wordless field as well as for the light kinds.
//

import SwiftUI

struct CreateStartBar: View {
    let kind: CreateSessionKind
    let visual: VisualFieldSettings
    @Bindable var light: MindMachineModel
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: TranceSpacing.inner) {
            HStack {
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text("Ready to begin")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(summary)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                }

                Spacer()

                Text(trailingValue)
                    .font(TranceTypography.dataReadout)
                    .foregroundStyle(trailingColor)
                    .accessibilityLabel(trailingAccessibilityLabel)
            }

            GlowButton(
                title: kind.startTitle(binauralEnabled: light.binauralEnabled),
                systemImage: kind.startIcon(binauralEnabled: light.binauralEnabled),
                kind: .primary,
                action: onStart
            )
            .accessibilityHint("Opens the full-screen player")
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.top, TranceSpacing.list)
        .padding(.bottom, TranceSpacing.tabBarClearance)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.bgPrimary.opacity(0.94), location: 0.24),
                    .init(color: Color.bgPrimary, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -TranceSpacing.content)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Copy

    private var summary: String {
        switch kind {
        case .visualField:
            return "\(visual.visual.displayName) · \(visual.direction.displayName)"
        case .flash, .bilateral, .colourPulse:
            let hertz = light.frequency.formatted(.number.precision(.fractionLength(1)))
            return "\(light.brainwaveZone) · \(hertz) Hz"
        }
    }

    private var trailingValue: String {
        switch kind {
        case .visualField:
            return visual.clampedOpacity.formatted(.percent.precision(.fractionLength(0)))
        case .flash, .bilateral, .colourPulse:
            return light.intensity.formatted(.percent.precision(.fractionLength(0)))
        }
    }

    private var trailingAccessibilityLabel: String {
        switch kind {
        case .visualField:
            return "Strength \(trailingValue)"
        case .flash, .bilateral, .colourPulse:
            return "Intensity \(trailingValue)"
        }
    }

    private var trailingColor: Color {
        kind == .visualField ? visual.tint.color : light.brainwaveColor
    }
}
