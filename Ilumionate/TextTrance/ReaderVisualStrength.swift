//  ReaderVisualStrength.swift
//  Ilumionate
//
//  Where a drag on the reader's Trance tile lands. Pure arithmetic, kept out of
//  the view so the off-threshold behaviour is testable rather than something
//  only a device can tell you about — same reasoning as DragValueMapper.

import Foundation

enum ReaderVisualStrength {
    /// Drag travel for the Trance tile. Starts at 0, below the visual's own
    /// minimum strength, so the bottom of the drag is fully off rather than
    /// merely faint.
    static let dragRange: ClosedRange<Double> =
        0...ReaderDisplayPreferences.visualOpacityRange.upperBound

    /// Below this the effect switches off entirely, stopping the shader instead
    /// of drawing it at an invisible opacity.
    static var offThreshold: Double {
        ReaderDisplayPreferences.visualOpacityRange.lowerBound
    }

    struct Resolution: Equatable {
        let visual: TranceVisual
        let opacity: Double
    }

    /// Resolve a dragged value into the effect and strength it implies.
    ///
    /// - `restoring` is the effect to come back to when the drag rises out of
    ///   the off zone; it must not be `.none` or switching on would show nothing.
    static func resolve(
        draggedValue: Double,
        current: TranceVisual,
        currentOpacity: Double,
        restoring restorable: TranceVisual
    ) -> Resolution {
        guard draggedValue >= offThreshold else {
            // Hold the last opacity so coming back on does not also reset it.
            return Resolution(visual: .none, opacity: currentOpacity)
        }
        let visual = current == .none ? restorable : current
        return Resolution(visual: visual, opacity: draggedValue)
    }

    /// Gauge fill, 0...1. Zero whenever the effect is off, so an empty gauge is
    /// itself the "off" signal.
    static func gauge(visual: TranceVisual, opacity: Double) -> Double {
        guard visual != .none else { return 0 }
        let span = dragRange.upperBound - dragRange.lowerBound
        guard span > 0 else { return 0 }
        return min(max((opacity - dragRange.lowerBound) / span, 0), 1)
    }
}
