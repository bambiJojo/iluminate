//
//  MindMachineView+Binaural.swift
//  Ilumionate
//
//  Binaural beats card for the Mind Machine screen.
//

import SwiftUI

extension MindMachineView {

    // MARK: - Binaural Beats Card

    var binauralCard: some View {
        GlassCard(label: "Binaural Beats") {
            VStack(spacing: TranceSpacing.list) {
                // Toggle row
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable")
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textPrimary)
                        Text("Requires headphones")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Toggle(
                        "Enable binaural beats",
                        isOn: Binding(
                            get: { model.binauralEnabled },
                            set: { model.binauralEnabled = $0; TranceHaptics.shared.selection() }
                        )
                    )
                    .labelsHidden()
                    .tint(.roseGold)
                }

                if model.binauralEnabled {
                    Divider()
                        .background(Color.glassBorder)

                    // Headphones reminder
                    Label("Best experienced with headphones", systemImage: "headphones")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.roseGold.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Carrier frequency
                    BinauralSliderRow(
                        label: "Carrier",
                        value: Binding(
                            get: { model.binauralCarrierFrequency },
                            set: { model.binauralCarrierFrequency = $0 }
                        ),
                        range: 100...400,
                        unit: "Hz"
                    )

                    // Volume
                    BinauralSliderRow(
                        label: "Volume",
                        value: Binding(
                            get: { model.binauralVolume },
                            set: { model.binauralVolume = $0 }
                        ),
                        range: 0...1,
                        unit: "%",
                        displayMultiplier: 100
                    )

                    // Brainwave info
                    binauralBrainwaveInfo
                }
            }
        }
    }

    // MARK: - Brainwave Info Pill

    private var binauralBrainwaveInfo: some View {
        let zone = brainwaveZoneName(for: model.frequency)
        let color = brainwaveZoneColor(for: model.frequency)
        let description = binauralDescription(for: model.frequency)
        return HStack(spacing: TranceSpacing.inner) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(zone) (\(model.frequency, specifier: "%.1f") Hz) — \(description)")
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TranceSpacing.inner)
        .background(color.opacity(0.08))
        .clipShape(.rect(cornerRadius: TranceRadius.tabItem))
    }

    // MARK: - Helpers

    private func brainwaveZoneName(for frequency: Double) -> String {
        switch frequency {
        case 0.5..<4:   return "Delta"
        case 4..<8:     return "Theta"
        case 8..<12:    return "Alpha"
        case 12..<30:   return "Beta"
        default:        return "Gamma"
        }
    }

    private func brainwaveZoneColor(for frequency: Double) -> Color {
        switch frequency {
        case 0.5..<4:   return .bwDelta
        case 4..<8:     return .bwTheta
        case 8..<12:    return .bwAlpha
        case 12..<30:   return .bwBeta
        default:        return .bwGamma
        }
    }

    private func binauralDescription(for frequency: Double) -> String {
        switch frequency {
        case 0.5..<4:   return "Deep sleep / recovery"
        case 4..<8:     return "Hypnosis / creativity"
        case 8..<12:    return "Calm focus / relaxation"
        case 12..<30:   return "Alert concentration"
        default:        return "Peak cognition"
        }
    }
}

// MARK: - Binaural Slider Row

private struct BinauralSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var displayMultiplier: Double = 1

    var displayValue: Double { value * displayMultiplier }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(unit == "%" ? "\(Int(displayValue))\(unit)" : "\(Int(displayValue)) \(unit)")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
            }
            CustomSlider(
                value: $value,
                range: range,
                trackColor: .glassBorder,
                thumbColor: .roseGold,
                activeColor: .roseGold
            )
            .onChange(of: value) { _, _ in TranceHaptics.shared.selection() }
        }
    }
}
