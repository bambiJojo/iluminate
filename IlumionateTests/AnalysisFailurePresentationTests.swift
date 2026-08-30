//
//  AnalysisFailurePresentationTests.swift
//  IlumionateTests
//

import Testing
@testable import Ilumionate

struct AnalysisFailurePresentationTests {

    @Test func invalidAudioExplainsReplacementInsteadOfOfferingRetry() {
        let presentation = AnalysisFailurePresentation(
            reason: .invalidAudio,
            failedStage: .transcription,
            recoveryStage: .none,
            retryState: .unavailable
        )

        #expect(presentation.title == "Audio file can’t be read")
        #expect(presentation.canRetry == false)
        #expect(presentation.recoveryMessage.contains("re-import"))
    }

    @Test func savedTranscriptIsCalledOutForManualRecovery() {
        let presentation = AnalysisFailurePresentation(
            reason: .contentAnalysis,
            failedStage: .contentAnalysis,
            recoveryStage: .transcription,
            retryState: .manual
        )

        #expect(presentation.canRetry)
        #expect(presentation.statusMessage == "Transcript saved")
        #expect(presentation.recoveryMessage.contains("continue"))
    }

    @Test func automaticRetryIsVisibleToTheUser() {
        let presentation = AnalysisFailurePresentation(
            reason: .transcription,
            failedStage: .transcription,
            recoveryStage: .none,
            retryState: .automatic
        )

        #expect(presentation.canRetry)
        #expect(presentation.statusMessage == "Retry scheduled")
    }

    @Test func stalledAnalysisExplainsTheWatchdogRecovery() {
        let presentation = AnalysisFailurePresentation(
            reason: .stalled,
            failedStage: .transcription,
            recoveryStage: .none,
            retryState: .manual
        )

        #expect(presentation.title == "Analysis stopped responding")
        #expect(presentation.message.contains("made no progress"))
        #expect(presentation.canRetry)
    }
}
