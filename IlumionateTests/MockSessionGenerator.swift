//
//  MockSessionGenerator.swift
//  IlumionateTests
//
//  Deterministic SessionGeneratingService for unit tests.
//

import Foundation
@testable import Ilumionate

@MainActor
final class MockSessionGenerator: SessionGeneratingService {
    var sessionToReturn: LightSession = AnalysisFixtures.hypnosisSession
    private(set) var callCount = 0

    func generateSession(
        from audioFile: AudioFile,
        analysis: AnalysisResult,
        config: SessionGenerator.GenerationConfig
    ) -> LightSession {
        callCount += 1
        return sessionToReturn
    }
}
