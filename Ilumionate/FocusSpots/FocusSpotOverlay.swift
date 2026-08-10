//
//  FocusSpotOverlay.swift
//  Ilumionate
//
//  The player's focus spot layer: reads the stored preference, applies the
//  lit-field gate, and hands the geometry to `FocusSpotField`.
//

import SwiftUI

struct FocusSpotOverlay: View {
    let mode: PlayerMode
    let mindMachineEnabled: Bool
    let lightSyncEnabled: Bool

    @AppStorage("focusSpotsEnabled") private var isEnabled = false
    /// Read as raw data so a change to the stored geometry re-renders a live
    /// session — the same trick `FlashGridBackground` uses for the tint.
    @AppStorage("focusSpots") private var settingsData: Data?

    private var settings: FocusSpotSettings {
        guard
            let settingsData,
            let decoded = try? JSONDecoder().decode(FocusSpotSettings.self, from: settingsData)
        else {
            return .default
        }
        return decoded.clamped
    }

    var body: some View {
        if FocusSpotVisibility.isVisible(
            mode: mode,
            isEnabled: isEnabled,
            mindMachineEnabled: mindMachineEnabled,
            lightSyncEnabled: lightSyncEnabled
        ) {
            FocusSpotField(settings: settings)
                .ignoresSafeArea()
                // Must never intercept the pull-to-reveal drag on the
                // minimal overlay above it.
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
