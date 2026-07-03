//
//  BloomSliderCapsule.swift
//  Ilumionate
//
//  The floating glass slider that "blooms" above a satellite row (volume,
//  light level, reading speed), plus the exclusive-open state that guarantees
//  only one bloom is visible at a time.
//

import SwiftUI

/// Exclusive-open state for a satellite row's bloom capsules.
struct BloomState<Panel: Equatable> {
    private(set) var open: Panel?

    mutating func toggle(_ panel: Panel) {
        open = (open == panel) ? nil : panel
    }

    mutating func closeAll() { open = nil }

    func isOpen(_ panel: Panel) -> Bool { open == panel }
}

/// A single floating slider capsule. Callers wrap it in a conditional driven
/// by `BloomState` and it transitions in/out (no motion under reduce-motion).
struct BloomSliderCapsule: View {
    let systemImage: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let valueText: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: TranceSpacing.small) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Slider(value: $value, in: range)
                .tint(.roseGold)
            Text(valueText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.glassBorder, lineWidth: 1))
        .padding(.horizontal, TranceSpacing.screen)
        .transition(reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.96)))
    }
}
