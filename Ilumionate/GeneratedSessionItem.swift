//
//  GeneratedSessionItem.swift
//  Ilumionate
//
//  Pairs a user-generated light score with the audio file it was built from,
//  so tapping a card can launch synchronized audio + light playback.
//

import Foundation

struct GeneratedSessionItem: Identifiable {
    let audioFile: AudioFile
    let session: LightSession

    var id: UUID { audioFile.id }
}
