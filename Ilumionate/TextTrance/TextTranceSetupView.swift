//  TextTranceSetupView.swift
//  Ilumionate
//
//  Configure a session for the chosen script: arc, optional layers, speed.
//  Builds a TextTranceSession and pushes the player.

import SwiftUI

struct TextTranceSetupView: View {
    let script: TranceScript

    @State private var arc: ScriptArc
    @State private var speed: TextPacingSettings.Speed = .natural
    @State private var lightEnabled = true
    @State private var binauralEnabled = false
    @State private var startPlayer = false

    init(script: TranceScript) {
        self.script = script
        _arc = State(initialValue: script.supportedArcs.first ?? .fullText)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TranceSpacing.cardMargin) {
                ArcCard(script: script, arc: $arc)
                LayersCard(arc: arc, lightEnabled: $lightEnabled, binauralEnabled: $binauralEnabled)
                SpeedCard(speed: $speed)
            }
            .padding(TranceSpacing.screen)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Begin", systemImage: "play.fill") { startPlayer = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.roseGold)
                .controlSize(.large)
                .padding(TranceSpacing.screen)
        }
        .navigationDestination(isPresented: $startPlayer) {
            TextTrancePlayerView(session: makeSession())
                .navigationBarBackButtonHidden()
        }
    }

    private func makeSession() -> TextTranceSession {
        let useLight = arc == .handoff && lightEnabled
        return TextTranceSession(
            script: script,
            settings: TextTranceSessionSettings(
                arc: arc,
                speed: speed,
                lightEnabled: useLight,
                binauralEnabled: binauralEnabled,
                beatFrequency: 10,
                postHandoffDuration: 600),
            light: useLight ? FlashController(frequency: 10, intensity: 0.7, pattern: .sine) : nil,
            audio: binauralEnabled ? BinauralBeatsEngine() : nil)
    }
}

private struct ArcCard: View {
    let script: TranceScript
    @Binding var arc: ScriptArc

    var body: some View {
        GlassCard(label: "Arc") {
            Picker("Arc", selection: $arc) {
                ForEach(script.supportedArcs) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct LayersCard: View {
    let arc: ScriptArc
    @Binding var lightEnabled: Bool
    @Binding var binauralEnabled: Bool

    var body: some View {
        GlassCard(label: "Layers") {
            VStack(spacing: TranceSpacing.list) {
                Toggle("Binaural beats", isOn: $binauralEnabled)
                Text("Requires headphones")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Light runs only in the post-handoff tail in M1.
                if arc == .handoff {
                    Toggle("Light pulse after handoff", isOn: $lightEnabled)
                }
            }
            .tint(Color.roseGold)
        }
    }
}

private struct SpeedCard: View {
    @Binding var speed: TextPacingSettings.Speed

    var body: some View {
        GlassCard(label: "Reading speed") {
            Picker("Speed", selection: $speed) {
                ForEach(TextPacingSettings.Speed.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

#Preview {
    NavigationStack {
        TextTranceSetupView(script: TranceScript(
            schemaVersion: 1, id: "p", title: "Deep Drift", theme: .relaxation,
            supportedArcs: [.fullText, .handoff], language: "en",
            source: ScriptSource(kind: .bundled, generator: nil, reviewed: true),
            segments: [TranceScriptSegment(phase: .induction, text: "rest now",
                pacing: SegmentPacing(baseWPM: 120), arcs: nil, triggersHandoff: nil)]))
    }
}
