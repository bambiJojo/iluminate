//
//  PlayerControlSlot.swift
//  Ilumionate
//
//  Which control tiles the player shows, and what state each one is in.
//
//  `slots(for:)` deliberately takes only a PlayerMode. It has no access to
//  playback state, so no runtime change can add or remove a tile mid-session —
//  the tray cannot reflow under the user's finger.
//

import Foundation

enum PlayerControlSlot: Equatable, CaseIterable {
    case mindMachine
    case lightSync
    case volume
    case brightness
    case more

    // MARK: - Composition

    static func slots(for mode: PlayerMode) -> [PlayerControlSlot] {
        switch mode {
        case .session(let session, let audioFile):
            var slots: [PlayerControlSlot] = audioFile == nil
                ? [.brightness]
                : [.mindMachine, .volume, .brightness]
            if session.binaural_enabled { slots.append(.more) }
            return slots

        case .playlist:
            return [.mindMachine, .volume, .brightness, .more]

        case .audioLight:
            return [.lightSync, .volume, .brightness]

        case .flashMode:
            return [.more]

        case .colorPulse:
            return []
        }
    }

    // MARK: - Presentation

    /// Whether this tile is adjusted by dragging rather than tapping.
    var isDraggable: Bool {
        self == .volume || self == .brightness
    }

    /// Labels stay constant so the tray never reflows and muscle memory holds;
    /// on/off is carried by state, not by the text.
    var label: String {
        switch self {
        case .mindMachine: return "Mind machine"
        case .lightSync:   return "Light sync"
        case .volume:      return "Volume"
        case .brightness:  return "Brightness"
        case .more:        return "More"
        }
    }

    func systemImage(lightsAreOn: Bool) -> String {
        switch self {
        case .mindMachine, .lightSync: return lightsAreOn ? "lightbulb.fill" : "lightbulb"
        case .volume:                  return "speaker.wave.2.fill"
        case .brightness:              return "sun.max.fill"
        case .more:                    return "ellipsis"
        }
    }

    func state(lightsAreOn: Bool) -> PlayerControlTile.State {
        switch self {
        case .mindMachine, .lightSync:
            return lightsAreOn ? .active : .normal
        case .brightness:
            return lightsAreOn ? .normal : .disabled
        case .volume, .more:
            return .normal
        }
    }
}
