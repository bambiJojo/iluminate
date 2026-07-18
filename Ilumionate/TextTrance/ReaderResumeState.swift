//  ReaderResumeState.swift
//  Ilumionate
//
//  Codable snapshot of an in-progress reading session, used to resume after
//  the player is closed. Persisted per script by ReaderProgressStore.

import Foundation
import CryptoKit

/// Settings needed to faithfully reconstruct a session on resume.
struct PersistedReaderSettings: Codable, Sendable, Equatable {
    let arc: ScriptArc
    let speedMultiplier: Double
    let subliminalEnabled: Bool
    let subliminalSpeed: TextPacingSettings.SubliminalSpeed
    let binauralEnabled: Bool
    let lightEnabled: Bool
    let beatFrequency: Double
    let attentionGateEnabled: Bool
    let speedTraining: ReaderSpeedTrainingSettings
    let displayPreferences: ReaderDisplayPreferences

    init(arc: ScriptArc,
         speedMultiplier: Double,
         subliminalEnabled: Bool,
         subliminalSpeed: TextPacingSettings.SubliminalSpeed,
         binauralEnabled: Bool,
         lightEnabled: Bool,
         beatFrequency: Double,
         attentionGateEnabled: Bool = false,
         speedTraining: ReaderSpeedTrainingSettings = .standard,
         displayPreferences: ReaderDisplayPreferences = .standard) {
        self.arc = arc
        self.speedMultiplier = speedMultiplier
        self.subliminalEnabled = subliminalEnabled
        self.subliminalSpeed = subliminalSpeed
        self.binauralEnabled = binauralEnabled
        self.lightEnabled = lightEnabled
        self.beatFrequency = beatFrequency
        self.attentionGateEnabled = attentionGateEnabled
        self.speedTraining = speedTraining
        self.displayPreferences = displayPreferences
    }

    private enum CodingKeys: String, CodingKey {
        case arc
        case speedMultiplier
        case subliminalEnabled
        case subliminalSpeed
        case binauralEnabled
        case lightEnabled
        case beatFrequency
        case attentionGateEnabled
        case speedTraining
        case displayPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arc = try container.decode(ScriptArc.self, forKey: .arc)
        speedMultiplier = try container.decode(Double.self, forKey: .speedMultiplier)
        subliminalEnabled = try container.decode(Bool.self, forKey: .subliminalEnabled)
        subliminalSpeed = try container.decode(TextPacingSettings.SubliminalSpeed.self, forKey: .subliminalSpeed)
        binauralEnabled = try container.decode(Bool.self, forKey: .binauralEnabled)
        lightEnabled = try container.decode(Bool.self, forKey: .lightEnabled)
        beatFrequency = try container.decode(Double.self, forKey: .beatFrequency)
        attentionGateEnabled = try container.decodeIfPresent(Bool.self, forKey: .attentionGateEnabled) ?? false
        speedTraining = try container.decodeIfPresent(
            ReaderSpeedTrainingSettings.self,
            forKey: .speedTraining
        ) ?? .standard
        displayPreferences = try container.decodeIfPresent(
            ReaderDisplayPreferences.self,
            forKey: .displayPreferences
        ) ?? .standard
    }
}

/// Where in the arc the user left off.
enum ResumePhase: Codable, Sendable, Equatable {
    case reading
    case handoffTail(elapsed: TimeInterval)
}

struct ReaderResumeState: Codable, Sendable, Equatable {
    let scriptId: String
    let wordIndex: Int
    let settings: PersistedReaderSettings
    let phase: ResumePhase
    let scriptContentHash: String
    let savedAt: Date

    /// Stable hash of the script's rendered text, used to detect that the
    /// source changed (e.g. an imported web reading source) since saving.
    static func contentHash(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func isUsable(contentHash: String, scheduleCount: Int) -> Bool {
        scriptContentHash == contentHash
            && wordIndex >= 0
            && wordIndex < scheduleCount
    }
}
