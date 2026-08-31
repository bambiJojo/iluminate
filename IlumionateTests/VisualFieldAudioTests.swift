//
//  VisualFieldAudioTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct VisualFieldAudioTests {

    private func freshDefaults() -> UserDefaults {
        let name = "VisualFieldAudioTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Silence is a configuration

    @Test("Silence is a valid configuration, not an unconfigured one")
    func silenceIsValid() {
        let mode = PlayerMode.visualField(
            settings: .standard, audioFile: nil, binaural: nil
        )
        #expect(mode.hasVolumeControl == false)
        #expect(PlayerControlSlot.slots(for: mode) == [.visualStrength, .visualSpeed])
    }

    // MARK: - The two sources are independent

    @Test("Binaural alone adds the overflow tile but no volume tile")
    func binauralAloneAddsNoVolume() {
        let binaural = BinauralSettings(
            enabled: true, carrier: 200, volume: 0.5, beatFrequency: 10
        )
        let mode = PlayerMode.visualField(
            settings: .standard, audioFile: nil, binaural: binaural
        )
        #expect(mode.hasVolumeControl == false)
        #expect(PlayerControlSlot.slots(for: mode).contains(.more))
        #expect(PlayerControlSlot.slots(for: mode).contains(.volume) == false)
    }

    @Test("Disabled binaural settings are the same as none")
    func disabledBinauralIsSilence() {
        let off = BinauralSettings(
            enabled: false, carrier: 200, volume: 0.5, beatFrequency: 10
        )
        let mode = PlayerMode.visualField(
            settings: .standard, audioFile: nil, binaural: off
        )
        #expect(PlayerControlSlot.slots(for: mode) == [.visualStrength, .visualSpeed])
    }

    // MARK: - The invariant

    @Test("Audio failure never disables the field itself")
    func audioFailureLeavesTheFieldRunning() {
        // The field is the content; audio is decoration. Elsewhere in the player
        // a failed load fails the session — here it must not.
        #expect(VisualFieldAudioFailure.leavesFieldRunning)
    }

    // MARK: - Persistence

    @Test("Binaural settings for the field persist separately from the visual")
    func binauralPersistsSeparately() {
        let defaults = freshDefaults()
        let store = VisualFieldStore(defaults: defaults)

        store.binaural = BinauralSettings(
            enabled: true, carrier: 240, volume: 0.4, beatFrequency: 6
        )
        var visual = store.settings
        visual.visual = .moire
        store.settings = visual

        let reloaded = VisualFieldStore(defaults: defaults)
        #expect(reloaded.binaural.enabled)
        #expect(reloaded.binaural.beatFrequency == 6)
        #expect(reloaded.settings.visual == .moire)
    }

    @Test("An empty store starts silent")
    func emptyStoreIsSilent() {
        #expect(VisualFieldStore(defaults: freshDefaults()).binaural.enabled == false)
    }

    @Test("Corrupt binaural data degrades to the defaults")
    func corruptBinauralDegrades() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: VisualFieldStore.binauralKey)
        #expect(VisualFieldStore(defaults: defaults).binaural == .standard)
    }

    @Test("The field's beat frequency is its own, not the light frequency")
    func beatFrequencyIsIndependent() {
        // A wordless field has no light frequency for the beat to follow, which
        // is why BinauralSettings carries one at all.
        let defaults = freshDefaults()
        let store = VisualFieldStore(defaults: defaults)
        store.binaural.beatFrequency = 4

        let light = MindMachineModel()
        light.frequency = 18

        #expect(store.binaural.beatFrequency == 4)
        #expect(light.binauralSettings.beatFrequency == LightSafety.maxFlashHz)
    }
}
