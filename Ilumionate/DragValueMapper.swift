//
//  DragValueMapper.swift
//  Ilumionate
//
//  Converts a vertical drag translation into a clamped value. Extracted from
//  the view so the feel of the gesture is testable arithmetic rather than
//  something only a device can tell you about.
//

import CoreGraphics

struct DragValueMapper {
    let range: ClosedRange<Double>

    /// Points of vertical travel that span the full range. Lower is more
    /// sensitive. Tuned for one-handed use without looking at the screen.
    var travel: CGFloat = 150

    /// SwiftUI's y axis grows downward, so dragging up is a negative
    /// translation and must increase the value.
    func value(from start: Double, translation: CGFloat) -> Double {
        guard travel > 0 else { return clamped(start) }
        let span = range.upperBound - range.lowerBound
        let delta = Double(-translation / travel) * span
        return clamped(start + delta)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
