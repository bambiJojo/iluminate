//
//  TranceFlowStrip.swift
//  Ilumionate
//
//  Trance Flow visualization for the playlist editor: renders the combined
//  Whole Journey light score as a frequency trajectory against brainwave
//  band guides, with an intensity underlay and phase-colored track chips.
//

import SwiftUI

// MARK: - Model

enum TranceFlowStripModel {

    /// Visible frequency window: alpha at the top, deep delta at the bottom.
    static let maxFrequency: Double = 12.0
    static let minFrequency: Double = 0.5

    struct Sample: Equatable {
        let x: Double            // 0...1 across the playlist duration
        let frequencyY: Double   // 0 = maxFrequency (top), 1 = minFrequency (bottom)
        let intensity: Double    // 0...1
    }

    /// Unit-space samples for drawing. Pure and testable.
    static func samples(from score: [LightMoment], duration: Double) -> [Sample] {
        guard duration > 0, !score.isEmpty else { return [] }
        return score.map { moment in
            let clampedHz = min(max(moment.frequency, minFrequency), maxFrequency)
            return Sample(
                x: min(max(moment.time / duration, 0), 1),
                frequencyY: (maxFrequency - clampedHz) / (maxFrequency - minFrequency),
                intensity: min(max(moment.intensity, 0), 1)
            )
        }
    }

    /// Unit-space y for a band guide line at the given frequency.
    static func bandY(hz: Double) -> Double {
        (maxFrequency - min(max(hz, minFrequency), maxFrequency))
            / (maxFrequency - minFrequency)
    }
}

// MARK: - View

struct TranceFlowStrip: View {
    let session: LightSession
    let phases: [PlaylistWholeSessionPhaseSummary]

    private static let bands: [(label: String, hz: Double)] =
        [("α", 10), ("θ", 6), ("δ", 2)]

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.inner) {
            canvas
                .frame(height: 72)

            if !phases.isEmpty {
                phaseChips
            }
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            let samples = TranceFlowStripModel.samples(
                from: session.light_score, duration: session.duration_sec
            )

            // Band guides
            for band in Self.bands {
                let y = TranceFlowStripModel.bandY(hz: band.hz) * size.height
                var line = Path()
                line.move(to: CGPoint(x: 18, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.glassBorder), lineWidth: 0.6)
                context.draw(
                    Text("\(band.label) \(Int(band.hz))Hz")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.textLight),
                    at: CGPoint(x: 9, y: y - 5)
                )
            }

            guard samples.count > 1 else { return }

            // Phase boundaries
            for phase in phases.dropFirst() where session.duration_sec > 0 {
                let x = phase.startTime / session.duration_sec * size.width
                var boundary = Path()
                boundary.move(to: CGPoint(x: x, y: 2))
                boundary.addLine(to: CGPoint(x: x, y: size.height - 2))
                context.stroke(boundary, with: .color(.glassBorder),
                               style: StrokeStyle(lineWidth: 0.8, dash: [2, 3]))
            }

            // Intensity underlay
            var underlay = Path()
            underlay.move(to: CGPoint(x: samples[0].x * size.width, y: size.height))
            for sample in samples {
                underlay.addLine(to: CGPoint(
                    x: sample.x * size.width,
                    y: size.height * (1 - sample.intensity * 0.4)
                ))
            }
            underlay.addLine(to: CGPoint(x: samples[samples.count - 1].x * size.width,
                                         y: size.height))
            underlay.closeSubpath()
            context.fill(underlay, with: .color(Color.roseDeep.opacity(0.10)))

            // Frequency trajectory
            var curve = Path()
            curve.move(to: point(samples[0], in: size))
            for sample in samples.dropFirst() {
                curve.addLine(to: point(sample, in: size))
            }
            context.stroke(
                curve,
                with: .linearGradient(
                    Gradient(colors: [.bwAlpha, .bwTheta, .bwDelta, .roseGold]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func point(_ sample: TranceFlowStripModel.Sample, in size: CGSize) -> CGPoint {
        CGPoint(x: sample.x * size.width, y: sample.frequencyY * size.height)
    }

    private var phaseChips: some View {
        HStack(spacing: 4) {
            ForEach(phases) { phase in
                VStack(spacing: 3) {
                    Text(phase.role.displayName)
                        .font(.system(size: 8))
                        .foregroundStyle(.textLight)
                        .lineLimit(1)
                    Capsule()
                        .fill(phaseColor(for: phase.phase))
                        .frame(height: 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func phaseColor(for phase: HypnosisMetadata.Phase) -> Color {
        switch phase {
        case .preTalk:
            return .phaseIntro
        case .induction:
            return .phaseInduction
        case .deepening, .confusion, .transitional:
            return .phaseDeepener
        case .fractionation:
            return .phaseFractionation
        case .suggestions, .therapy, .eroticSuggestions, .conditioning, .brainwashing:
            return .phaseSuggestion
        case .emergence:
            return .phaseAwakening
        }
    }
}
