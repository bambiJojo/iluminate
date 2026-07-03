//  ReaderControlCluster.swift
//  Ilumionate
//
//  Revealed-state controls for the Text Trance reader in the shared orbital
//  grammar: End · pause/resume · Settings cluster, with satellites for the
//  live in-trance settings (speed bloom, light, binaural). Deep settings
//  stay in ReaderSettingsDrawer.

import SwiftUI

struct ReaderControlCluster: View {
    @Bindable var session: TextTranceSession
    let onSettings: () -> Void
    let onEnd: () -> Void

    private enum Panel { case speed }
    @State private var bloom = BloomState<Panel>()

    private var speedBinding: Binding<Double> {
        Binding(get: { session.speedMultiplier },
                set: { session.setSpeed(multiplier: $0) })
    }

    var body: some View {
        VStack(spacing: TranceSpacing.cardMargin) {
            if bloom.isOpen(.speed) {
                BloomSliderCapsule(
                    systemImage: "speedometer",
                    value: speedBinding,
                    range: TextPacingEngine.minSpeedMultiplier...TextPacingEngine.maxSpeedMultiplier,
                    valueText: "~\(TextPacingEngine.nominalWPM(forMultiplier: session.speedMultiplier)) wpm")
            }

            HStack(spacing: 36) {
                ClusterGhostButton(label: "End session", systemImage: "xmark", action: onEnd)

                ClusterPlayButton(
                    label: session.isPaused ? "Resume" : "Pause",
                    systemImage: session.isPaused ? "play.fill" : "pause.fill",
                    size: 56
                ) {
                    if session.isPaused { session.resume() } else { session.pause() }
                }

                ClusterGhostButton(label: "Settings", systemImage: "slider.horizontal.3",
                                   action: onSettings)
            }

            HStack(spacing: TranceSpacing.small) {
                SatelliteButton(
                    label: "Reading speed",
                    systemImage: "speedometer",
                    active: bloom.isOpen(.speed)
                ) {
                    TranceHaptics.shared.light()
                    bloom.toggle(.speed)
                }

                if session.settings.arc == .handoff {
                    SatelliteButton(
                        label: session.lightEnabledLive ? "Light pulse on" : "Light pulse off",
                        systemImage: session.lightEnabledLive ? "lightbulb.fill" : "lightbulb",
                        active: session.lightEnabledLive
                    ) { session.setLightEnabled(!session.lightEnabledLive) }
                }

                SatelliteButton(
                    label: session.binauralActive ? "Binaural on" : "Binaural off",
                    systemImage: "waveform",
                    active: session.binauralActive
                ) { session.setBinaural(enabled: !session.binauralActive) }
            }
        }
        .padding(.horizontal, TranceSpacing.screen)
        .padding(.bottom, TranceSpacing.statusBar)
    }
}
