//
//  FocusSpotField.swift
//  Ilumionate
//
//  Draws the two focus spots for a given geometry.
//
//  Takes its settings as a parameter rather than reading storage, so the
//  calibration screen can render a working copy that has not been saved yet.
//

import SwiftUI

struct FocusSpotField: View {
    let settings: FocusSpotSettings

    @State private var size: CGSize = .zero

    var body: some View {
        ZStack {
            Color.clear

            if let resolved = FocusSpotLayout.resolve(settings, in: size) {
                spot(diameter: resolved.diameter, at: resolved.left)
                spot(diameter: resolved.diameter, at: resolved.right)
            }
        }
        // `onGeometryChange` rather than a GeometryReader: the reader would
        // impose its own layout on a view that must simply fill its parent.
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
    }

    /// Genuinely opaque: the spot is a hole punched in the light, not a
    /// dimming. SwiftUI antialiases the edge; no feather is applied.
    private func spot(diameter: CGFloat, at centre: CGPoint) -> some View {
        Circle()
            .fill(.black)
            .frame(width: diameter, height: diameter)
            .position(centre)
    }
}

#Preview {
    ZStack {
        Color.orange
        FocusSpotField(settings: .default)
    }
    .ignoresSafeArea()
}
