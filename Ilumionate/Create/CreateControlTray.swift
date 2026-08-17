//  CreateControlTray.swift
//  Ilumionate
//
//  Create's fixed control tray, in the same grammar as PlayerControlTray: 72pt
//  tiles, drag for continuous values with a haptic tick every 10%, tap for
//  everything else, and a slot list decided once from the session kind so
//  nothing reflows under the user's finger.

import SwiftUI

struct CreateControlTray: View {
    let kind: CreateSessionKind
    @Binding var visual: VisualFieldSettings
    @Bindable var light: MindMachineModel
    @Binding var showingTintSheet: Bool

    @State private var dragStart: [CreateControlSlot: Double] = [:]

    private static let unitMapper = DragValueMapper(range: 0...1)
    private static let frequencyMapper = DragValueMapper(range: 0.5...40.0)
    private static let strengthMapper =
        DragValueMapper(range: VisualModulation.opacityBand)

    private var slots: [CreateControlSlot] { CreateControlSlot.slots(for: kind) }

    private var rows: [[CreateControlSlot]] {
        stride(from: 0, to: slots.count, by: 3).map {
            Array(slots[$0..<min($0 + 3, slots.count)])
        }
    }

    var body: some View {
        VStack(spacing: TranceSpacing.small) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: TranceSpacing.small) {
                    ForEach(rows[row], id: \.self) { slot in
                        tile(for: slot)
                    }
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }

    @ViewBuilder
    private func tile(for slot: CreateControlSlot) -> some View {
        let onTap: (() -> Void)? = slot.isDraggable ? nil : { tap(slot) }
        let onDragChanged: ((CGFloat) -> Void)? =
            slot.isDraggable ? { drag(slot, translation: $0) } : nil

        PlayerControlTile(
            systemImage: symbol(for: slot),
            label: slot.label,
            state: .normal,
            value: gauge(for: slot),
            displayValue: displayValue(for: slot),
            accessibilityValueText: valueText(for: slot),
            onTap: onTap,
            onDragChanged: onDragChanged,
            onDragEnded: slot.isDraggable ? { dragStart[slot] = nil } : nil
        )
    }

    // MARK: - Presentation

    private func symbol(for slot: CreateControlSlot) -> String {
        switch slot {
        case .direction: return visual.direction.systemImage
        default:         return slot.systemImage
        }
    }

    /// 0…1 fill. Nil for tiles whose value is a name rather than a magnitude.
    private func gauge(for slot: CreateControlSlot) -> Double? {
        switch slot {
        case .visualSpeed:
            return visual.speed
        case .strength:
            let band = VisualModulation.opacityBand
            return (visual.clampedOpacity - band.lowerBound)
                / (band.upperBound - band.lowerBound)
        case .frequency:
            return (light.frequency - 0.5) / 39.5
        case .intensity:
            return light.intensity
        case .warmth:
            let options = light.temperatureOptions
            guard let index = options.firstIndex(of: light.colorTemperature),
                  options.count > 1 else { return nil }
            return Double(index) / Double(options.count - 1)
        default:
            return nil
        }
    }

    private func valueText(for slot: CreateControlSlot) -> String {
        switch slot {
        case .effect:      return visual.visual.displayName
        case .tint:        return visual.tint.displayName
        case .direction:   return visual.direction.displayName
        case .duration:    return SessionDurationOption(seconds: visual.duration).accessibilityLabel
        case .visualSpeed: return percent(visual.speed)
        case .strength:    return percent(visual.clampedOpacity)
        case .frequency:
            return "\(light.frequency.formatted(.number.precision(.fractionLength(1)))) hertz"
        case .intensity:   return percent(light.intensity)
        case .warmth:      return "\(light.colorTemperature) kelvin"
        case .waveform:    return light.selectedPattern.rawValue
        case .binaural:    return light.binauralEnabled ? "On" : "Off"
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded())) percent"
    }

    /// The short form shown on the tile itself. Kept terse — a tile is 72pt of
    /// width shared with an icon and a label, so "Inward" fits and
    /// "Drawing toward the centre" does not.
    private func displayValue(for slot: CreateControlSlot) -> String {
        switch slot {
        case .effect:      return visual.visual.displayName
        case .tint:        return visual.tint.displayName
        case .direction:   return visual.direction.displayName
        case .duration:    return SessionDurationOption(seconds: visual.duration).label
        case .visualSpeed: return shortPercent(visual.speed)
        case .strength:    return shortPercent(visual.clampedOpacity)
        case .frequency:
            return "\(light.frequency.formatted(.number.precision(.fractionLength(1)))) Hz"
        case .intensity:   return shortPercent(light.intensity)
        case .warmth:      return "\(light.colorTemperature)K"
        case .waveform:    return light.selectedPattern.rawValue
        case .binaural:    return light.binauralEnabled ? "On" : "Off"
        }
    }

    private func shortPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    // MARK: - Tapping

    private func tap(_ slot: CreateControlSlot) {
        TranceHaptics.shared.selection()
        switch slot {
        case .effect:
            visual.visual = Self.nextEffect(after: visual.visual)
        case .tint:
            showingTintSheet = true
        case .direction:
            visual.direction = visual.direction == .inward ? .outward : .inward
        case .duration:
            visual.duration = SessionDurationOption(seconds: visual.duration).next.seconds
        case .waveform:
            let all = MindMachineModel.LightPattern.allCases
            let index = all.firstIndex(of: light.selectedPattern) ?? 0
            light.selectedPattern = all[(index + 1) % all.count]
        case .binaural:
            light.binauralEnabled.toggle()
        case .visualSpeed, .strength, .frequency, .intensity, .warmth:
            break
        }
    }

    /// `.none` and `.breath` are deliberately skipped: the Visual Field IS the
    /// effect here, so tapping through to "no effect" would tap through to a
    /// black screen. The reader keeps both because there the effect is
    /// decoration behind words.
    private static func nextEffect(after current: TranceVisual) -> TranceVisual {
        let selectable = TranceVisual.allCases.filter { $0.shaderName != nil }
        guard let index = selectable.firstIndex(of: current) else {
            return selectable[0]
        }
        return selectable[(index + 1) % selectable.count]
    }

    // MARK: - Dragging

    private func drag(_ slot: CreateControlSlot, translation: CGFloat) {
        switch slot {
        case .visualSpeed:
            let start = begin(slot, current: visual.speed)
            let new = Self.unitMapper.value(from: start, translation: translation)
            tick(from: visual.speed, to: new, in: 0...1)
            visual.speed = new

        case .strength:
            let band = VisualModulation.opacityBand
            let start = begin(slot, current: visual.clampedOpacity)
            let new = Self.strengthMapper.value(from: start, translation: translation)
            tick(from: visual.clampedOpacity, to: new, in: band)
            visual.opacity = new

        case .frequency:
            let start = begin(slot, current: light.frequency)
            let new = Self.frequencyMapper.value(from: start, translation: translation)
            tick(from: light.frequency, to: new, in: 0.5...40.0)
            light.frequency = new

        case .intensity:
            let start = begin(slot, current: light.intensity)
            let new = Self.unitMapper.value(from: start, translation: translation)
            tick(from: light.intensity, to: new, in: 0...1)
            light.intensity = new

        case .warmth:
            let options = light.temperatureOptions
            let currentIndex = Double(options.firstIndex(of: light.colorTemperature) ?? 0)
            let start = begin(slot, current: currentIndex)
            let mapper = DragValueMapper(range: 0...Double(options.count - 1))
            let index = Int(mapper.value(from: start, translation: translation).rounded())
            if options[index] != light.colorTemperature {
                light.colorTemperature = options[index]
                TranceHaptics.shared.selection()
            }

        case .effect, .tint, .direction, .waveform, .binaural, .duration:
            break
        }
    }

    /// Records where a drag started and ticks once on the way in, so the value
    /// tracks the finger from its own starting point rather than jumping.
    private func begin(_ slot: CreateControlSlot, current: Double) -> Double {
        if let existing = dragStart[slot] { return existing }
        dragStart[slot] = current
        TranceHaptics.shared.selection()
        return current
    }

    /// A haptic tick on every 10% crossing, so a value is legible without looking.
    private func tick(from old: Double, to new: Double, in range: ClosedRange<Double>) {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return }
        let oldStep = Int(((old - range.lowerBound) / span) * 10)
        let newStep = Int(((new - range.lowerBound) / span) * 10)
        if oldStep != newStep { TranceHaptics.shared.selection() }
    }
}
