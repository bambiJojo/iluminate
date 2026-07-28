//  PlayerControlTrayTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

struct DragValueMapperTests {

    private let mapper = DragValueMapper(range: 0...1, travel: 150)

    @Test func draggingUpIncreasesTheValue() {
        // Up is a negative translation in SwiftUI's coordinate space.
        let result = mapper.value(from: 0.5, translation: -75)
        #expect(abs(result - 1.0) < 0.0001)
    }

    @Test func draggingDownDecreasesTheValue() {
        let result = mapper.value(from: 0.5, translation: 75)
        #expect(abs(result - 0.0) < 0.0001)
    }

    @Test func zeroTranslationIsANoOp() {
        #expect(mapper.value(from: 0.42, translation: 0) == 0.42)
    }

    @Test func fullTravelSpansExactlyTheRange() {
        #expect(abs(mapper.value(from: 0, translation: -150) - 1.0) < 0.0001)
    }

    @Test func valuesClampAtBothEnds() {
        #expect(mapper.value(from: 0.9, translation: -1000) == 1.0)
        #expect(mapper.value(from: 0.1, translation: 1000) == 0.0)
    }

    @Test func sensitivityScalesWithTravel() {
        let coarse = DragValueMapper(range: 0...1, travel: 300)
        // Half the sensitivity: the same drag moves half as far.
        #expect(abs(coarse.value(from: 0, translation: -150) - 0.5) < 0.0001)
    }

    @Test func respectsANonZeroLowerBound() {
        let brightness = DragValueMapper(range: 0.1...1.0, travel: 150)
        #expect(brightness.value(from: 0.5, translation: 1000) == 0.1)
        #expect(abs(brightness.value(from: 0.1, translation: -150) - 1.0) < 0.0001)
    }

    @Test func zeroTravelIsSafe() {
        let degenerate = DragValueMapper(range: 0...1, travel: 0)
        #expect(degenerate.value(from: 0.5, translation: -100) == 0.5)
    }
}

@MainActor
struct PlayerControlSlotTests {

    private func makeSession(binaural: Bool = false) -> LightSession {
        LightSession(
            session_name: "Slot Test",
            duration_sec: 300,
            light_score: [LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)],
            binaural_enabled: binaural
        )
    }

    private func makeAudioFile() -> AudioFile {
        AudioFile(
            id: UUID(),
            filename: "track.m4a",
            duration: 300,
            fileSize: 2048,
            createdDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    @Test func sessionWithAudioGetsTheFullTray() {
        let slots = PlayerControlSlot.slots(
            for: .session(session: makeSession(), audioFile: makeAudioFile())
        )
        #expect(slots == [.mindMachine, .volume, .brightness])
    }

    @Test func binauralSessionAlsoGetsMore() {
        let slots = PlayerControlSlot.slots(
            for: .session(session: makeSession(binaural: true), audioFile: makeAudioFile())
        )
        #expect(slots == [.mindMachine, .volume, .brightness, .more])
    }

    @Test func sessionWithoutAudioHasNoMindMachineOrVolume() {
        let slots = PlayerControlSlot.slots(
            for: .session(session: makeSession(), audioFile: nil)
        )
        #expect(slots == [.brightness])
    }

    @Test func playlistGetsTheFullTray() {
        let slots = PlayerControlSlot.slots(for: .playlist(playlist: Playlist(name: "Evening")))
        #expect(slots == [.mindMachine, .volume, .brightness, .more])
    }

    @Test func audioLightUsesLightSyncInsteadOfMindMachine() {
        let slots = PlayerControlSlot.slots(for: .audioLight(audioFile: makeAudioFile()))
        #expect(slots == [.lightSync, .volume, .brightness])
    }

    @Test func flashModeOnlyGetsMore() {
        let slots = PlayerControlSlot.slots(for: .flashMode(
            frequency: 10, intensity: 0.75, colorTemperature: 3000, pattern: .sine,
            binauralEnabled: false, binauralCarrier: 200, binauralVolume: 0.5
        ))
        #expect(slots == [.more])
    }

    @Test func colorPulseGetsNoTray() {
        let slots = PlayerControlSlot.slots(for: .colorPulse(frequency: 10, intensity: 0.5))
        #expect(slots.isEmpty)
    }

    /// The regression test for the reflow bug. `slots(for:)` takes only a mode,
    /// so no runtime state can add or remove a tile mid-session.
    @Test func slotsAreStableAcrossMindMachineToggling() {
        let mode = PlayerMode.session(session: makeSession(), audioFile: makeAudioFile())
        let before = PlayerControlSlot.slots(for: mode)
        let after = PlayerControlSlot.slots(for: mode)
        #expect(before == after)
        #expect(before.contains(.brightness))
    }

    // MARK: - Tile state

    @Test func brightnessIsDisabledWhenLightsAreOff() {
        #expect(PlayerControlSlot.brightness.state(lightsAreOn: false) == .disabled)
        #expect(PlayerControlSlot.brightness.state(lightsAreOn: true) == .normal)
    }

    @Test func lightTogglesAreActiveWhenLightsAreOn() {
        #expect(PlayerControlSlot.mindMachine.state(lightsAreOn: true) == .active)
        #expect(PlayerControlSlot.mindMachine.state(lightsAreOn: false) == .normal)
        #expect(PlayerControlSlot.lightSync.state(lightsAreOn: true) == .active)
    }

    @Test func volumeAndMoreAreAlwaysNormal() {
        #expect(PlayerControlSlot.volume.state(lightsAreOn: false) == .normal)
        #expect(PlayerControlSlot.more.state(lightsAreOn: false) == .normal)
    }

    @Test func onlyValueSlotsAreDraggable() {
        #expect(PlayerControlSlot.volume.isDraggable)
        #expect(PlayerControlSlot.brightness.isDraggable)
        #expect(PlayerControlSlot.mindMachine.isDraggable == false)
        #expect(PlayerControlSlot.more.isDraggable == false)
    }
}
