//
//  VisualFieldPlayerModeTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct VisualFieldPlayerModeTests {

    private func mode(
        binaural: BinauralSettings? = nil,
        duration: TimeInterval? = nil
    ) -> PlayerMode {
        var settings = VisualFieldSettings.standard
        settings.duration = duration
        return .visualField(settings: settings, audioFile: nil, binaural: binaural)
    }

    // MARK: - Capabilities

    @Test("A silent visual field offers no audio controls")
    func silentFieldHasNoAudioControls() {
        #expect(mode().hasAudioScrubber == false)
        #expect(mode().hasVolumeControl == false)
    }

    @Test("Strength is the visual's own knob, so screen brightness is not offered")
    func noBrightnessControl() {
        #expect(mode().hasBrightnessControl == false)
    }

    @Test("The visual field never warns about flashing, because it never flashes")
    func noSafetyWarning() {
        // PlayerSafetyWarningView belongs to the entrainment path. The field
        // never drives FlashController or LightEngine.
        #expect(mode().requiresSafetyWarning == false)
    }

    @Test("The field is dark chrome and offers no skip controls")
    func chromeAndTransport() {
        #expect(mode().usesDarkChrome)
        #expect(mode().hasSkipControls == false)
    }

    @Test("Duration decides whether the session is finite")
    func finiteOnlyWhenTimed() {
        #expect(mode(duration: nil).hasFiniteDuration == false)
        #expect(mode(duration: 600).hasFiniteDuration)
        #expect(mode(duration: 600).goalDuration == 600)
        #expect(mode(duration: nil).goalDuration == nil)
    }

    @Test("The title names the session")
    func title() {
        #expect(mode().title == "Visual Field")
    }

    @Test("Each visual field session gets its own id")
    func idsAreUnique() {
        #expect(mode().id != mode().id)
        #expect(mode().id.hasPrefix("visualField-"))
    }

    // MARK: - Tray

    @Test("A silent field shows only its two visual tiles")
    func silentTray() {
        #expect(PlayerControlSlot.slots(for: mode()) == [.visualStrength, .visualSpeed])
    }

    @Test("Enabled binaural adds the overflow tile")
    func binauralAddsMore() {
        let binaural = BinauralSettings(enabled: true, carrier: 200, volume: 0.5, beatFrequency: 10)
        #expect(PlayerControlSlot.slots(for: mode(binaural: binaural))
                == [.visualStrength, .visualSpeed, .more])
    }

    @Test("Disabled binaural settings add nothing")
    func disabledBinauralAddsNothing() {
        let off = BinauralSettings(enabled: false, carrier: 200, volume: 0.5, beatFrequency: 10)
        #expect(PlayerControlSlot.slots(for: mode(binaural: off))
                == [.visualStrength, .visualSpeed])
    }

    @Test("The visual tiles are dragged, not tapped")
    func visualTilesAreDraggable() {
        #expect(PlayerControlSlot.visualStrength.isDraggable)
        #expect(PlayerControlSlot.visualSpeed.isDraggable)
    }

    @Test("Every new slot has a label and an icon")
    func newSlotsArePresentable() {
        for slot in [PlayerControlSlot.visualStrength, .visualSpeed] {
            #expect(slot.label.isEmpty == false)
            #expect(slot.systemImage(lightsAreOn: true).isEmpty == false)
            #expect(slot.state(lightsAreOn: false) != .disabled)
        }
    }

    @Test("The tray for a given mode is the same list every time")
    func trayIsStable() {
        let mode = mode()
        #expect(PlayerControlSlot.slots(for: mode) == PlayerControlSlot.slots(for: mode))
    }

    // MARK: - Countdown and auto-start

    @Test("Only the visual field starts itself — its background renders whenever it is on screen")
    func onlyTheFieldBeginsAutomatically() {
        #expect(mode().beginsAutomatically)
        #expect(PlayerMode.colorPulse(frequency: 10, intensity: 0.5).beginsAutomatically == false)
        #expect(PlayerMode.flashMode(
            frequency: 10, intensity: 0.5, colorTemperature: 3000, pattern: .sine,
            binauralEnabled: false, binauralCarrier: 200, binauralVolume: 0.5
        ).beginsAutomatically == false)
    }

    @Test("The field's countdown never tells a watcher to close their eyes")
    func countdownCopyFitsAWatchedSession() {
        #expect(mode().countdownHoldMessage == nil)
        #expect(mode().countdownIntroMessage.localizedStandardContains("close your eyes") == false)
        // Flashing modes use a neutral hold rather than implying that closing
        // the eyes prevents exposure.
        #expect(PlayerMode.colorPulse(frequency: 10, intensity: 0.5)
            .countdownHoldMessage == "Ready")
    }

    // MARK: - BinauralSettings

    @Test("Binaural settings round-trip through Codable")
    func binauralCodable() throws {
        let original = BinauralSettings(enabled: true, carrier: 180, volume: 0.3, beatFrequency: 6)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(BinauralSettings.self, from: data) == original)
    }

    @Test("The standard binaural settings are off")
    func binauralDefaultsOff() {
        #expect(BinauralSettings.standard.enabled == false)
    }
}
