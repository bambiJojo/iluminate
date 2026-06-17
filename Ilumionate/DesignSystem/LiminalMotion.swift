//
//  LiminalMotion.swift
//  Ilumionate
//
//  The three Liminal motion tempos. Centralizing them keeps every
//  surface breathing at the same rate.
//

import SwiftUI

enum LiminalMotion {
    /// Ambient, never-ending: orb breathing, aurora drift.
    static let breathDuration: Double = 5.0
    /// Conic orb-ring rotation period.
    static let orbSpinDuration: Double = 24.0

    /// Screen/sheet transitions.
    static let drift = Animation.spring(response: 0.7, dampingFraction: 0.85)
    /// Touch feedback (press, glow bloom).
    static let touch = Animation.easeInOut(duration: 0.22)
    /// Player controls fade.
    static let fade = Animation.easeInOut(duration: 0.3)

    /// Idle seconds before Pure Void controls auto-hide.
    static let controlsAutoHideDelay: Double = 4.0

    static var breath: Animation { .easeInOut(duration: breathDuration).repeatForever(autoreverses: true) }
    static var orbSpin: Animation { .linear(duration: orbSpinDuration).repeatForever(autoreverses: false) }
}
