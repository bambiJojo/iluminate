//
//  PlayerSecondaryControls.swift
//  Ilumionate
//
//  A calm row of control pills (light sync, volume, light level). Slider pills
//  expand their control inline; only one is open at a time. Replaces the stacked
//  VOLUME / LIGHT INTENSITY glass cards with a single tidy surface.
//

import SwiftUI

struct PlayerSecondaryControls: View {
    @Bindable var viewModel: UnifiedPlayerViewModel
    @Bindable var engine: LightEngine

    private enum Panel { case volume, light }
    @State private var open: Panel?

    // Session-with-audio handles volume in its own SYNC OPTIONS card, so skip the
    // volume pill there to avoid a duplicate control.
    private var showVolume: Bool { viewModel.mode.hasVolumeControl && !viewModel.mode.hasSyncOptions }
    private var showLight: Bool { viewModel.mode.hasBrightnessControl }
    private var showLightSync: Bool { viewModel.mode.hasLightSyncToggle }
    private var hasAny: Bool { showVolume || showLight || showLightSync }

    var body: some View {
        if hasAny {
            VStack(spacing: TranceSpacing.list) {
                // Expanded slider appears ABOVE the pill row (popover-style) so it
                // is never clipped by the bottom of the screen.
                if open == .volume, showVolume {
                    sliderRow(
                        minIcon: "speaker.fill", maxIcon: "speaker.wave.3.fill",
                        value: Binding(get: { Double(viewModel.volume) }, set: { viewModel.setVolume(Float($0)) }),
                        percent: Int((viewModel.volume * 100).rounded())
                    )
                }
                if open == .light, showLight {
                    sliderRow(
                        minIcon: "sun.min.fill", maxIcon: "sun.max.fill",
                        value: $engine.userBrightnessMultiplier, range: 0.1...1.0,
                        percent: Int((engine.userBrightnessMultiplier * 100).rounded())
                    )
                }

                HStack(spacing: TranceSpacing.small) {
                    if showLightSync {
                        Button { viewModel.toggleLightSync() } label: {
                            pillLabel(
                                title: viewModel.lightSyncEnabled ? "Light Sync On" : "Light Sync",
                                icon: viewModel.lightSyncEnabled ? "lightbulb.fill" : "lightbulb",
                                active: viewModel.lightSyncEnabled
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if showVolume {
                        Button { toggle(.volume) } label: {
                            pillLabel(
                                title: "Volume",
                                icon: viewModel.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                active: open == .volume
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if showLight {
                        Button { toggle(.light) } label: {
                            pillLabel(title: "Light", icon: "sun.max.fill", active: open == .light)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .animation(.easeInOut(duration: 0.2), value: open)
        }
    }

    private func toggle(_ panel: Panel) {
        TranceHaptics.shared.light()
        open = (open == panel) ? nil : panel
    }

    private func pillLabel(title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(active ? Color.roseGold : viewModel.labelColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(active ? Color.roseGold.opacity(0.15) : Color.glassFill)
        .overlay(
            Capsule().strokeBorder(active ? Color.roseGold.opacity(0.5) : Color.glassBorder, lineWidth: 1)
        )
        .clipShape(.capsule)
    }

    private func sliderRow(
        minIcon: String, maxIcon: String,
        value: Binding<Double>, range: ClosedRange<Double> = 0...1, percent: Int
    ) -> some View {
        HStack {
            Image(systemName: minIcon)
                .font(.caption)
                .foregroundStyle(viewModel.secondaryLabelColor)
            Slider(value: value, in: range)
                .tint(viewModel.accentColor)
            Image(systemName: maxIcon)
                .font(.caption)
                .foregroundStyle(viewModel.secondaryLabelColor)
            Text("\(percent)%")
                .font(TranceTypography.caption)
                .foregroundStyle(viewModel.secondaryLabelColor)
                .frame(width: 32)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.glassFill, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).strokeBorder(Color.glassBorder, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
