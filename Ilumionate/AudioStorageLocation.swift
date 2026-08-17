//
//  AudioStorageLocation.swift
//  Ilumionate
//

import Foundation

/// Where an audio file's bytes live. Missing values in older library JSON mean
/// Documents, preserving every file imported before managed storage existed.
nonisolated enum AudioStorageLocation: String, Codable, Sendable, Equatable {
    case documents
    case managed
}
