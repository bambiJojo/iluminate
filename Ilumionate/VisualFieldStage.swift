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
    /// Freezes the field without hiding it. The shader is a TimelineView and
    /// would otherwise animate whenever it is on screen — including while the
    /// player is idle, counting down, or paused, which reads as a session
    /// running behind a player that says it has not started.
    var isPaused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VisualFieldLayer(
                visual: settings.visual,
                modulation: modulation,
                opacity: settings.clampedOpacity * min(max(fade, 0), 1),
                focus: 0
            )
        }
        .accessibilityHidden(true)
    }

    private var modulation: VisualModulation {
        let live = settings.modulation(reduceMotion: reduceMotion)
        return isPaused ? live.stilled : live
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
