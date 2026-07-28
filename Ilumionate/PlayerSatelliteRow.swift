//
//  PlayerSatelliteRow.swift
//  Ilumionate
//
//  Icon-only satellite controls for the unified player: light sync, volume,
//  light level, and the "more" overflow. Slider satellites bloom a capsule
//  above the row; only one bloom is open at a time.
//

import SwiftUI

struct PlayerSatelliteRow: View {
    @Bindable var viewModel: UnifiedPlayerViewModel
    @Bindable var engine: LightEngine
    @Binding var showingOverflow: Bool

    enum Panel { case volume, light }
    @State private var bloom = BloomState<Panel>()

    private var showVolume: Bool { viewModel.mode.hasVolumeControl }
    private var showLight: Bool { viewModel.mode.hasBrightnessControl }
    private var showLightSync: Bool { viewModel.mode.hasLightSyncToggle }
    private var showOverflow: Bool {
        viewModel.mode.hasBilateralToggle || viewModel.mode.hasBinauralToggle
            || viewModel.mode.hasSmartTransitions || viewModel.mode.hasTrackList
    }
    private var hasAny: Bool { showVolume || showLight || showLightSync || showOverflow }

    var body: some View {
        if hasAny {
            VStack(spacing: TranceSpacing.list) {
                if bloom.isOpen(.volume), showVolume {
                    BloomSliderCapsule(
                        systemImage: "speaker.wave.2.fill",
                        value: $viewModel.volumeDouble,
                        valueText: "\(Int((viewModel.volume * 100).rounded()))%")
                }
                if bloom.isOpen(.light), showLight {
                    BloomSliderCapsule(
                        systemImage: "sun.max.fill",
                        value: $engine.userBrightnessMultiplier,
                        range: 0.1...1.0,
                        valueText: "\(Int((engine.userBrightnessMultiplier * 100).rounded()))%")
                }

                HStack(spacing: TranceSpacing.small) {
                    if showLightSync {
                        SatelliteButton(
                            label: viewModel.lightSyncEnabled ? "Light sync on" : "Light sync off",
                            systemImage: viewModel.lightSyncEnabled ? "lightbulb.fill" : "lightbulb",
                            active: viewModel.lightSyncEnabled
                        ) { viewModel.toggleLightSync() }
                    }
                    if showVolume {
                        SatelliteButton(
                            label: "Volume",
                            systemImage: viewModel.volume > 0
                                ? "speaker.wave.2.fill" : "speaker.slash.fill",
                            active: bloom.isOpen(.volume)
                        ) { toggle(.volume) }
                    }
                    if showLight {
                        SatelliteButton(
                            label: "Light level",
                            systemImage: "sun.max.fill",
                            active: bloom.isOpen(.light)
                        ) { toggle(.light) }
                    }
                    if showOverflow {
                        SatelliteButton(label: "More options", systemImage: "ellipsis") {
                            showingOverflow = true
                        }
                    }
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .animation(.easeInOut(duration: 0.2), value: bloom.open)
        }
    }

    private func toggle(_ panel: Panel) {
        TranceHaptics.shared.light()
        bloom.toggle(panel)
    }
}
