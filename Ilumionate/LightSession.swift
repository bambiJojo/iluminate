//
//  LightSession.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/9/26.
//

import Foundation

/// Represents a complete light entrainment session loaded from JSON.
/// This is the root structure that contains all session metadata and the
/// timeline of light control points.
struct LightSession: Codable, Identifiable {
    let id: UUID
    let session_name: String
    let duration_sec: Double
    let light_score: [LightMoment]

    /// Computed property for SwiftUI display
    var displayName: String { session_name }

    /// Computed property for duration formatting
    var durationFormatted: String {
        let minutes = Int(duration_sec) / 60
        let seconds = Int(duration_sec) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case session_name
        case duration_sec
        case light_score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate a UUID if not present in JSON
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.session_name = try container.decode(String.self, forKey: .session_name)
        self.duration_sec = try container.decode(Double.self, forKey: .duration_sec)
        self.light_score = try container.decode([LightMoment].self, forKey: .light_score)
    }

    init(id: UUID = UUID(), session_name: String, duration_sec: Double, light_score: [LightMoment]) {
        self.id = id
        self.session_name = session_name
        self.duration_sec = duration_sec
        self.light_score = light_score
    }
}

/// A single control point in the light score timeline.
/// Represents the target state of the light engine at a specific time.
/// The runtime player interpolates between consecutive moments.
struct LightMoment: Codable {
    let time: Double          // seconds from session start
    let frequency: Double     // target frequency in Hz
    let intensity: Double     // brightness intensity 0.0–1.0
    let waveform: WaveformType

    /// Optional ramp duration override for this transition
    let ramp_duration: Double?

    /// Optional bilateral mode setting
    let bilateral: Bool?

    /// Optional bilateral transition duration (how long to slip apart/together)
    let bilateral_transition_duration: Double?

    /// Optional color temperature in Kelvin (2000 = warm amber, 6500 = cool blue-white)
    let color_temperature: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case frequency
        case intensity
        case waveform
        case ramp_duration
        case bilateral
        case bilateral_transition_duration
        case color_temperature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.time = try container.decode(Double.self, forKey: .time)
        self.frequency = try container.decode(Double.self, forKey: .frequency)
        self.intensity = try container.decode(Double.self, forKey: .intensity)
        self.waveform = try container.decode(WaveformType.self, forKey: .waveform)
        self.ramp_duration = try? container.decode(Double.self, forKey: .ramp_duration)
        self.bilateral = try? container.decode(Bool.self, forKey: .bilateral)
        self.bilateral_transition_duration = try? container.decode(Double.self, forKey: .bilateral_transition_duration)
        self.color_temperature = try? container.decode(Double.self, forKey: .color_temperature)
    }

    init(time: Double, frequency: Double, intensity: Double, waveform: WaveformType, ramp_duration: Double? = nil, bilateral: Bool? = nil, bilateral_transition_duration: Double? = nil, color_temperature: Double? = nil) {
        self.time = time
        self.frequency = frequency
        self.intensity = intensity
        self.waveform = waveform
        self.ramp_duration = ramp_duration
        self.bilateral = bilateral
        self.bilateral_transition_duration = bilateral_transition_duration
        self.color_temperature = color_temperature
    }
}

/// Waveform types that can be specified in session JSON.
/// Must match the Waveform enum in EngineWaveforms.swift
enum WaveformType: String, Codable, CaseIterable {
    case sine
    case triangle
    case softPulse = "soft_pulse"
    case rampHold = "ramp_hold"
    case noiseModulatedSine = "noise_sine"

    /// Convert to the runtime Waveform enum
    var toWaveform: Waveform {
        switch self {
        case .sine: return .sine
        case .triangle: return .triangle
        case .softPulse: return .softPulse
        case .rampHold: return .rampHold
        case .noiseModulatedSine: return .noiseModulatedSine
        }
    }

    var displayName: String {
        switch self {
        case .sine: return "Sine"
        case .triangle: return "Triangle"
        case .softPulse: return "Soft Pulse"
        case .rampHold: return "Ramp & Hold"
        case .noiseModulatedSine: return "Noise Sine"
        }
    }
}
