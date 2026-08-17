//
//  FocusSpotVisibility.swift
//  Ilumionate
//
//  Whether the focus spots should be drawn for a given player mode.
//
//  Spots are holes in a lit field. With the lights off the backdrop is flat
//  `bgPrimary`, and two black circles on it read as a rendering bug — so the
//  gate follows the same "are the lights on?" question the control tray asks
//  (`PlayerControlTray.lightsAreOn`).
//

import Foundation

extension PlayerMode {
    /// Whether this mode renders a light field the spots can sit on.
    ///
    /// The visual field opts out: it is a composed shader scene rather than a
    /// driven light field, and two black holes would fight its composition.
    var supportsFocusSpots: Bool {
        switch self {
        case .visualField:
            return false
        case .session, .flashMode, .colorPulse, .audioLight, .playlist:
            return true
        }
    }
}

nonisolated enum FocusSpotVisibility {

    static func isVisible(
        mode: PlayerMode,
        isEnabled: Bool,
        mindMachineEnabled: Bool,
        lightSyncEnabled: Bool
    ) -> Bool {
        guard isEnabled, mode.supportsFocusSpots else { return false }

        switch mode {
        case .flashMode, .colorPulse: return true
        case .audioLight:             return lightSyncEnabled
        case .session, .playlist:     return mindMachineEnabled
        case .visualField:            return false
        }
    }
}
