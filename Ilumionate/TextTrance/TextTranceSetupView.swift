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
    @State private var attentionGateEnabled = false
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
              script.supportedArcs.contains(s.settings.arc),
              s.isUsable(
                contentHash: contentHash,
                scheduleCount: resumeScheduleCount(for: s.settings)
              ) else { return nil }
        return s
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: TranceSpacing.cardMargin) {
                    ScriptOverviewCard(script: script)
                    ArcCard(script: script, arc: $arc)
                    LayersCard(arc: arc, lightEnabled: $lightEnabled, binauralEnabled: $binauralEnabled)
                    AttentionGateCard(enabled: $attentionGateEnabled)
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
                subliminalSpeed: subliminalSpeed,
                attentionGateEnabled: attentionGateEnabled),
            light: useLight ? FlashController(frequency: 10, intensity: 0.7, pattern: .sine) : nil,
            audio: binauralEnabled ? BinauralBeatsEngine() : nil,
            progressStore: progressStore,
            scriptContentHash: contentHash)
    }

    private func resumeScheduleCount(for settings: PersistedReaderSettings) -> Int {
        TextPacingEngine.schedule(
            for: script,
            settings: TextPacingSettings(
                arc: settings.arc,
                speedMultiplier: 1.0,
                subliminalEnabled: settings.subliminalEnabled,
                subliminalSpeed: settings.subliminalSpeed
            )
        ).count
    }

    /// Seed the editable controls from a resume snapshot before launching.
    private func applyResumeSettings(_ s: ReaderResumeState) {
        arc = s.settings.arc
        speedMultiplier = s.settings.speedMultiplier
        lightEnabled = s.settings.lightEnabled
        binauralEnabled = s.settings.binauralEnabled
        subliminalEnabled = s.settings.subliminalEnabled
        subliminalSpeed = s.settings.subliminalSpeed
        attentionGateEnabled = s.settings.attentionGateEnabled
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

private struct ScriptOverviewCard: View {
    let script: TranceScript

    var body: some View {
        LiminalCard(label: "Script") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Text(script.librarySummary)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        SetupMetricPill(systemImage: "clock", text: script.durationSummary)
                        SetupMetricPill(systemImage: "textformat", text: script.wordCountSummary)
                        SetupMetricPill(systemImage: "arrow.triangle.branch", text: script.arcSummary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SetupMetricPill(systemImage: "clock", text: script.durationSummary)
                        SetupMetricPill(systemImage: "textformat", text: script.wordCountSummary)
                        SetupMetricPill(systemImage: "arrow.triangle.branch", text: script.arcSummary)
                    }
                }

                Text(script.phaseSummary)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                    Text(handoffStatusText)
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .tint(.auroraTeal)
        }
    }

    private var handoffStatusText: String {
        if lightEnabled || binauralEnabled {
            return "Enabled layers continue after the final reading line."
        }
        return "With both layers off, the session ends after the final reading line."
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

private struct AttentionGateCard: View {
    @Binding var enabled: Bool

    var body: some View {
        LiminalCard(label: "Attention") {
            VStack(spacing: TranceSpacing.list) {
                Toggle("Require attention", isOn: $enabled)
                    .tint(.auroraTeal)
                Text("Uses the front camera when the reader is open")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

private struct SetupMetricPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(TranceTypography.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.glassBorder.opacity(0.28), in: .capsule)
            .foregroundStyle(Color.textSecondary)
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
