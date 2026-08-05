//  ReaderSettingsDrawer.swift
//  Ilumionate
//
//  Mid-session live-settings sheet. Which groups appear, and whether they are
//  main or advanced, comes from ReaderSettingsCatalog — the same source the
//  setup view reads, so the two surfaces cannot disagree.
//
//  Changes apply immediately via the session's live setters.

import SwiftUI

struct ReaderSettingsDrawer: View {
    @Bindable var session: TextTranceSession
    let attentionStatus: ReaderAttentionMonitorStatus
    /// Passed in live rather than re-read from the store: the Trance tile in the
    /// control tray can change it while the reader is open, and the drawer must
    /// offer the groups for the mode the user is actually in.
    let mode: ReaderMode
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdvanced = false

    private var binauralBinding: Binding<Bool> {
        Binding(get: { session.binauralActive },
                set: { session.setBinaural(enabled: $0) })
    }
    private var subliminalBinding: Binding<Bool> {
        Binding(get: { session.subliminalEnabled },
                set: { session.setSubliminal(enabled: $0, speed: session.subliminalSpeed) })
    }
    private var subliminalSpeedBinding: Binding<TextPacingSettings.SubliminalSpeed> {
        Binding(get: { session.subliminalSpeed },
                set: { session.setSubliminal(enabled: session.subliminalEnabled, speed: $0) })
    }
    private var lightBinding: Binding<Bool> {
        Binding(get: { session.lightEnabledLive },
                set: { session.setLightEnabled($0) })
    }
    private var attentionBinding: Binding<Bool> {
        Binding(get: { session.attentionGateEnabled },
                set: { session.setAttentionGate(enabled: $0) })
    }
    private var speedTrainingBinding: Binding<ReaderSpeedTrainingSettings> {
        Binding(get: { session.speedTraining },
                set: { session.setSpeedTraining($0) })
    }
    private var displayPreferencesBinding: Binding<ReaderDisplayPreferences> {
        Binding(get: { session.displayPreferences },
                set: { session.setDisplayPreferences($0) })
    }

    /// Groups the drawer can actually offer mid-session. Arc and pacing preset
    /// are start-of-session choices — changing them here would invalidate the
    /// schedule the reader is already partway through.
    private func drawerGroups(tier: ReaderSettingsTier) -> [ReaderSettingsGroup] {
        ReaderSettingsGroup.groups(in: mode, tier: tier)
            .filter { $0 != .arc && $0 != .pacingPreset }
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(drawerGroups(tier: .main)) { group in
                    Section(group.title) { rows(for: group) }
                }

                let advanced = drawerGroups(tier: .advanced)
                if !advanced.isEmpty {
                    Section {
                        DisclosureGroup("Advanced", isExpanded: $showingAdvanced) {
                            ForEach(advanced) { group in
                                rows(for: group)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary.ignoresSafeArea())
            .tint(.roseGold)
            .navigationTitle("Settings")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func rows(for group: ReaderSettingsGroup) -> some View {
        switch group {
        case .readingComfort:
            ReadingComfortRows(preferences: displayPreferencesBinding)
        case .speedTarget:
            SpeedTargetRow(settings: speedTrainingBinding)
        case .visual:
            ReaderVisualControls(preferences: displayPreferencesBinding, style: .formSection)
        case .attention:
            Toggle("Require attention", isOn: attentionBinding)
            if session.attentionGateEnabled {
                Label(attentionStatusText, systemImage: attentionStatusImage)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        case .binaural:
            Toggle("Binaural beats", isOn: binauralBinding)
        case .speedDetail:
            ReaderSpeedDetailRows(settings: speedTrainingBinding)
        case .displayDetail:
            ReaderDisplayDetailRows(preferences: displayPreferencesBinding)
        case .subliminal:
            Toggle("Flash suggestion words", isOn: subliminalBinding)
            if session.subliminalEnabled {
                Picker("Flash speed", selection: subliminalSpeedBinding) {
                    ForEach(TextPacingSettings.SubliminalSpeed.allCases) {
                        Text($0.displayName).tag($0)
                    }
                }
            }
        case .lightHandoff:
            if session.settings.arc == .handoff {
                Toggle("Light pulse", isOn: lightBinding)
            }
        case .arc, .pacingPreset:
            EmptyView()   // filtered out by drawerGroups
        }
    }

    private var attentionStatusText: String {
        if session.isAttentionPaused { return "Waiting for attention" }
        if let text = attentionStatus.displayText { return text }
        return session.attentionSatisfied ? "Attention detected" : "Waiting for attention"
    }

    private var attentionStatusImage: String {
        session.attentionSatisfied ? "eye.fill" : "eye.slash.fill"
    }
}

// MARK: - Row groups
//
// Content-only (no Section wrapper) so the drawer can place them either in
// their own Section at main tier or inside the Advanced disclosure.

/// Words per minute as a number — plain reading mode's headline control.
private struct SpeedTargetRow: View {
    @Binding var settings: ReaderSpeedTrainingSettings

    private var targetBinding: Binding<Double> {
        Binding(
            get: { Double(settings.clampedTargetWPM) },
            set: {
                settings.targetWPM = Int($0.rounded())
                settings.warmUpWPM = min(settings.warmUpWPM, settings.targetWPM)
                settings.rampStartWPM = min(settings.rampStartWPM, settings.targetWPM)
            }
        )
    }

    var body: some View {
        LabeledContent("Target", value: "\(settings.clampedTargetWPM) wpm")
        Slider(
            value: targetBinding,
            in: ReaderSpeedTrainingSettings.setupTargetWPMRange,
            step: 5
        )
    }
}

/// The three display controls people actually reach for.
private struct ReadingComfortRows: View {
    @Binding var preferences: ReaderDisplayPreferences

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { preferences.clampedFontScale },
            set: { preferences.fontScale = $0 }
        )
    }

    var body: some View {
        Picker("Reader mode", selection: $preferences.colorMode) {
            ForEach(ReaderColorMode.allCases) { Text($0.displayName).tag($0) }
        }
        Picker("Font", selection: $preferences.font) {
            ForEach(ReaderFont.allCases) { Text($0.displayName).tag($0) }
        }
        LabeledContent("Size", value: "\(Int((preferences.clampedFontScale * 100).rounded()))%")
        Slider(value: fontScaleBinding, in: ReaderDisplayPreferences.fontScaleRange)
    }
}

private struct ReaderSpeedDetailRows: View {
    @Binding var settings: ReaderSpeedTrainingSettings

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
        Picker("Speed mode", selection: $settings.mode) {
            ForEach(ReaderSpeedMode.allCases) { Text($0.displayName).tag($0) }
        }

        if settings.mode == .warmUp {
            LabeledContent("Warm-up", value: "\(settings.clampedWarmUpWPM) wpm")
            Slider(value: warmUpBinding, in: ReaderSpeedTrainingSettings.setupTargetWPMRange, step: 5)
        }

        if settings.mode == .ramp {
            LabeledContent("Ramp start", value: "\(settings.clampedRampStartWPM) wpm")
            Slider(value: rampStartBinding, in: ReaderSpeedTrainingSettings.setupTargetWPMRange, step: 5)
        }

        Picker("Words per flash", selection: chunkBinding) {
            Text("1 word").tag(1)
            Text("2 words").tag(2)
            Text("3 words").tag(3)
        }

        Picker("Punctuation pauses", selection: $settings.punctuationPause) {
            ForEach(ReaderPunctuationPause.allCases) { Text($0.displayName).tag($0) }
        }
    }
}

private struct ReaderDisplayDetailRows: View {
    @Binding var preferences: ReaderDisplayPreferences

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

    var body: some View {
        Picker("Theme", selection: $preferences.theme) {
            ForEach(ReaderTheme.allCases) { Text($0.displayName).tag($0) }
        }

        LabeledContent("Line spacing", value: String(format: "%.1fx", preferences.clampedLineSpacing))
        Slider(value: lineSpacingBinding, in: ReaderDisplayPreferences.lineSpacingRange)

        Picker("Highlight color", selection: $preferences.orpColor) {
            ForEach(ReaderORPColor.allCases) { Text($0.displayName).tag($0) }
        }

        LabeledContent("Background", value: "\(Int((preferences.clampedBackgroundBrightness * 100).rounded()))%")
        Slider(value: brightnessBinding, in: ReaderDisplayPreferences.backgroundBrightnessRange)

        Toggle("Hide controls by default", isOn: $preferences.hideControls)
        Toggle("Dyslexia-friendly rendering", isOn: $preferences.dyslexiaFriendly)
    }
}
