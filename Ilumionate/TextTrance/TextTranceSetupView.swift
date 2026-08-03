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
    @State private var speedTraining: ReaderSpeedTrainingSettings = .standard
    @State private var pacingPreset: ReaderPacingPreset = .balanced
    @State private var displayPreferences: ReaderDisplayPreferences = .standard
    @State private var lightEnabled = true
    @State private var binauralEnabled = false
    @State private var subliminalEnabled = true
    @State private var subliminalSpeed: TextPacingSettings.SubliminalSpeed = .medium
    @State private var attentionGateEnabled = false
    @State private var resumeIndex = 0
    @State private var activePlayerSession: TextTranceSession?
    @State private var loadedPreset = false
    @State private var showingAdvancedOptions = false

    private let progressStore = ReaderProgressStore.shared
    private let presetStore = ReaderPresetStore.shared

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
                    ReaderPacingPresetCard(selection: pacingPreset) { preset in
                        pacingPreset = preset
                        speedTraining = preset.settings
                        speedMultiplier = preset.settings.targetSpeedMultiplier
                    }

                    LiminalCard {
                        DisclosureGroup("Advanced options", isExpanded: $showingAdvancedOptions) {
                            VStack(spacing: TranceSpacing.cardMargin) {
                                LayersCard(
                                    arc: arc,
                                    lightEnabled: $lightEnabled,
                                    binauralEnabled: $binauralEnabled
                                )
                                AttentionGateCard(enabled: $attentionGateEnabled)
                                SpeedTrainingCard(settings: $speedTraining)
                                ReaderDisplayCard(preferences: $displayPreferences)
                                SubliminalCard(enabled: $subliminalEnabled, speed: $subliminalSpeed)
                            }
                            .padding(.top, TranceSpacing.list)
                        }
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                        .tint(Color.roseGold)
                    }
                }
                .padding(TranceSpacing.screen)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(script.title)
        .platformInlineNavigationTitle()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: TranceSpacing.list) {
                if let resume = validResume {
                    GlowButton(title: "Resume", systemImage: "play.fill", kind: .primary) {
                        applyResumeSettings(resume)
                        savePreset()
                        launchPlayer(at: resume.wordIndex)
                    }
                    .frame(maxWidth: .infinity)
                    GlowButton(title: "Start over", systemImage: "arrow.counterclockwise", kind: .secondary) {
                        progressStore.clear(scriptId: script.id)
                        savePreset()
                        launchPlayer(at: 0)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    GlowButton(title: "Begin", systemImage: "play.fill", kind: .primary) {
                        savePreset()
                        launchPlayer(at: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.top, TranceSpacing.cardMargin)
            // Lift the buttons clear of the app's floating tab bar.
            .padding(.bottom, TranceSpacing.tabBarClearance)
            .background {
                // Scrim so scrolled cards fade out beneath the launch buttons
                // and tab bar instead of colliding with them.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.bgPrimary.opacity(0.88), location: 0.32),
                        .init(color: Color.bgPrimary.opacity(0.96), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .padding(.top, -TranceSpacing.card)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .platformFullScreenCover(item: $activePlayerSession, onDismiss: handlePlayerDismiss) { session in
            TextTrancePlayerView(session: session, startIndex: resumeIndex)
        }
        .onAppear { loadPresetIfNeeded() }
    }

    private func makeSession() -> TextTranceSession {
        let useLight = arc == .handoff && lightEnabled
        let activeSpeedTraining = normalizedSpeedTraining()
        return TextTranceSession(
            script: script,
            settings: TextTranceSessionSettings(
                arc: arc,
                speedMultiplier: activeSpeedTraining.targetSpeedMultiplier,
                lightEnabled: useLight,
                binauralEnabled: binauralEnabled,
                beatFrequency: 10,
                postHandoffDuration: 600,
                subliminalEnabled: subliminalEnabled,
                subliminalSpeed: subliminalSpeed,
                attentionGateEnabled: attentionGateEnabled,
                speedTraining: activeSpeedTraining,
                displayPreferences: displayPreferences),
            light: useLight ? FlashController(frequency: 10, intensity: 0.7, pattern: .sine) : nil,
            audio: binauralEnabled ? BinauralBeatsEngine() : nil,
            progressStore: progressStore,
            scriptContentHash: contentHash)
    }

    private func launchPlayer(at startIndex: Int) {
        resumeIndex = startIndex
        activePlayerSession = makeSession()
    }

    private func handlePlayerDismiss() {
        if let activePlayerSession, !activePlayerSession.isComplete {
            activePlayerSession.end()
        }
        activePlayerSession = nil
    }

    private func resumeScheduleCount(for settings: PersistedReaderSettings) -> Int {
        TextPacingEngine.schedule(
            for: script,
            settings: TextPacingSettings(
                arc: settings.arc,
                speedMultiplier: 1.0,
                subliminalEnabled: settings.subliminalEnabled,
                subliminalSpeed: settings.subliminalSpeed,
                speedTraining: settings.speedTraining
            )
        ).count
    }

    /// Seed the editable controls from a resume snapshot before launching.
    private func applyResumeSettings(_ s: ReaderResumeState) {
        arc = s.settings.arc
        speedMultiplier = s.settings.speedMultiplier
        speedTraining = normalizedSpeedTraining(from: s.settings)
        pacingPreset = ReaderPacingPreset.closest(to: speedTraining)
        lightEnabled = s.settings.lightEnabled
        binauralEnabled = s.settings.binauralEnabled
        subliminalEnabled = s.settings.subliminalEnabled
        subliminalSpeed = s.settings.subliminalSpeed
        attentionGateEnabled = s.settings.attentionGateEnabled
        displayPreferences = s.settings.displayPreferences
    }

    private func loadPresetIfNeeded() {
        guard !loadedPreset else { return }
        loadedPreset = true
        let preset = presetStore.preset(forScriptId: script.id)
        speedTraining = preset.speedTraining
        pacingPreset = ReaderPacingPreset.closest(to: preset.speedTraining)
        speedMultiplier = preset.speedTraining.targetSpeedMultiplier
        displayPreferences = preset.displayPreferences
    }

    private func savePreset() {
        presetStore.save(
            ReaderPreset(
                speedTraining: normalizedSpeedTraining(),
                displayPreferences: displayPreferences
            ),
            forScriptId: script.id
        )
    }

    private func normalizedSpeedTraining() -> ReaderSpeedTrainingSettings {
        var settings = speedTraining
        settings.targetWPM = min(
            max(settings.targetWPM, ReaderSpeedTrainingSettings.targetWPMRange.lowerBound),
            ReaderSpeedTrainingSettings.targetWPMRange.upperBound
        )
        speedMultiplier = settings.targetSpeedMultiplier
        return settings
    }

    private func normalizedSpeedTraining(from settings: PersistedReaderSettings) -> ReaderSpeedTrainingSettings {
        var speedTraining = settings.speedTraining
        if speedTraining == .standard, settings.speedMultiplier != 1.0 {
            speedTraining.targetWPM = TextPacingEngine.nominalWPM(forMultiplier: settings.speedMultiplier)
        }
        return speedTraining
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
            .tint(.roseGold)
        }
    }

    private var handoffStatusText: String {
        if lightEnabled || binauralEnabled {
            return "Enabled layers continue after the final reading line."
        }
        return "With both layers off, the session ends after the final reading line."
    }
}

private struct SpeedTrainingCard: View {
    @Binding var settings: ReaderSpeedTrainingSettings

    private var targetBinding: Binding<Double> {
        Binding(
            get: { Double(settings.clampedTargetWPM) },
            set: { newValue in
                settings.targetWPM = Int(newValue.rounded())
                settings.warmUpWPM = min(settings.warmUpWPM, settings.targetWPM)
                settings.rampStartWPM = min(settings.rampStartWPM, settings.targetWPM)
            }
        )
    }

    private var warmUpBinding: Binding<Double> {
        Binding(
            get: { Double(settings.clampedWarmUpWPM) },
            set: { settings.warmUpWPM = Int($0.rounded()) }
        )
    }

    private var rampStartBinding: Binding<Double> {
        Binding(
            get: { Double(settings.clampedRampStartWPM) },
            set: { settings.rampStartWPM = Int($0.rounded()) }
        )
    }

    private var chunkBinding: Binding<Int> {
        Binding(
            get: { settings.clampedChunkSize },
            set: { settings.chunkSize = $0 }
        )
    }

    var body: some View {
        LiminalCard(label: "Speed training") {
            VStack(spacing: TranceSpacing.list) {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(ReaderSpeedMode.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)

                SetupControlLabel(text: "\(settings.clampedTargetWPM) wpm target")
                Slider(value: targetBinding,
                       in: ReaderSpeedTrainingSettings.setupTargetWPMRange,
                       step: 5)
                .tint(.roseGold)

                if settings.mode == .warmUp {
                    SetupControlLabel(text: "\(settings.clampedWarmUpWPM) wpm warm-up")
                    Slider(value: warmUpBinding,
                           in: ReaderSpeedTrainingSettings.setupTargetWPMRange,
                           step: 5)
                    .tint(.roseDeep)
                }

                if settings.mode == .ramp {
                    SetupControlLabel(text: "\(settings.clampedRampStartWPM) wpm start")
                    Slider(value: rampStartBinding,
                           in: ReaderSpeedTrainingSettings.setupTargetWPMRange,
                           step: 5)
                    .tint(.roseDeep)
                }

                SetupControlLabel(text: "Words per flash")
                Picker("Chunk size", selection: chunkBinding) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                }
                .pickerStyle(.segmented)

                SetupControlLabel(text: "Punctuation pauses")
                Picker("Punctuation pauses", selection: $settings.punctuationPause) {
                    ForEach(ReaderPunctuationPause.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }
            .tint(.roseGold)
        }
    }
}

private struct ReaderDisplayCard: View {
    @Binding var preferences: ReaderDisplayPreferences

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { preferences.clampedFontScale },
            set: { preferences.fontScale = $0 }
        )
    }

    private var lineSpacingBinding: Binding<Double> {
        Binding(
            get: { preferences.clampedLineSpacing },
            set: { preferences.lineSpacing = $0 }
        )
    }

    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { preferences.clampedBackgroundBrightness },
            set: { preferences.backgroundBrightness = $0 }
        )
    }

    private var visualOpacityBinding: Binding<Double> {
        Binding(
            get: { preferences.clampedVisualOpacity },
            set: { preferences.visualOpacity = $0 }
        )
    }

    var body: some View {
        LiminalCard(label: "Reader display") {
            VStack(spacing: TranceSpacing.list) {
                SetupPickerRow(title: "Theme") {
                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(ReaderTheme.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }

                SetupPickerRow(title: "Font") {
                    Picker("Font", selection: $preferences.font) {
                        ForEach(ReaderFont.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }

                SetupControlLabel(text: "Size \(Int((preferences.clampedFontScale * 100).rounded()))%")
                Slider(value: fontScaleBinding, in: ReaderDisplayPreferences.fontScaleRange)
                    .tint(.roseGold)

                SetupControlLabel(text: "Line \(String(format: "%.1fx", preferences.clampedLineSpacing))")
                Slider(value: lineSpacingBinding, in: ReaderDisplayPreferences.lineSpacingRange)
                    .tint(.roseDeep)

                SetupPickerRow(title: "Highlight color") {
                    Picker("Highlight color", selection: $preferences.orpColor) {
                        ForEach(ReaderORPColor.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }

                SetupControlLabel(text: "Background \(Int((preferences.clampedBackgroundBrightness * 100).rounded()))%")
                Slider(value: brightnessBinding, in: ReaderDisplayPreferences.backgroundBrightnessRange)
                    .tint(.roseGold)

                Toggle("Hide controls by default", isOn: $preferences.hideControls)
                    .tint(.roseGold)
                Toggle("Dyslexia-friendly rendering", isOn: $preferences.dyslexiaFriendly)
                    .tint(.roseGold)

                // Mirrors the Visual section in ReaderSettingsDrawer so the
                // background can be chosen before a session starts, not only
                // mid-read. Both surfaces bind the same preference fields.
                SetupPickerRow(title: "Visual") {
                    Picker("Visual", selection: $preferences.visual) {
                        ForEach(ReaderVisual.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }

                SetupControlLabel(text: preferences.visual.summary)

                if preferences.visual != .none {
                    SetupControlLabel(
                        text: "Strength \(preferences.clampedVisualOpacity.formatted(.percent.precision(.fractionLength(0))))"
                    )
                    Slider(
                        value: visualOpacityBinding,
                        in: ReaderDisplayPreferences.visualOpacityRange
                    )
                    .tint(.roseDeep)
                }
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
                    .tint(.roseGold)
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
                    .tint(.roseGold)
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

/// Caption label above a slider or segmented control in a setup card.
private struct SetupControlLabel: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
    }
}

/// Labeled row hosting a menu-style picker, so the picker's choice reads
/// against a visible title instead of floating as a bare blue menu.
private struct SetupPickerRow<Content: View>: View {
    let title: String
    @ViewBuilder let picker: () -> Content

    var body: some View {
        HStack {
            Text(title)
                .font(TranceTypography.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            picker()
                .tint(.roseGold)
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
