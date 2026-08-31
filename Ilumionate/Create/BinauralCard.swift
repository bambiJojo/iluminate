//
//  BinauralCard.swift
//  Ilumionate
//
//  Binaural carrier and volume, for the surfaces that expose more than an
//  on/off tile.
//
//  The old "Color Pulse is visual-only" branch is gone: which kinds offer
//  binaural is now expressed structurally by CreateControlSlot.slots(for:),
//  which simply does not give colourPulse a binaural tile. A card explaining
//  why a control it is showing does not apply was always the weaker way to say
//  it.
//

import SwiftUI

struct BinauralCard: View {
    @Bindable var model: MindMachineModel

    // MARK: - Binaural Beats Card

    var body: some View {
        LiminalCard(label: "Binaural Beats") {
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
        case 0.5..<1.0: return "Very Slow"
        case 1.0..<1.5: return "Slow"
        case 1.5..<2.0: return "Medium"
        case 2.0..<2.5: return "Fast"
        default:        return "Very Fast"
        }
    }

    private func brainwaveZoneColor(for frequency: Double) -> Color {
        switch frequency {
        case 0.5..<1.0: return .bwDelta
        case 1.0..<1.5: return .bwTheta
        case 1.5..<2.0: return .bwAlpha
        case 2.0..<2.5: return .bwBeta
        default:        return .bwGamma
        }
    }

    private func binauralDescription(for frequency: Double) -> String {
        switch frequency {
        case 0.5..<1.0: return "Very slow beat"
        case 1.0..<1.5: return "Slow beat"
        case 1.5..<2.0: return "Midrange beat"
        case 2.0..<2.5: return "Fast beat"
        default:        return "Very fast beat"
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
