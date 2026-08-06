//  VisualFieldStage.swift
//  Ilumionate
//
//  The wordless field, full screen. focus: 0 — there is no word to protect, and
//  the compressed centre is the whole point of an inward effect.

import SwiftUI

struct VisualFieldStage: View {
    let settings: VisualFieldSettings
    /// Scales the configured strength. The timed ending rides this down to zero
    /// so a session recedes rather than cutting to black.
    var fade: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VisualFieldLayer(
                visual: settings.visual,
                modulation: settings.modulation(reduceMotion: reduceMotion),
                opacity: settings.clampedOpacity * min(max(fade, 0), 1),
                focus: 0
            )
        }
        .accessibilityHidden(true)
    }
}

/// The rule audio handling in a Visual Field session must obey.
///
/// A named constant rather than a comment because it is the one thing that
/// separates this mode from every other one in the player: elsewhere audio
/// failing means the session has failed, and here it does not — the field is
/// the content, and audio is decoration on top of it.
enum VisualFieldAudioFailure {
    static let leavesFieldRunning = true
}
