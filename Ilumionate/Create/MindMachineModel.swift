//
//  MindMachineModel.swift
//  Ilumionate
//
//  The light-entrainment settings behind Create's Flash, Colour and Bilateral
//  kinds. The wordless Visual Field has its own model — VisualFieldSettings —
//  because it shares none of these parameters.
//
//  Named for the type PlayerMode.flashMode already refers to. What used to be
//  MindMachineView around it is now CreateView.
//

import SwiftUI

@MainActor
@Observable
final class MindMachineModel: Sendable {
    private var frequencyStorage: Double = LightSafety.maxFlashHz
    var frequency: Double {      // Hz
        get { frequencyStorage }
        set { frequencyStorage = LightSafety.clampFlashHz(newValue) }
    }
    var intensity: Double = 0.75        // 0.0 to 1.0
    var colorTemperature: Int = 3000     // Kelvin
    var selectedPattern: LightPattern = .sine
    var isSessionActive: Bool = false

    // Color temperature options
    let temperatureOptions = [2700, 3000, 4000, 5000, 6500]

    // MARK: - Binaural Beats Settings
    var binauralEnabled: Bool = false
    var binauralCarrierFrequency: Double = 200.0   // Hz — left ear carrier
    var binauralVolume: Double = 0.5

    enum LightPattern: String, CaseIterable {
        case sine = "Sine"
        case square = "Square"
        case triangle = "Triangle"
        case sawtooth = "Sawtooth"
        case pulse = "Pulse"

        var description: String {
            switch self {
            case .sine: return "Smooth waves"
            case .square: return "Sharp pulses"
            case .triangle: return "Rising waves"
            case .sawtooth: return "Ramped pulses"
            case .pulse: return "Brief flashes"
            }
        }

        var gradient: LinearGradient {
            switch self {
            case .sine:
                return LinearGradient(colors: [.bwAlpha, .roseGold], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .square:
                return LinearGradient(colors: [.bwBeta, .warmAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .triangle:
                return LinearGradient(colors: [.bwTheta, .lavender], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .sawtooth:
                return LinearGradient(colors: [.bwGamma, .blush], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .pulse:
                return LinearGradient(colors: [.roseDeep, .roseGold], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }

    // MARK: - Derived Presentation Helpers
    // Pure functions of model state, shared by the view's child components.

    var brainwaveZone: String {
        switch frequency {
        case 0.5..<1.0: return "Very Slow"
        case 1.0..<1.5: return "Slow"
        case 1.5..<2.0: return "Medium"
        case 2.0..<2.5: return "Fast"
        default: return "Very Fast"
        }
    }

    var brainwaveColor: Color {
        switch frequency {
        case 0.5..<1.0: return .bwDelta
        case 1.0..<1.5: return .bwTheta
        case 1.5..<2.0: return .bwAlpha
        case 2.0..<2.5: return .bwBeta
        default: return .bwGamma
        }
    }

    /// Maps the live frequency to a brainwave category for AuroraBackground mood.
    /// Bands match BrainwaveCategory's own frequencyRange/haloColor so the aurora
    /// tint agrees with the model's brainwaveColor.
    var moodCategory: BrainwaveCategory {
        switch frequency {
        case 0.5..<1.0: return .sleep
        case 1.0..<1.5: return .relax
        case 1.5..<2.0: return .focus
        case 2.0..<2.5: return .energy
        default:        return .trance
        }
    }

    func colorForTemperature(_ temp: Int) -> Color {
        switch temp {
        case 2700: return .warmAccent
        case 3000: return .roseGold
        case 4000: return .blush
        case 5000: return .lavender
        case 6500: return .bwBeta
        default: return .roseGold
        }
    }

    /// The binaural configuration in the form a Visual Field session takes it.
    ///
    /// The beat frequency follows the light frequency, matching what
    /// `setupFlashMode` does — so switching kinds does not silently change the
    /// beat out from under you.
    var binauralSettings: BinauralSettings {
        BinauralSettings(
            enabled: binauralEnabled,
            carrier: binauralCarrierFrequency,
            volume: binauralVolume,
            beatFrequency: frequency
        )
    }
}
