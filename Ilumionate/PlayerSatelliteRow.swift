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
    /// Called on every tap and every slider movement so the parent can restart
    /// the controls idle timer. Without it the overlay fades out from under the
    /// user mid-tap or mid-drag, because pressing a control is not otherwise
    /// counted as an interaction.
    var onInteraction: () -> Void = {}

    enum Panel { case volume, light }
    @State private var bloom = BloomState<Panel>()

    private var showVolume: Bool { viewModel.mode.hasVolumeControl }
    /// A brightness slider is meaningless with no light output.
    private var showLight: Bool {
        viewModel.mode.hasBrightnessControl && viewModel.mindMachineEnabled
    }
    private var showLightSync: Bool { viewModel.mode.hasLightSyncToggle }
    private var showMindMachine: Bool { viewModel.mode.hasMindMachineToggle }
    private var showOverflow: Bool {
        viewModel.mode.hasBilateralToggle || viewModel.mode.hasBinauralToggle
            || viewModel.mode.hasSmartTransitions || viewModel.mode.hasTrackList
    }
    private var hasAny: Bool {
        showVolume || showLight || showLightSync || showMindMachine || showOverflow
    }

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
                    if showMindMachine {
                        SatelliteButton(
                            label: viewModel.mindMachineEnabled
                                ? "Mind Machine on" : "Mind Machine off",
                            systemImage: viewModel.mindMachineEnabled
                                ? "lightbulb.fill" : "lightbulb",
                            active: viewModel.mindMachineEnabled
                        ) {
                            onInteraction()
                            viewModel.toggleMindMachine()
                        }
                    }
                    if showLightSync {
                        SatelliteButton(
                            label: viewModel.lightSyncEnabled ? "Light sync on" : "Light sync off",
                            systemImage: viewModel.lightSyncEnabled ? "lightbulb.fill" : "lightbulb",
                            active: viewModel.lightSyncEnabled
                        ) {
                            onInteraction()
                            viewModel.toggleLightSync()
                        }
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
                            onInteraction()
                            showingOverflow = true
                        }
                    }
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .animation(.easeInOut(duration: 0.2), value: bloom.open)
            .onChange(of: viewModel.mindMachineEnabled) { _, enabled in
                if !enabled, bloom.isOpen(.light) { bloom.toggle(.light) }
            }
            // Dragging a bloom slider must keep the overlay alive.
            .onChange(of: viewModel.volume) { _, _ in onInteraction() }
            .onChange(of: engine.userBrightnessMultiplier) { _, _ in onInteraction() }
        }
    }

    private func toggle(_ panel: Panel) {
        onInteraction()
        TranceHaptics.shared.light()
        bloom.toggle(panel)
    }
}
