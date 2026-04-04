//
//  LightScoreEditorView.swift
//  Ilumionate
//
//  Timeline visualization of a generated LightSession's LightMoment entries.
//  Allows viewing and future editing of the light score.
//

import SwiftUI

struct LightScoreEditorView: View {

    let session: LightSession
    let audioFile: AudioFile

    @State private var selectedMomentIndex: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TranceSpacing.content) {
                // Full-width frequency curve
                frequencyCurveSection

                // Intensity curve
                intensityCurveSection

                // Moment list
                momentListSection

                Color.clear.frame(height: TranceSpacing.tabBarClearance)
            }
            .padding(.top, TranceSpacing.content)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Light Score")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Frequency Curve

    private var frequencyCurveSection: some View {
        GlassCard(label: "Frequency (Hz)") {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                LightScoreGraph(
                    moments: session.light_score,
                    duration: session.duration_sec,
                    keyPath: \.frequency,
                    gradientColors: [.roseGold, .bwTheta],
                    selectedIndex: $selectedMomentIndex
                )
                .frame(height: 120)

                HStack {
                    Text("0 Hz")
                        .font(.caption2)
                        .foregroundStyle(Color.textLight)
                    Spacer()
                    if let max = session.light_score.map(\.frequency).max() {
                        Text("\(max, format: .number.precision(.fractionLength(1))) Hz")
                            .font(.caption2)
                            .foregroundStyle(Color.textLight)
                    }
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }

    // MARK: - Intensity Curve

    private var intensityCurveSection: some View {
        GlassCard(label: "Intensity") {
            VStack(alignment: .leading, spacing: TranceSpacing.inner) {
                LightScoreGraph(
                    moments: session.light_score,
                    duration: session.duration_sec,
                    keyPath: \.intensity,
                    gradientColors: [.bwAlpha, .bwGamma],
                    selectedIndex: $selectedMomentIndex
                )
                .frame(height: 80)

                HStack {
                    Text("0%")
                        .font(.caption2)
                        .foregroundStyle(Color.textLight)
                    Spacer()
                    Text("100%")
                        .font(.caption2)
                        .foregroundStyle(Color.textLight)
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }

    // MARK: - Moment List

    private var momentListSection: some View {
        GlassCard(label: "\(session.light_score.count) Light Moments") {
            LazyVStack(spacing: 0) {
                ForEach(session.light_score.indices, id: \.self) { index in
                    let moment = session.light_score[index]
                    let isSelected = selectedMomentIndex == index

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMomentIndex = isSelected ? nil : index
                        }
                    } label: {
                        momentRow(moment, index: index, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)

                    if index < session.light_score.count - 1 {
                        Rectangle()
                            .fill(Color.glassBorder.opacity(0.2))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
    }

    private func momentRow(_ moment: LightMoment, index: Int, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: isSelected ? TranceSpacing.inner : 0) {
            HStack(spacing: TranceSpacing.list) {
                Text(formatTime(moment.time))
                    .font(TranceTypography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 50, alignment: .leading)

                Text("\(moment.frequency, format: .number.precision(.fractionLength(1))) Hz")
                    .font(TranceTypography.body)
                    .bold()
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Text("\(moment.intensity, format: .percent.precision(.fractionLength(0)))")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)

                Text(moment.waveform.displayName)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.roseGold)
            }

            // Expanded detail
            if isSelected {
                HStack(spacing: TranceSpacing.card) {
                    if let ramp = moment.ramp_duration {
                        detailPill(label: "Ramp", value: ramp.formatted(.number.precision(.fractionLength(1))) + "s")
                    }
                    if let bilateral = moment.bilateral, bilateral {
                        detailPill(label: "Bilateral", value: "On")
                    }
                    if let kelvin = moment.color_temperature {
                        detailPill(label: "Color", value: "\(Int(kelvin))K")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, TranceSpacing.inner)
        .background(isSelected ? Color.roseGold.opacity(0.05) : Color.clear)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    private func detailPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textLight)
            Text(value)
                .font(.caption2)
                .bold()
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, TranceSpacing.inner)
        .padding(.vertical, 4)
        .background(Color.glassBorder.opacity(0.1))
        .clipShape(.capsule)
    }

    private func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - Light Score Graph

struct LightScoreGraph: View {
    let moments: [LightMoment]
    let duration: Double
    let keyPath: KeyPath<LightMoment, Double>
    let gradientColors: [Color]
    @Binding var selectedIndex: Int?

    var body: some View {
        Canvas { ctx, size in
            guard moments.count >= 2, duration > 0 else { return }

            let maxVal = moments.map { $0[keyPath: keyPath] }.max() ?? 1
            let minVal = moments.map { $0[keyPath: keyPath] }.min() ?? 0
            let range = max(maxVal - minVal, 0.001)

            let path = Path { p in
                for (i, moment) in moments.enumerated() {
                    let x = (moment.time / duration) * size.width
                    let normalized = (moment[keyPath: keyPath] - minVal) / range
                    let y = size.height - normalized * size.height * 0.9 - size.height * 0.05
                    if i == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }

            ctx.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: gradientColors),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                lineWidth: 2
            )

            // Fill area under curve
            var fillPath = path
            if let lastMoment = moments.last {
                let lastX = (lastMoment.time / duration) * size.width
                fillPath.addLine(to: CGPoint(x: lastX, y: size.height))
                fillPath.addLine(to: CGPoint(x: (moments.first?.time ?? 0) / duration * size.width, y: size.height))
                fillPath.closeSubpath()
            }
            ctx.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: gradientColors.map { $0.opacity(0.15) }),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            // Selected moment indicator
            if let idx = selectedIndex, idx < moments.count {
                let moment = moments[idx]
                let x = (moment.time / duration) * size.width
                let normalized = (moment[keyPath: keyPath] - minVal) / range
                let y = size.height - normalized * size.height * 0.9 - size.height * 0.05

                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
                    with: .color(.roseGold)
                )
            }
        }
    }
}
