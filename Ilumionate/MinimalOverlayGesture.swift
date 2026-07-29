//
//  MinimalOverlayGesture.swift
//  Ilumionate
//
//  How a touch on the hidden-controls overlay is interpreted.
//
//  Extracted from the view because this decision has been wrong twice: the
//  reveal swipe was previously attached to an ancestor of a full-screen
//  Button, which silently swallowed it. Keeping the thresholds here means
//  they are pinned by tests rather than by hope.
//

import CoreGraphics

enum MinimalOverlayGesture: Equatable {
    /// A deliberate upward swipe: show the controls.
    case reveal
    /// A stationary touch: pulse the hint, but keep the chrome hidden so a
    /// stray brush mid-session does not interrupt.
    case hint
    /// Movement that is neither — a sideways or downward drag. Do nothing.
    case ignore

    /// Upward travel required to count as a deliberate reveal.
    static let revealThreshold: CGFloat = 40
    /// Movement below this in both axes still counts as a tap.
    static let tapSlop: CGFloat = 10

    static func from(translation: CGSize) -> MinimalOverlayGesture {
        if translation.height < -revealThreshold { return .reveal }
        if abs(translation.height) < tapSlop && abs(translation.width) < tapSlop { return .hint }
        return .ignore
    }
}
