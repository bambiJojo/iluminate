//
//  PlayerControlTray.swift
//  Ilumionate
//
//  The player's fixed control row. Slots are decided once from the mode and
//  never change while playing; toggling the mind machine changes a tile's
//  state, never whether it exists.
//

import SwiftUI

struct PlayerControlTray: View {
    @Bindable var viewModel: UnifiedPlayerViewModel
    @Bindable var engine: LightEngine
    @Binding var showingOverflow: Bool
    /// Restarts the controls idle timer on every touch.
    var onInteraction: () -> Void = {}

    @State private var volumeDragStart: Double?
    @State private var brightnessDragStart: Double?
    @State private var visualSpeedDragStart: Double?
    @State private var visualStrengthDragStart: Double?

    private static let volumeMapper = DragValueMapper(range: 0...1)
    private static let brightnessMapper = DragValueMapper(range: 0.1...1.0)
    private static let visualSpeedMapper = DragValueMapper(range: 0...1)
    private static let visualStrengthMapper =
        DragValueMapper(range: VisualModulation.opacityBand)

    private var slots: [PlayerControlSlot] { PlayerControlSlot.slots(for: viewModel.mode) }

    /// `.audioLight` gates its lights with its own Light Sync control; every
    /// other mode uses the mind machine gate.
    private var lightsAreOn: Bool {
        if case .audioLight = viewModel.mode { return viewModel.lightSyncEnabled }
        return viewModel.mindMachineEnabled
    }

    var body: some View {
        if !slots.isEmpty {
            HStack(spacing: TranceSpacing.small) {
                ForEach(slots, id: \.self) { slot in
                    tile(for: slot)
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .animation(LiminalMotion.fade, value: lightsAreOn)
        }
    }

    @ViewBuilder
    private func tile(for slot: PlayerControlSlot) -> some View {
        // Handled here rather than in PlayerControlSlot.state(lightsAreOn:),
        // which deliberately takes no view-model state. The tile's PRESENCE
        // still comes only from the mode, so the tray does not reflow — only
        // its state changes.
        let state: PlayerControlTile.State =
            (slot == .volume && viewModel.audioUnavailable)
                ? .disabled
                : slot.state(lightsAreOn: lightsAreOn)

        PlayerControlTile(
            systemImage: slot.systemImage(lightsAreOn: lightsAreOn),
            label: slot.label,
            state: state,
            value: value(for: slot),
            accessibilityValueText: accessibilityValue(for: slot, state: state),
            onTap: slot.isDraggable ? tapForDisabledValueTile(slot, state: state) : { tap(slot) },
            onDragChanged: slot.isDraggable ? { drag(slot, translation: $0) } : nil,
            onDragEnded: slot.isDraggable ? { endDrag(slot) } : nil
        )
    }

    // MARK: - Values

    private func value(for slot: PlayerControlSlot) -> Double? {
        switch slot {
        case .volume:     return viewModel.volumeDouble
        case .brightness: return engine.userBrightnessMultiplier
        case .visualSpeed: return viewModel.visualFieldSettings.speed
        case .visualStrength:
            let band = VisualModulation.opacityBand
            return (viewModel.visualFieldSettings.clampedOpacity - band.lowerBound)
                / (band.upperBound - band.lowerBound)
        default:          return nil
        }
    }

    private func accessibilityValue(
        for slot: PlayerControlSlot,
        state: PlayerControlTile.State
    ) -> String? {
        if state == .disabled { return "Unavailable while the mind machine is off" }
        guard let value = value(for: slot) else {
            return state == .active ? "On" : nil
        }
        return "\(Int((value * 100).rounded())) percent"
    }

    // MARK: - Actions

    /// Reaching for brightness with the lights off means you want the lights.
    private func tapForDisabledValueTile(
        _ slot: PlayerControlSlot,
        state: PlayerControlTile.State
    ) -> (() -> Void)? {
        guard slot == .brightness, state == .disabled else { return nil }
        return {
            onInteraction()
            viewModel.toggleMindMachine()
        }
    }

    private func tap(_ slot: PlayerControlSlot) {
        onInteraction()
        switch slot {
        case .mindMachine: viewModel.toggleMindMachine()
        case .lightSync:   viewModel.toggleLightSync()
        case .more:        showingOverflow = true
        case .volume, .brightness, .visualStrength, .visualSpeed: break
        }
    }

    private func drag(_ slot: PlayerControlSlot, translation: CGFloat) {
        onInteraction()
        switch slot {
        case .volume:
            let start = volumeDragStart ?? viewModel.volumeDouble
            if volumeDragStart == nil {
                volumeDragStart = start
                TranceHaptics.shared.selection()
            }
            let old = viewModel.volumeDouble
            let new = Self.volumeMapper.value(from: start, translation: translation)
            viewModel.volumeDouble = new
            tick(from: old, to: new, in: 0...1)

        case .brightness:
            let start = brightnessDragStart ?? engine.userBrightnessMultiplier
            if brightnessDragStart == nil {
                brightnessDragStart = start
                TranceHaptics.shared.selection()
            }
            let old = engine.userBrightnessMultiplier
            let new = Self.brightnessMapper.value(from: start, translation: translation)
            engine.userBrightnessMultiplier = new
            tick(from: old, to: new, in: 0.1...1.0)

        case .visualSpeed:
            let start = visualSpeedDragStart ?? viewModel.visualFieldSettings.speed
            if visualSpeedDragStart == nil {
                visualSpeedDragStart = start
                TranceHaptics.shared.selection()
            }
            let old = viewModel.visualFieldSettings.speed
            let new = Self.visualSpeedMapper.value(from: start, translation: translation)
            viewModel.visualFieldSettings.speed = new
            tick(from: old, to: new, in: 0...1)

        case .visualStrength:
            let band = VisualModulation.opacityBand
            let start = visualStrengthDragStart
                ?? viewModel.visualFieldSettings.clampedOpacity
            if visualStrengthDragStart == nil {
                visualStrengthDragStart = start
                TranceHaptics.shared.selection()
            }
            let old = viewModel.visualFieldSettings.clampedOpacity
            let new = Self.visualStrengthMapper.value(from: start, translation: translation)
            viewModel.visualFieldSettings.opacity = new
            tick(from: old, to: new, in: band)

        default:
            break
        }
    }

    private func endDrag(_ slot: PlayerControlSlot) {
        switch slot {
        case .volume:     volumeDragStart = nil
        case .brightness: brightnessDragStart = nil
        case .visualSpeed: visualSpeedDragStart = nil
        case .visualStrength: visualStrengthDragStart = nil
        default:          break
        }
    }

    /// A haptic tick on every 10% crossing, so the value is legible without looking.
    private func tick(from old: Double, to new: Double, in range: ClosedRange<Double>) {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return }
        let oldStep = Int(((old - range.lowerBound) / span) * 10)
        let newStep = Int(((new - range.lowerBound) / span) * 10)
        if oldStep != newStep { TranceHaptics.shared.selection() }
    }
}
