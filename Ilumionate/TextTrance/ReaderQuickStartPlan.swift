//
//  ReaderQuickStartPlan.swift
//  Ilumionate
//
//  Chooses and reconstructs the shortest safe path from the Reader library
//  into playback. Resume settings stay faithful; new sessions avoid optional
//  camera, light, and audio layers until the user chooses them in Setup.

import Foundation

@MainActor
struct ReaderQuickStartPlan: Identifiable {
    let script: TranceScript
    let startIndex: Int
    let startType: PlaybackStartType
    let settings: TextTranceSessionSettings

    var id: String { "\(script.id)-\(startType.rawValue)-\(startIndex)" }

    static func select(
        scripts: [TranceScript],
        historyItems: [ReaderHistoryItem],
        preset: (String) -> ReaderPreset
    ) -> ReaderQuickStartPlan? {
        for item in historyItems {
            if let plan = resumedPlan(for: item) {
                return plan
            }
        }

        guard let script = scripts.first,
              let arc = preferredArc(for: script) else { return nil }
        let savedPreset = preset(script.id)
        return ReaderQuickStartPlan(
            script: script,
            startIndex: 0,
            startType: .fresh,
            settings: TextTranceSessionSettings(
                arc: arc,
                speedMultiplier: savedPreset.speedTraining.targetSpeedMultiplier,
                lightEnabled: false,
                binauralEnabled: false,
                beatFrequency: 10,
                postHandoffDuration: 600,
                subliminalEnabled: false,   // see TextTranceSetupView for rationale
                subliminalSpeed: .medium,
                attentionGateEnabled: false,
                speedTraining: savedPreset.speedTraining,
                displayPreferences: savedPreset.displayPreferences
            )
        )
    }

    func makeSession(progressStore: ReaderProgressStore) -> TextTranceSession {
        // This path skips Setup entirely, so the mode has to be applied here too
        // or a one-tap start ignores it.
        let mode = ReaderPresetStore.shared
            .preset(forScriptId: script.id)
            .resolvedMode(for: script)
        let settings = self.settings.normalized(
            for: mode,
            supportedArcs: script.supportedArcs
        )
        let useLight = settings.arc == .handoff && settings.lightEnabled
        return TextTranceSession(
            script: script,
            settings: settings,
            light: useLight
                ? FlashController(frequency: 10, intensity: 0.7, pattern: .sine)
                : nil,
            audio: settings.binauralEnabled ? BinauralBeatsEngine() : nil,
            progressStore: progressStore,
            scriptContentHash: Self.contentHash(for: script)
        )
    }

    private static func resumedPlan(for item: ReaderHistoryItem) -> ReaderQuickStartPlan? {
        let state = item.state
        let script = item.script
        guard script.supportedArcs.contains(state.settings.arc) else { return nil }

        let scheduleCount = TextPacingEngine.schedule(
            for: script,
            settings: TextPacingSettings(
                arc: state.settings.arc,
                speedMultiplier: 1,
                subliminalEnabled: state.settings.subliminalEnabled,
                subliminalSpeed: state.settings.subliminalSpeed,
                speedTraining: state.settings.speedTraining
            )
        ).count
        guard state.isUsable(
            contentHash: contentHash(for: script),
            scheduleCount: scheduleCount
        ) else { return nil }

        var speedTraining = state.settings.speedTraining
        if speedTraining == .standard, state.settings.speedMultiplier != 1 {
            speedTraining.targetWPM = TextPacingEngine.nominalWPM(
                forMultiplier: state.settings.speedMultiplier
            )
        }

        return ReaderQuickStartPlan(
            script: script,
            startIndex: state.wordIndex,
            startType: .resumed,
            settings: TextTranceSessionSettings(
                arc: state.settings.arc,
                speedMultiplier: speedTraining.targetSpeedMultiplier,
                lightEnabled: state.settings.lightEnabled,
                binauralEnabled: state.settings.binauralEnabled,
                beatFrequency: state.settings.beatFrequency,
                postHandoffDuration: 600,
                subliminalEnabled: state.settings.subliminalEnabled,
                subliminalSpeed: state.settings.subliminalSpeed,
                attentionGateEnabled: state.settings.attentionGateEnabled,
                speedTraining: speedTraining,
                displayPreferences: state.settings.displayPreferences
            )
        )
    }

    private static func preferredArc(for script: TranceScript) -> ScriptArc? {
        script.supportedArcs.contains(.fullText) ? .fullText : script.supportedArcs.first
    }

    private static func contentHash(for script: TranceScript) -> String {
        ReaderResumeState.contentHash(
            for: script.segments.map(\.text).joined(separator: " ")
        )
    }
}
