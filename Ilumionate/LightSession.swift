//
//  LightSession.swift
//  Ilumionate
//
//  Created by Byron Quine on 2/9/26.
//

import Foundation
import CryptoKit

/// Represents a complete light entrainment session loaded from JSON.
/// This is the root structure that contains all session metadata and the
/// timeline of light control points.
nonisolated struct LightSession: Codable, Identifiable, Sendable {
    let id: UUID
    let session_name: String
    let duration_sec: Double
    let light_score: [LightMoment]

    /// Whether the session includes binaural beats (headphones required).
    let binaural_enabled: Bool

    /// Carrier tone frequency for the left ear (Hz). Right ear = carrier + beat frequency.
    let binaural_carrier: Double

    /// Default binaural volume (0.0–1.0).
    let binaural_volume: Double

    /// Quality report from the audio-to-light alignment pass, when generated
    /// from an analyzed audio file.
    let alignment_report: LightScoreAlignmentReport?

    /// Computed property for SwiftUI display
    var displayName: String { session_name }

    /// Computed property for duration formatting
    var durationFormatted: String {
        Duration.seconds(duration_sec).formatted(.time(pattern: .minuteSecond))
    }

    enum CodingKeys: String, CodingKey {
        case id
        case session_name
        case duration_sec
        case light_score
        case binaural_enabled
        case binaural_carrier
        case binaural_volume
        case alignment_report
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.session_name = try container.decode(String.self, forKey: .session_name)
        self.duration_sec = try container.decode(Double.self, forKey: .duration_sec)
        self.light_score = try container.decode([LightMoment].self, forKey: .light_score)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? Self.stableID(
            sessionName: session_name,
            duration: duration_sec,
            lightScore: light_score
        )
        self.binaural_enabled = (try? container.decode(Bool.self, forKey: .binaural_enabled)) ?? false
        self.binaural_carrier = (try? container.decode(Double.self, forKey: .binaural_carrier)) ?? 200.0
        self.binaural_volume = (try? container.decode(Double.self, forKey: .binaural_volume)) ?? 0.5
        self.alignment_report = try? container.decode(LightScoreAlignmentReport.self, forKey: .alignment_report)
    }

    init(id: UUID = UUID(), session_name: String, duration_sec: Double, light_score: [LightMoment],
         binaural_enabled: Bool = false, binaural_carrier: Double = 200.0, binaural_volume: Double = 0.5,
         alignment_report: LightScoreAlignmentReport? = nil) {
        self.id = id
        self.session_name = session_name
        self.duration_sec = duration_sec
        self.light_score = light_score
        self.binaural_enabled = binaural_enabled
        self.binaural_carrier = binaural_carrier
        self.binaural_volume = binaural_volume
        self.alignment_report = alignment_report
    }

    /// Bundled session files predate explicit IDs. Deriving one from immutable
    /// session content keeps resume keys stable across launches while preserving
    /// IDs already stored in generated-session JSON.
    private static func stableID(
        sessionName: String,
        duration: TimeInterval,
        lightScore: [LightMoment]
    ) -> UUID {
        var input = "\(sessionName)|\(duration)|\(lightScore.count)"
        for moment in lightScore {
            input += "|\(moment.time),\(moment.frequency),\(moment.intensity),\(moment.waveform.rawValue)"
        }

        let digest = SHA256.hash(data: Data(input.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// A single control point in the light score timeline.
/// Represents the target state of the light engine at a specific time.
/// The runtime player interpolates between consecutive moments.
nonisolated struct LightMoment: Codable, Sendable {
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
nonisolated enum WaveformType: String, Codable, CaseIterable, Sendable {
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
