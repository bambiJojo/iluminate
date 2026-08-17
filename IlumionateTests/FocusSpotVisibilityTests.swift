//
//  FocusSpotVisibilityTests.swift
//  IlumionateTests
//
//  Focus spots must never appear over an unlit backdrop — black circles on
//  flat bgPrimary read as a rendering bug, not a feature.
//

import Foundation
import Testing

@testable import Ilumionate

@Suite("Focus spot visibility")
@MainActor
struct FocusSpotVisibilityTests {

    private func makeSession() -> LightSession {
        LightSession(
            session_name: "Visibility Test",
            duration_sec: 300,
            light_score: [
                LightMoment(time: 0, frequency: 10, intensity: 0.5, waveform: .sine)
            ]
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

    private var flashMode: PlayerMode {
        .flashMode(
            frequency: 10,
            intensity: 0.75,
            colorTemperature: 3000,
            pattern: .sine,
            binauralEnabled: false,
            binauralCarrier: 200,
            binauralVolume: 0.5
        )
    }

    private var visualField: PlayerMode {
        .visualField(settings: .standard, audioFile: nil, binaural: nil)
    }

    private func isVisible(
        _ mode: PlayerMode,
        isEnabled: Bool = true,
        mindMachineEnabled: Bool = true,
        lightSyncEnabled: Bool = true
    ) -> Bool {
        FocusSpotVisibility.isVisible(
            mode: mode,
            isEnabled: isEnabled,
            mindMachineEnabled: mindMachineEnabled,
            lightSyncEnabled: lightSyncEnabled
        )
    }

    // MARK: - Capability flag

    @Test("Every mode but the visual field supports focus spots")
    func capabilityFlag() {
        #expect(flashMode.supportsFocusSpots)
        #expect(PlayerMode.colorPulse(frequency: 10, intensity: 0.5).supportsFocusSpots)
        #expect(PlayerMode.session(session: makeSession(), audioFile: nil).supportsFocusSpots)
        #expect(PlayerMode.audioLight(audioFile: makeAudioFile()).supportsFocusSpots)
        #expect(PlayerMode.playlist(playlist: Playlist(name: "Evening")).supportsFocusSpots)
        #expect(visualField.supportsFocusSpots == false)
    }

    // MARK: - The gate

    @Test("Disabled means never visible")
    func disabledIsNeverVisible() {
        #expect(isVisible(flashMode, isEnabled: false) == false)
        #expect(
            isVisible(
                PlayerMode.colorPulse(frequency: 10, intensity: 0.5),
                isEnabled: false
            ) == false
        )
    }

    @Test("The raw entrainment fields always show spots when enabled")
    func rawFieldsAlwaysShow() {
        // Neither mode is gated by the mind machine or light sync toggles.
        #expect(isVisible(flashMode, mindMachineEnabled: false, lightSyncEnabled: false))
        #expect(
            isVisible(
                PlayerMode.colorPulse(frequency: 10, intensity: 0.5),
                mindMachineEnabled: false,
                lightSyncEnabled: false
            )
        )
    }

    @Test("Session and playlist follow the mind machine toggle")
    func sessionFollowsMindMachine() {
        let session = PlayerMode.session(session: makeSession(), audioFile: makeAudioFile())
        let playlist = PlayerMode.playlist(playlist: Playlist(name: "Evening"))

        #expect(isVisible(session, mindMachineEnabled: true))
        #expect(isVisible(session, mindMachineEnabled: false) == false)
        #expect(isVisible(playlist, mindMachineEnabled: true))
        #expect(isVisible(playlist, mindMachineEnabled: false) == false)
    }

    @Test("Audio mode follows its own light sync toggle")
    func audioFollowsLightSync() {
        let audio = PlayerMode.audioLight(audioFile: makeAudioFile())

        #expect(isVisible(audio, mindMachineEnabled: false, lightSyncEnabled: true))
        #expect(isVisible(audio, mindMachineEnabled: true, lightSyncEnabled: false) == false)
    }

    @Test("The visual field never shows spots, even when everything is on")
    func visualFieldNeverShows() {
        #expect(isVisible(visualField) == false)
    }
}
