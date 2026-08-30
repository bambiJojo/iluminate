//
//  TranscriptionTypes.swift
//  AnalyzerImprover
//
//  AnalyzerImprover-specific errors. The transcript value types themselves live
//  in Ilumionate/AudioTranscriptionResult.swift, which was extracted from
//  AudioAnalyzer precisely so tools that only read cached transcripts could
//  share them without linking a speech recogniser. This file used to carry its
//  own copies; they drifted (the shared type sanitizes text and drops empty
//  segments, these did not) and collided once the shared file was added to this
//  target's membership list. See ERRORS.md ERR-018.
//

import Foundation

enum AnalyzerError: LocalizedError {
    case whisperKitNotInitialized
    case transcriptionFailed(Error)
    case audioFileInvalid
    case noAudioData

    var errorDescription: String? {
        switch self {
        case .whisperKitNotInitialized:
            return "WhisperKit is not initialized. Please wait for the model to load."
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .audioFileInvalid:
            return "The audio file is invalid or corrupted"
        case .noAudioData:
            return "No audio data found"
        }
    }
}
