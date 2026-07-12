//  ReaderSettingsDrawer.swift
//  Ilumionate
//
//  Mid-session live-settings sheet: binaural, subliminal, and (handoff) light.
//  Changes apply immediately via the session's live setters.

import SwiftUI

struct ReaderSettingsDrawer: View {
    @Bindable var session: TextTranceSession
    let attentionStatus: ReaderAttentionMonitorStatus
    @Environment(\.dismiss) private var dismiss

    private var binauralBinding: Binding<Bool> {
        Binding(get: { session.binauralActive },
                set: { session.setBinaural(enabled: $0) })
    }
    private var narrationBinding: Binding<Bool> {
        Binding(get: { session.narrationActive },
                set: { session.setNarration(enabled: $0) })
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

    var body: some View {
        NavigationStack {
            Form {
                ReaderSpeedTrainingFormSection(settings: speedTrainingBinding)
                ReaderDisplayFormSection(preferences: displayPreferencesBinding)
                Section("Attention") {
                    Toggle("Require attention", isOn: attentionBinding)
                    if session.attentionGateEnabled {
                        Label(attentionStatusText, systemImage: attentionStatusImage)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Section("Narration") {
                    Toggle("Voice narration", isOn: narrationBinding)
                    Text("Speaks from the current word and follows pause, resume, and section jumps.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Section("Binaural beats") {
                    Toggle("Enabled", isOn: binauralBinding)
                }
                Section("Subliminal flashing") {
                    Toggle("Flash suggestion words", isOn: subliminalBinding)
                    if session.subliminalEnabled {
                        Picker("Flash speed", selection: subliminalSpeedBinding) {
                            ForEach(TextPacingSettings.SubliminalSpeed.allCases) {
                                Text($0.displayName).tag($0)
                            }
                        }
                    }
                }
                if session.settings.arc == .handoff {
                    Section("After handoff") {
                        Toggle("Light pulse", isOn: lightBinding)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bgPrimary.ignoresSafeArea())
            .tint(.auroraTeal)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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

private struct ReaderSpeedTrainingFormSection: View {
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
        Section("Speed training") {
            Picker("Mode", selection: $settings.mode) {
                ForEach(ReaderSpeedMode.allCases) {
                    Text($0.displayName).tag($0)
                }
            }

            LabeledContent("Target", value: "\(settings.clampedTargetWPM) wpm")
            Slider(
                value: targetBinding,
                in: ReaderSpeedTrainingSettings.setupTargetWPMRange,
                step: 5
            )

            if settings.mode == .warmUp {
                LabeledContent("Warm-up", value: "\(settings.clampedWarmUpWPM) wpm")
                Slider(
                    value: warmUpBinding,
                    in: ReaderSpeedTrainingSettings.setupTargetWPMRange,
                    step: 5
                )
            }

            if settings.mode == .ramp {
                LabeledContent("Ramp start", value: "\(settings.clampedRampStartWPM) wpm")
                Slider(
                    value: rampStartBinding,
                    in: ReaderSpeedTrainingSettings.setupTargetWPMRange,
                    step: 5
                )
            }

            Picker("Words per flash", selection: chunkBinding) {
                Text("1 word").tag(1)
                Text("2 words").tag(2)
                Text("3 words").tag(3)
            }

            Picker("Punctuation pauses", selection: $settings.punctuationPause) {
                ForEach(ReaderPunctuationPause.allCases) {
                    Text($0.displayName).tag($0)
                }
            }
        }
    }
}

private struct ReaderDisplayFormSection: View {
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

    var body: some View {
        Section("Reader display") {
            Picker("Theme", selection: $preferences.theme) {
                ForEach(ReaderTheme.allCases) {
                    Text($0.displayName).tag($0)
                }
            }

            Picker("Font", selection: $preferences.font) {
                ForEach(ReaderFont.allCases) {
                    Text($0.displayName).tag($0)
                }
            }

            LabeledContent("Size", value: "\(Int((preferences.clampedFontScale * 100).rounded()))%")
            Slider(value: fontScaleBinding, in: ReaderDisplayPreferences.fontScaleRange)

            LabeledContent("Line spacing", value: String(format: "%.1fx", preferences.clampedLineSpacing))
            Slider(value: lineSpacingBinding, in: ReaderDisplayPreferences.lineSpacingRange)

            Picker("Highlight color", selection: $preferences.orpColor) {
                ForEach(ReaderORPColor.allCases) {
                    Text($0.displayName).tag($0)
                }
            }

            LabeledContent("Background", value: "\(Int((preferences.clampedBackgroundBrightness * 100).rounded()))%")
            Slider(value: brightnessBinding, in: ReaderDisplayPreferences.backgroundBrightnessRange)

            Toggle("Hide controls by default", isOn: $preferences.hideControls)
            Toggle("Dyslexia-friendly rendering", isOn: $preferences.dyslexiaFriendly)
        }
    }
}
