//
//  PlayerControlTile.swift
//  Ilumionate
//
//  One large control tile for the player tray. Sized for one-handed use with
//  eyes closed: a 72pt-tall target with a visible label, and — for value tiles
//  — a gauge fill that doubles as the readout, so volume can be read without
//  touching anything.
//
//  A tile is either tappable or draggable, never both, which keeps gesture
//  arbitration out of the picture entirely.
//

import SwiftUI

struct PlayerControlTile: View {
    enum State: Equatable { case active, normal, disabled }

    let systemImage: String
    let label: String
    var state: State = .normal
    /// 0...1 fill for value tiles. Nil for toggles.
    var value: Double? = nil
    /// A visible readout under the label.
    ///
    /// Nil in the player, where you are configuring with your eyes closed and
    /// the gauge fill is the readout. Set on the Create tab, where you are
    /// looking straight at the tile while choosing — a tile that says "Effect"
    /// but not "Spiral" makes you tap it to find out what it already is.
    var displayValue: String? = nil
    var accessibilityValueText: String? = nil
    var onTap: (() -> Void)? = nil
    var onDragChanged: ((CGFloat) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDraggable: Bool { onDragChanged != nil && state != .disabled }

    var body: some View {
        tile
            .contentShape(.rect(cornerRadius: 16))
            .gesture(isDraggable ? dragGesture : nil)
            .onTapGesture { if !isDraggable { onTap?() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(accessibilityValueText ?? "")
            .accessibilityAddTraits(.isButton)
    }

    private var tile: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundFill)

            if let value, state != .disabled {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.roseGold.opacity(0.16))
                        .frame(height: geo.size.height * max(0, min(1, value)))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .allowsHitTesting(false)
            }

            VStack(spacing: displayValue == nil ? 8 : 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(label)
                    .font(TranceTypography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let displayValue {
                    Text(displayValue)
                        .font(TranceTypography.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Color.roseGold)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 72)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(border, lineWidth: 1)
        )
        .animation(reduceMotion ? nil : LiminalMotion.touch, value: state)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { onDragChanged?($0.translation.height) }
            .onEnded { _ in onDragEnded?() }
    }

    private var backgroundFill: Color {
        switch state {
        case .active:   return Color.roseGold.opacity(0.12)
        case .normal:   return Color.glassFill
        case .disabled: return Color.glassFill.opacity(0.4)
        }
    }

    private var border: Color {
        switch state {
        case .active:   return Color.roseGold.opacity(0.5)
        case .normal:   return Color.glassBorder
        case .disabled: return Color.glassBorder.opacity(0.4)
        }
    }

    private var foreground: Color {
        switch state {
        case .active:   return Color.roseGold
        case .normal:   return Color.textPrimary
        case .disabled: return Color.textLight
        }
    }
}
