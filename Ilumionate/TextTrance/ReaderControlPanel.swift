//  ReaderControlPanel.swift
//  Ilumionate
//
//  In-session control overlay panel for the Text Trance reader: transport,
//  live speed slider with WPM readout, settings, and end. Purely presentational.

import SwiftUI

struct ReaderControlPanel: View {
    @Bindable var session: TextTranceSession
    let onSettings: () -> Void
    let onEnd: () -> Void

    private var speedBinding: Binding<Double> {
        Binding(get: { session.speedMultiplier },
                set: { session.setSpeed(multiplier: $0) })
    }

    var body: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            speedControl

            HStack(spacing: 40) {
                Button("End", systemImage: "xmark", action: onEnd)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)

                Button {
                    if session.isPaused { session.resume() } else { session.pause() }
                } label: {
                    Image(systemName: session.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.auroraTeal)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(session.isPaused ? "Resume" : "Pause")

                Button("Settings", systemImage: "slider.horizontal.3", action: onSettings)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(TranceSpacing.screen)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.bottom, TranceSpacing.statusBar)
    }

    private var speedControl: some View {
        VStack(spacing: TranceSpacing.micro) {
            HStack {
                Text("Reading speed")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("~\(TextPacingEngine.nominalWPM(forMultiplier: session.speedMultiplier)) wpm")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
            }
            Slider(value: speedBinding,
                   in: TextPacingEngine.minSpeedMultiplier...TextPacingEngine.maxSpeedMultiplier)
                .tint(.auroraTeal)
        }
    }
}
