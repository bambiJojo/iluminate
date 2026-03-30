//
//  MockAudioTranscriber.swift
//  IlumionateTests
//
//  Deterministic AudioTranscribingService for unit tests.
//  Configure `resultToReturn` before calling transcribe().
//

import Foundation
@testable import Ilumionate

@MainActor
final class MockAudioTranscriber: AudioTranscribingService {
    var progress: Double = 0.0
    var statusMessage: String = ""

    var resultToReturn: Result<AudioTranscriptionResult, Error> =
        .success(AnalysisFixtures.basicTranscription)
    private(set) var callCount = 0

    func transcribe(audioFile: AudioFile) async throws -> AudioTranscriptionResult {
        callCount += 1
        progress = 1.0
        return try resultToReturn.get()
    }

    func cancelTranscription() async {
        // no-op in tests
    }
}
