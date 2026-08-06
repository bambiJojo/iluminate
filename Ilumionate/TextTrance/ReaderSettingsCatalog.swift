//  ReaderSettingsCatalog.swift
//  Ilumionate
//
//  Single source of truth for where every reader setting lives. Both the
//  pre-session setup view and the mid-session drawer read this instead of
//  hardcoding their own arrangement, so the two surfaces cannot drift apart.
//
//  A group is either main (always visible), advanced (behind a disclosure), or
//  absent — and which one it is depends on the ReaderMode. Most of the apparent
//  complexity in the old settings pile was trance controls being shown while
//  plain-reading an imported article, where they mean nothing.

import Foundation

enum ReaderSettingsTier: String, CaseIterable, Sendable {
    case main
    case advanced
}

enum ReaderSettingsGroup: String, CaseIterable, Identifiable, Sendable {
    // Shared
    case readingComfort     // reader mode, font, size
    case visual             // TranceVisual picker (never removed by mode)
    case attention          // attention gate
    case displayDetail      // line spacing, highlight, brightness, hide controls, dyslexia
    case speedDetail        // speed mode, warm-up/ramp WPM, chunk size, punctuation pauses

    // Reading only
    case speedTarget        // target WPM as a number

    // Trance only
    case arc
    case pacingPreset
    case binaural
    case subliminal
    case lightHandoff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readingComfort: "Reading comfort"
        case .visual:         "Visual"
        case .attention:      "Attention"
        case .displayDetail:  "Reader display"
        case .speedDetail:    "Speed training"
        case .speedTarget:    "Speed"
        case .arc:            "Arc"
        case .pacingPreset:   "Pacing"
        case .binaural:       "Binaural beats"
        case .subliminal:     "Subliminal suggestions"
        case .lightHandoff:   "After handoff"
        }
    }

    /// Where this group sits in the given mode, or `nil` when it does not apply.
    ///
    /// `speedTarget` and `pacingPreset` are two presentations of the same
    /// underlying `ReaderSpeedTrainingSettings.targetWPM`: reading exposes the
    /// raw number because words-per-minute *is* the feature, trance exposes
    /// named presets because the number is a tuning detail there.
    func tier(in mode: ReaderMode) -> ReaderSettingsTier? {
        switch self {
        case .readingComfort, .visual, .attention:
            return .main
        case .displayDetail, .speedDetail:
            return .advanced

        case .speedTarget:
            return mode == .reading ? .main : nil
        case .arc, .pacingPreset, .binaural:
            return mode == .trance ? .main : nil
        case .subliminal, .lightHandoff:
            return mode == .trance ? .advanced : nil
        }
    }

    /// Groups for a mode and tier, in declaration order.
    static func groups(in mode: ReaderMode, tier: ReaderSettingsTier) -> [ReaderSettingsGroup] {
        allCases.filter { $0.tier(in: mode) == tier }
    }

    /// Groups that do not apply in this mode at all.
    static func absentGroups(in mode: ReaderMode) -> [ReaderSettingsGroup] {
        allCases.filter { $0.tier(in: mode) == nil }
    }
}

extension TextTranceSessionSettings {
    /// Strip the layers a mode does not offer.
    ///
    /// The catalog decides which groups a mode shows; this makes the *session*
    /// obey the same decision. Without it, choosing Reading only hid the
    /// binaural, subliminal and light controls — whatever they were last set to
    /// kept running, and with the controls gone there was no way to reach them.
    ///
    /// The arc matters most. `.arc` is trance-only, so a bundled script left on
    /// `.handoff` would keep that arc in Reading mode, and TextPacingEngine
    /// stops scheduling at the handoff trigger — silently truncating the text.
    func normalized(for mode: ReaderMode, supportedArcs: [ScriptArc]) -> TextTranceSessionSettings {
        func offers(_ group: ReaderSettingsGroup) -> Bool { group.tier(in: mode) != nil }

        let resolvedArc: ScriptArc
        if offers(.arc) {
            resolvedArc = arc
        } else {
            // Read the whole text when the mode has no arc control. Falls back
            // to the current arc for a script that cannot do full text at all.
            resolvedArc = supportedArcs.contains(.fullText) ? .fullText : arc
        }

        return TextTranceSessionSettings(
            arc: resolvedArc,
            speedMultiplier: speedMultiplier,
            lightEnabled: offers(.lightHandoff) && lightEnabled,
            binauralEnabled: offers(.binaural) && binauralEnabled,
            beatFrequency: beatFrequency,
            postHandoffDuration: postHandoffDuration,
            subliminalEnabled: offers(.subliminal) && subliminalEnabled,
            subliminalSpeed: subliminalSpeed,
            attentionGateEnabled: attentionGateEnabled,
            speedTraining: speedTraining,
            displayPreferences: displayPreferences
        )
    }
}
