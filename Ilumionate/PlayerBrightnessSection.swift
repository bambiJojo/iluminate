//
//  PlayerBrightnessSection.swift
//  Ilumionate
//
//  Light intensity slider for the unified player.
//

import SwiftUI

struct PlayerBrightnessSection: View {
    @Bindable var engine: LightEngine
    let labelColor: Color

    var body: some View {
        GlassCard(label: "LIGHT INTENSITY") {
            HStack {
                Image(systemName: "sun.min.fill")
                    .font(.caption)
                    .foregroundStyle(labelColor.opacity(0.7))

                Slider(value: $engine.userBrightnessMultiplier, in: 0.1...1.0)
                    .tint(labelColor == .white ? .white : .roseGold)

                Image(systemName: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(labelColor.opacity(0.7))

                Text("\(Int(engine.userBrightnessMultiplier * 100))%")
                    .font(TranceTypography.caption)
                    .foregroundStyle(labelColor.opacity(0.7))
                    .frame(width: 32)
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }
}
