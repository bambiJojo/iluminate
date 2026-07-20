//
//  BottomChromeMetrics.swift
//  Ilumionate
//
//  Measured heights of the floating bottom chrome so screens can reserve the
//  right amount of space above it. The analysis overlay grows with its text
//  (stage summary, time estimate, reassurance copy), so it is measured rather
//  than estimated — a fixed guess would let CTAs slip underneath it.
//

import SwiftUI

@MainActor
@Observable
final class BottomChromeMetrics {
    static let shared = BottomChromeMetrics()

    /// Height of the analysis status / recovery overlay. Zero when hidden.
    var analysisOverlayHeight: CGFloat = 0

    private init() {}
}
