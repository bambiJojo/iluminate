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
            && wordIndex > 0
            && wordIndex < scheduleCount
    }
}
