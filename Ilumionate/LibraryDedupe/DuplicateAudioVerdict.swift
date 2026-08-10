//
//  DuplicateAudioVerdict.swift
//  Ilumionate
//

import Foundation

nonisolated enum DuplicateAudioVerdict: Equatable, Sendable {
    /// The library holds this exact audio. Safe to reuse without asking.
    case identical(existing: AudioFile.ID)
    /// Strong but circumstantial. Always shown to the user before acting.
    case likely(existing: AudioFile.ID, reason: Reason)
    case distinct

    nonisolated enum Reason: Equatable, Sendable {
        case sizeAndDuration
        case titleAndDuration
    }

    var existingID: AudioFile.ID? {
        switch self {
        case .identical(let id): id
        case .likely(let id, _): id
        case .distinct: nil
        }
    }
}
