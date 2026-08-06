//  CreateControlSlot.swift
//  Ilumionate
//
//  Which control tiles the Create tab shows for each session kind.
//
//  `slots(for:)` deliberately takes only a CreateSessionKind. It has no access
//  to any value, so changing a setting can never add or remove a tile — the tray
//  cannot reflow under the user's finger mid-drag. Same rule, same reason, as
//  PlayerControlSlot.slots(for:).

import Foundation

enum CreateControlSlot: String, Equatable, Hashable, CaseIterable, Sendable {
    // Visual field
    case effect
    case tint
    case visualSpeed
    case strength
    case direction
    // Light kinds
    case frequency
    case intensity
    case warmth
    case waveform
    case binaural
    // Shared
    case duration

    // MARK: - Composition

    static func slots(for kind: CreateSessionKind) -> [CreateControlSlot] {
        switch kind {
        case .visualField:
            return [.effect, .tint, .visualSpeed, .strength, .direction, .duration]
        case .flash, .bilateral:
            return [.frequency, .intensity, .warmth, .waveform, .binaural, .duration]
        case .colourPulse:
            return [.frequency, .intensity, .duration]
        }
    }

    // MARK: - Presentation

    /// Whether this tile is adjusted by dragging rather than tapping. A tile is
    /// one or the other, never both — see PlayerControlTile.
    var isDraggable: Bool {
        switch self {
        case .visualSpeed, .strength, .frequency, .intensity, .warmth:
            return true
        case .effect, .tint, .direction, .waveform, .binaural, .duration:
            return false
        }
    }

    /// Labels stay constant so the tray never reflows and muscle memory holds;
    /// the current value is carried by the tile's gauge and value text.
    var label: String {
        switch self {
        case .effect:      return "Effect"
        case .tint:        return "Colour"
        case .visualSpeed: return "Speed"
        case .strength:    return "Strength"
        case .direction:   return "Direction"
        case .frequency:   return "Frequency"
        case .intensity:   return "Intensity"
        case .warmth:      return "Warmth"
        case .waveform:    return "Waveform"
        case .binaural:    return "Binaural"
        case .duration:    return "Duration"
        }
    }

    var systemImage: String {
        switch self {
        case .effect:      return "circle.hexagonpath"
        case .tint:        return "paintpalette"
        case .visualSpeed: return "speedometer"
        case .strength:    return "circle.lefthalf.filled"
        case .direction:   return "arrow.down.right.and.arrow.up.left"
        case .frequency:   return "waveform.path"
        case .intensity:   return "sun.max"
        case .warmth:      return "thermometer.sun"
        case .waveform:    return "waveform"
        case .binaural:    return "headphones"
        case .duration:    return "timer"
        }
    }
}
