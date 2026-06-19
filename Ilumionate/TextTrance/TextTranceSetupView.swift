//  TextTranceSetupView.swift
//  Ilumionate
//
//  Configure a session for the chosen script: arc, optional layers, speed.
//  Builds a TextTranceSession and presents the immersive player full-screen.

import SwiftUI

struct TextTranceSetupView: View {
    let script: TranceScript

    @State private var arc: ScriptArc
    @State private var speedMultiplier: Double = 1.0
    @State private var lightEnabled = true
    @State private var binauralEnabled = false
    @State private var subliminalEnabled = true
    @State private var subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium
    @State private var startPlayer = false
    @State private var resumeIndex = 0

    private let progressStore = ReaderProgressStore.shared

    init(script: TranceScript) {
        self.script = script
        _arc = State(initialValue: script.supportedArcs.first ?? .fullText)
    }

    private var scriptText: String { script.segments.map(\.text).joined(separator: " ") }
    private var contentHash: String { ReaderResumeState.contentHash(for: scriptText) }

    /// A resume snapshot only if it matches the current script text and is in range.
    private var validResume: ReaderResumeState? {
        guard let s = progressStore.resumeState(forScriptId: script.id),
              s.scriptContentHash == contentHash,
              s.wordIndex > 0 else { return nil }
        return s
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: TranceSpacing.cardMargin) {
                    ArcCard(script: script, arc: $arc)
                    LayersCard(arc: arc, lightEnabled: $lightEnabled, binauralEnabled: $binauralEnabled)
                    SpeedCard(multiplier: $speedMultiplier)
                    SubliminalCard(enabled: $subliminalEnabled, speed: $subliminalSpeed)
                }
                .padding(TranceSpacing.screen)
            }
        }
        .navigationTitle(script.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: TranceSpacing.list) {
                if let resume = validResume {
                    GlowButton(title: "Resume", systemImage: "play.fill", kind: .primary) {
                        applyResumeSettings(resume)
                        resumeIndex = resume.wordIndex
                        startPlayer = true
                    }
                    .frame(maxWidth: .infinity)
                    GlowButton(title: "Start over", systemImage: "arrow.counterclockwise", kind: .secondary) {
                        progressStore.clear(scriptId: script.id)
                        resumeIndex = 0
                        startPlayer = true
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    GlowButton(title: "Begin", systemImage: "play.fill", kind: .primary) {
                        resumeIndex = 0
                        startPlayer = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.top, TranceSpacing.cardMargin)
            // Lift the buttons clear of the app's floating tab bar.
            .padding(.bottom, TranceSpacing.tabBarClearance)
        }
        .fullScreenCover(isPresented: $startPlayer) {
            TextTrancePlayerView(session: makeSession(from: resumeIndex), startIndex: resumeIndex)
        }
    }

    private func makeSession(from startIndex: Int) -> TextTranceSession {
        let useLight = arc == .handoff && lightEnabled
        return TextTranceSession(
            script: script,
            settings: TextTranceSessionSettings(
                arc: arc,
                speedMultiplier: speedMultiplier,
                lightEnabled: useLight,
                binauralEnabled: binauralEnabled,
                beatFrequency: 10,
                postHandoffDuration: 600,
                subliminalEnabled: subliminalEnabled,
                subliminalSpeed: subliminalSpeed),
            light: useLight ? FlashController(frequency: 10, intensity: 0.7, pattern: .sine) : nil,
            audio: binauralEnabled ? BinauralBeatsEngine() : nil,
            progressStore: progressStore,
            scriptContentHash: contentHash)
    }

    /// Seed the editable controls from a resume snapshot before launching.
    private func applyResumeSettings(_ s: ReaderResumeState) {
        arc = s.settings.arc
        speedMultiplier = s.settings.speedMultiplier
        lightEnabled = s.settings.lightEnabled
        binauralEnabled = s.settings.binauralEnabled
        subliminalEnabled = s.settings.subliminalEnabled
        subliminalSpeed = s.settings.subliminalSpeed
    }
}

private struct ArcCard: View {
    let script: TranceScript
    @Binding var arc: ScriptArc

    var body: some View {
        LiminalCard(label: "Arc") {
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
        LiminalCard(label: "Layers") {
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
            .tint(.auroraTeal)
        }
    }
}

private struct SpeedCard: View {
    @Binding var multiplier: Double

    var body: some View {
        LiminalCard(label: "Reading speed") {
            VStack(spacing: TranceSpacing.micro) {
                HStack {
                    Text("~\(TextPacingEngine.nominalWPM(forMultiplier: multiplier)) wpm")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                Slider(value: $multiplier,
                       in: TextPacingEngine.minSpeedMultiplier...TextPacingEngine.maxSpeedMultiplier)
                    .tint(.auroraTeal)
            }
        }
    }
}

private struct SubliminalCard: View {
    @Binding var enabled: Bool
    @Binding var speed: TextPacingSettings.SubliminalSpeed

    var body: some View {
        LiminalCard(label: "Subliminal suggestions") {
            VStack(spacing: TranceSpacing.list) {
                Toggle("Flash suggestion words", isOn: $enabled)
                    .tint(.auroraTeal)
                if enabled {
                    Picker("Flash speed", selection: $speed) {
                        ForEach(TextPacingSettings.SubliminalSpeed.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
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
