import Testing
@testable import Ilumionate

struct ReaderPacingPresetTests {
    @Test
    func presetsIncreaseInTargetSpeed() {
        #expect(ReaderPacingPreset.gentle.settings.targetWPM < ReaderPacingPreset.balanced.settings.targetWPM)
        #expect(ReaderPacingPreset.balanced.settings.targetWPM < ReaderPacingPreset.focused.settings.targetWPM)
    }

    @Test
    func closestPresetPreservesAUsefulDefault() {
        let custom = ReaderSpeedTrainingSettings(targetWPM: 250)
        #expect(ReaderPacingPreset.closest(to: custom) == .focused)
    }
}
