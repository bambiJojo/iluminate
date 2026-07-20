//
//  PlaylistArtworkMotifs.swift
//  Ilumionate
//
//  The drawn trance/hypnosis motifs used for playlist artwork. Each is a Shape
//  computed from its rect, so a motif renders identically at any size — from an
//  84pt grid tile to the 200pt editor header.
//

import SwiftUI

// MARK: - Shapes

/// Archimedean spiral winding out from the center.
struct SpiralShape: Shape {
    var turns: Double = 3.5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2 * 0.9
        let totalAngle = turns * 2 * .pi
        let steps = max(48, Int(turns * 64))

        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let angle = progress * totalAngle
            let radius = maxRadius * progress
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

/// Concentric rings radiating from the center.
struct ConcentricRingsShape: Shape {
    var count: Int = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2 * 0.92

        for ring in 1...max(1, count) {
            let radius = maxRadius * Double(ring) / Double(count)
            path.addEllipse(in: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        return path
    }
}

/// Stacked sine waves drifting progressively out of phase.
struct DriftingWavesShape: Shape {
    var lines: Int = 6
    var amplitude: Double = 0.07

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 44

        for line in 0..<max(1, lines) {
            let baseline = rect.minY + rect.height * (Double(line) + 1) / Double(lines + 1)
            let phase = Double(line) * 0.7
            path.move(to: CGPoint(x: rect.minX, y: baseline))

            for step in 1...steps {
                let progress = Double(step) / Double(steps)
                let x = rect.minX + rect.width * progress
                let y = baseline + sin(progress * .pi * 2 + phase) * rect.height * amplitude
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

/// Pendulum rod plus its dashed arc of travel (the bob is drawn separately).
struct PendulumFrameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pivot = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.12)
        let bob = PendulumFrameShape.bobCenter(in: rect)

        path.move(to: pivot)
        path.addLine(to: bob)

        // Arc of travel, swinging symmetrically about the pivot.
        let arcY = rect.minY + rect.height * 0.80
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: arcY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.16, y: arcY),
            control: CGPoint(x: rect.midX, y: arcY + rect.height * 0.16)
        )
        return path
    }

    /// Resting position of the bob, shared with the fill layer.
    static func bobCenter(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.74)
    }

    static func bobRadius(in rect: CGRect) -> CGFloat {
        min(rect.width, rect.height) * 0.11
    }
}

/// The pendulum's weighted bob.
struct PendulumBobShape: Shape {
    /// Multiplier on the bob radius — used to draw the surrounding halo.
    var scale: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let center = PendulumFrameShape.bobCenter(in: rect)
        let radius = PendulumFrameShape.bobRadius(in: rect) * scale
        var path = Path()
        path.addEllipse(in: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
        return path
    }
}

// MARK: - Motif Artwork

/// Renders a single motif in a colorway, filling its frame.
struct PlaylistMotifArtwork: View {
    let motif: PlaylistArtworkMotif
    let palette: PlaylistArtworkPalette
    /// Stroke weight scales with the tile so small tiles don't turn to mush.
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Color.bgSecondary
            palette.backdrop

            switch motif {
            case .auto:
                EmptyView()
            case .spiral:
                SpiralShape()
                    .stroke(palette.inkGradient, style: .init(lineWidth: lineWidth, lineCap: .round))
                    .padding(lineWidth)
            case .rings:
                ConcentricRingsShape()
                    .stroke(palette.inkGradient, lineWidth: lineWidth * 0.8)
                    .padding(lineWidth)
                Circle()
                    .fill(palette.glow)
                    .frame(width: lineWidth * 2.4, height: lineWidth * 2.4)
            case .waves:
                DriftingWavesShape()
                    .stroke(palette.inkGradient, style: .init(lineWidth: lineWidth * 0.75, lineCap: .round))
            case .pendulum:
                pendulum
            }
        }
    }

    private var pendulum: some View {
        ZStack {
            PendulumFrameShape()
                .stroke(
                    palette.colors[min(2, palette.colors.count - 1)].opacity(0.55),
                    style: .init(lineWidth: lineWidth * 0.6, lineCap: .round, dash: [lineWidth * 1.6, lineWidth * 2])
                )
            PendulumBobShape(scale: 1.5)
                .fill(palette.glow.opacity(0.22))
            PendulumBobShape()
                .fill(
                    RadialGradient(
                        colors: [palette.colors[0], palette.glow.opacity(0.85)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 40
                    )
                )
        }
        .padding(lineWidth)
    }
}

#Preview("Motifs") {
    ScrollView {
        VStack(spacing: TranceSpacing.card) {
            ForEach(PlaylistArtworkPalette.allCases) { palette in
                HStack(spacing: TranceSpacing.card) {
                    ForEach(PlaylistArtworkMotif.allCases.filter { $0 != .auto }) { motif in
                        PlaylistMotifArtwork(motif: motif, palette: palette)
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: TranceRadius.thumbnail))
                    }
                }
            }
        }
        .padding()
    }
    .background(Color.bgPrimary)
}
