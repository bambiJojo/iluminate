//
//  SyncPlayerItem.swift
//  Ilumionate
//

import Foundation

/// Bundles an audio file with its optional generated session for presentation.
struct SyncPlayerItem: Identifiable {
    let id = UUID()
    let audioFile: AudioFile
    let lightSession: LightSession?
}
