//
//  FocusSpotLayout.swift
//  Ilumionate
//
//  Turns a stored `FocusSpotSettings` and a field size into two centre
//  points. Pure and view-free so every clamping rule is unit-testable.
//
//  In bilateral flash mode the field is an HStack of two halves; symmetric
//  centres put exactly one spot in each half for any spacing above zero, so
//  bilateral needs no special case here.
//

import CoreGraphics

nonisolated enum FocusSpotLayout {

    struct Resolved: Equatable, Sendable {
        let diameter: CGFloat
        let left: CGPoint
        let right: CGPoint
    }

    /// Resolves the pair against a field, or `nil` when the field has no area
    /// to draw in (a view measured before its first layout pass).
    static func resolve(_ settings: FocusSpotSettings, in size: CGSize) -> Resolved? {
        guard size.width > 0, size.height > 0 else { return nil }

        let requested = settings.clamped

        // Two spots must fit side by side, and one must fit vertically.
        let diameter = min(CGFloat(requested.diameter), size.width / 2, size.height)
        // The outer edges stay inside the field: a Mac window narrowed to
        // 300pt must not push a spot off-screen.
        let spacing = min(CGFloat(requested.horizontalSpacing), size.width - diameter)
        let y = min(
            max(CGFloat(requested.verticalPosition) * size.height, diameter / 2),
            size.height - diameter / 2
        )
        let midX = size.width / 2

        return Resolved(
            diameter: diameter,
            left: CGPoint(x: midX - spacing / 2, y: y),
            right: CGPoint(x: midX + spacing / 2, y: y)
        )
    }
}
