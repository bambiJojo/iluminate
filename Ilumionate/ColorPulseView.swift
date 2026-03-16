//
//  ColorPulseView.swift
//  Ilumionate
//
//  Full-screen color pulse visual mode.
//  Cycles through the hue spectrum while pulsing brightness at the selected
//  therapeutic frequency — distinct from white flash entrainment.
//

import SwiftUI

struct ColorPulseView: View {
    let frequency: Double   // Hz (0.5–40)
    let intensity: Double   // 0–1

    @Environment(\.dismiss) private var dismiss
    @State private var showingControls = true
    @State private var showSafetyWarning = true

    var body: some View {
        if showSafetyWarning {
            safetyWarningView
        } else {
            pulseContent
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingControls.toggle()
                    }
                }
        }
    }

    // MARK: - Pulse Content

    private var pulseContent: some View {
        // 30 Hz update rate is sufficient for smooth hue + brightness transitions
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            // Hue cycles slowly (one full rotation every ~20 s)
            let hue = (elapsed * 0.05).truncatingRemainder(dividingBy: 1.0)
            // Brightness pulses at the therapeutic frequency (0 → intensity → 0)
            let raw = (sin(elapsed * frequency * 2 * .pi) + 1) / 2
            let pulseBrightness = raw * intensity

            ZStack {
                Color(hue: hue, saturation: 0.85, brightness: pulseBrightness)
                    .ignoresSafeArea()

                if showingControls {
                    controls(brightness: pulseBrightness)
                        .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(!showingControls)
        .preferredColorScheme(.dark)
    }

    // MARK: - Controls Overlay

    private func controls(brightness: Double) -> some View {
        VStack {
            HStack {
                Button("End Session", systemImage: "xmark.circle.fill") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.leading, TranceSpacing.screen)
                Spacer()
                VStack(spacing: 2) {
                    Text("\(frequency, specifier: "%.1f") Hz")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Color Pulse")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.trailing, TranceSpacing.screen)
            }
            .padding(.top, TranceSpacing.statusBar)

            Spacer()

            Text("Tap to hide controls")
                .font(TranceTypography.caption)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, TranceSpacing.statusBar)
        }
    }

    // MARK: - Safety Warning

    private var safetyWarningView: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: TranceSpacing.content) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.roseGold)

                Text("Safety Warning")
                    .font(TranceTypography.screenTitle)
                    .foregroundStyle(Color.textPrimary)

                Text(
                    "Color pulse mode uses rapidly changing colored light. " +
                    "Do not use if you have photosensitive epilepsy or are " +
                    "sensitive to flashing or strobing lights."
                )
                .font(TranceTypography.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TranceSpacing.content)

                Button {
                    withAnimation { showSafetyWarning = false }
                } label: {
                    Text("I Understand, Continue")
                        .font(TranceTypography.body)
                        .bold()
                        .foregroundStyle(.white)
                        .padding(.vertical, TranceSpacing.list)
                        .padding(.horizontal, TranceSpacing.content)
                        .background(
                            LinearGradient(
                                colors: [.roseGold, .roseDeep],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(.rect(cornerRadius: TranceRadius.button))
                }

                Button("Cancel") { dismiss() }
                    .foregroundStyle(Color.textSecondary)
                    .font(TranceTypography.body)
            }
            .padding(TranceSpacing.screen)
        }
    }
}

#Preview {
    ColorPulseView(frequency: 10.0, intensity: 0.8)
}
