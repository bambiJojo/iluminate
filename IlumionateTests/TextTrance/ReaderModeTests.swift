//  ReaderModeTests.swift
//  IlumionateTests
//
//  Mode derivation, the settings catalog, and the preset override.

import Foundation
import Testing
@testable import Ilumionate

@Suite("Reader mode")
struct ReaderModeTests {

    private func script(kind: ScriptSource.Kind) -> TranceScript {
        TranceScript(
            schemaVersion: 1,
            id: "s",
            title: "T",
            theme: .relaxation,
            supportedArcs: [.fullText],
            language: "en",
            source: ScriptSource(kind: kind, generator: nil, reviewed: true),
            segments: [
                TranceScriptSegment(
                    phase: .induction,
                    text: "drifting down",
                    pacing: nil,
                    arcs: nil,
                    triggersHandoff: nil
                )
            ]
        )
    }

    @Test("Imported content defaults to plain reading")
    func importedContentIsReading() {
        #expect(ReaderMode.derived(from: ScriptSource(kind: .importedWeb, generator: nil, reviewed: false)) == .reading)
        #expect(ReaderMode.derived(from: ScriptSource(kind: .importedDocument, generator: nil, reviewed: false)) == .reading)
    }

    @Test("Authored content defaults to trance")
    func authoredContentIsTrance() {
        #expect(ReaderMode.derived(from: ScriptSource(kind: .bundled, generator: nil, reviewed: true)) == .trance)
        #expect(ReaderMode.derived(from: ScriptSource(kind: .generated, generator: "ai", reviewed: false)) == .trance)
    }

    @Test("Every source kind derives a mode", arguments: [
        ScriptSource.Kind.bundled, .generated, .importedWeb, .importedDocument
    ])
    func everyKindDerives(kind: ScriptSource.Kind) {
        let mode = ReaderMode.derived(from: ScriptSource(kind: kind, generator: nil, reviewed: false))
        #expect(ReaderMode.allCases.contains(mode))
    }

    // MARK: - Catalog

    @Test("Trance-only groups are absent when plain reading")
    func tranceGroupsAbsentInReading() {
        let absent = ReaderSettingsGroup.absentGroups(in: .reading)
        #expect(absent.contains(.arc))
        #expect(absent.contains(.binaural))
        #expect(absent.contains(.subliminal))
        #expect(absent.contains(.lightHandoff))
        #expect(absent.contains(.pacingPreset))
    }

    @Test("Raw words-per-minute is absent in trance")
    func speedTargetAbsentInTrance() {
        #expect(ReaderSettingsGroup.speedTarget.tier(in: .trance) == nil)
        #expect(ReaderSettingsGroup.speedTarget.tier(in: .reading) == .main)
    }

    @Test("Shared groups keep the same tier in both modes")
    func sharedGroupsAreStable() {
        for group in [ReaderSettingsGroup.readingComfort, .visual, .attention] {
            #expect(group.tier(in: .reading) == .main)
            #expect(group.tier(in: .trance) == .main)
        }
        for group in [ReaderSettingsGroup.displayDetail, .speedDetail] {
            #expect(group.tier(in: .reading) == .advanced)
            #expect(group.tier(in: .trance) == .advanced)
        }
    }

    @Test("Visual is never removed by mode")
    func visualAlwaysPresent() {
        for mode in ReaderMode.allCases {
            #expect(ReaderSettingsGroup.visual.tier(in: mode) != nil)
        }
    }

    @Test("Every group is main, advanced, or absent in every mode")
    func everyGroupIsClassified() {
        for mode in ReaderMode.allCases {
            let main = ReaderSettingsGroup.groups(in: mode, tier: .main)
            let advanced = ReaderSettingsGroup.groups(in: mode, tier: .advanced)
            let absent = ReaderSettingsGroup.absentGroups(in: mode)
            #expect(main.count + advanced.count + absent.count == ReaderSettingsGroup.allCases.count)
            #expect(Set(main).isDisjoint(with: Set(advanced)))
        }
    }

    @Test("Plain reading shows fewer groups than trance")
    func readingIsSimpler() {
        let reading = ReaderSettingsGroup.absentGroups(in: .reading).count
        let trance = ReaderSettingsGroup.absentGroups(in: .trance).count
        #expect(reading > trance)
    }

    // MARK: - Preset override

    @Test("Preset with no override uses the derived mode")
    func presetFallsBackToDerived() {
        let preset = ReaderPreset()
        #expect(preset.resolvedMode(for: script(kind: .importedWeb)) == .reading)
        #expect(preset.resolvedMode(for: script(kind: .bundled)) == .trance)
    }

    @Test("Preset override wins over the derived mode")
    func presetOverrideWins() {
        let preset = ReaderPreset(mode: .trance)
        #expect(preset.resolvedMode(for: script(kind: .importedWeb)) == .trance)

        let reversed = ReaderPreset(mode: .reading)
        #expect(reversed.resolvedMode(for: script(kind: .bundled)) == .reading)
    }

    @Test("Preset round-trips with and without an override")
    func presetRoundTrips() throws {
        for mode in [ReaderMode?.none, .reading, .trance] {
            let original = ReaderPreset(mode: mode)
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ReaderPreset.self, from: data)
            #expect(decoded == original)
            #expect(decoded.mode == mode)
        }
    }

    @Test("Presets saved before mode existed still decode")
    func legacyPresetDecodes() throws {
        // Shape written by the pre-ReaderMode build: no `mode` key at all.
        let legacy = ReaderPreset(
            speedTraining: .standard,
            displayPreferences: .standard
        )
        let encoded = try JSONEncoder().encode(legacy)
        var json = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json.removeValue(forKey: "mode")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(ReaderPreset.self, from: data)
        #expect(decoded.mode == nil)
        #expect(decoded.resolvedMode(for: script(kind: .importedDocument)) == .reading)
    }
}
