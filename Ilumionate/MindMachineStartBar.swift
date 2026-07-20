//
//  MindMachineStartBar.swift
//  Ilumionate
//

import SwiftUI

struct MindMachineStartBar: View {
    @Bindable var model: MindMachineModel
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: TranceSpacing.inner) {
            HStack {
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text("Ready to begin")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text("\(model.brainwaveZone) · \(model.frequency.formatted(.number.precision(.fractionLength(1)))) Hz")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                }

                Spacer()

                Text("\(Int(model.intensity * 100))%")
                    .font(TranceTypography.dataReadout)
                    .foregroundStyle(model.brainwaveColor)
                    .accessibilityLabel("Intensity \(Int(model.intensity * 100)) percent")
            }

            GlowButton(
                title: model.startSessionButtonTitle,
                systemImage: model.startSessionIcon,
                kind: .primary,
                action: onStart
            )
            .accessibilityHint("Opens the full-screen Mind Machine player")
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
}
