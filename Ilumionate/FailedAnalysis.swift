//
//  FailedAnalysis.swift
//  Ilumionate
//
//  Model for a failed analysis attempt, surfaced in AnalyzerView.
//

import Foundation

nonisolated enum AnalysisRecoveryStage: String, Codable, Equatable, Sendable {
    case none
    case transcription
    case analysis
}

nonisolated enum AnalysisRetryState: Equatable, Sendable {
    case automatic
    case manual
    case unavailable
}

/// Stable, user-facing failure copy. Technical error strings remain local for
/// diagnostics, but never become the primary recovery instructions.
nonisolated struct AnalysisFailurePresentation: Equatable, Sendable {
    let reason: AnalyticsAnalysisFailureReason
    let failedStage: AnalyticsAnalysisStage
    let recoveryStage: AnalysisRecoveryStage
    let retryState: AnalysisRetryState

    var title: String {
        switch reason {
        case .invalidAudio: "Audio file can’t be read"
        case .noAudioData: "No audible audio found"
        case .modelNotReady, .modelInitialization: "Analyzer isn’t ready"
        case .transcription: "Transcription paused"
        case .contentAnalysis: "Content analysis paused"
        case .generation: "Session generation paused"
        case .persistence: "Session couldn’t be saved"
        case .unknown: "Analysis paused"
        }
    }

    var message: String {
        switch reason {
        case .invalidAudio:
            "LumeSync couldn’t open this audio file."
        case .noAudioData:
            "The file opened, but it didn’t contain audio that could be analyzed."
        case .modelNotReady, .modelInitialization:
            "The on-device analyzer couldn’t start. Keep LumeSync open and try again."
        case .transcription:
            "LumeSync couldn’t finish turning the audio into text."
        case .contentAnalysis:
            "The transcript is safe, but its content analysis didn’t finish."
        case .generation:
            "The analysis is safe, but the light session wasn’t generated."
        case .persistence:
            "The analysis is safe, but the generated session wasn’t saved."
        case .unknown:
            "LumeSync couldn’t finish this analysis."
        }
    }

    var recoveryMessage: String {
        switch reason {
        case .invalidAudio:
            "Remove this copy and re-import the original audio file."
        case .noAudioData:
            "Check that the source file contains audible sound, then import another copy."
        default:
            switch retryState {
            case .automatic:
                "LumeSync will try again automatically when processing resumes."
            case .manual:
                switch recoveryStage {
                case .transcription:
                    "Retry to continue from the saved transcript without transcribing again."
                case .analysis:
                    "Retry to continue from the saved analysis."
                case .none:
                    "Retry when the app is active and keep it open while analysis starts."
                }
            case .unavailable:
                "Import a different audio file to continue."
            }
        }
    }

    var statusMessage: String? {
        if retryState == .automatic { return "Retry scheduled" }
        switch recoveryStage {
        case .transcription: return "Transcript saved"
        case .analysis: return "Analysis saved"
        case .none: return nil
        }
    }

    var canRetry: Bool { retryState != .unavailable }
}

struct FailedAnalysis: Identifiable, Sendable {
    var id: UUID { audioFile.id }
    let audioFile: AudioFile
    /// Retained for local logs and debugging; UI uses `presentation`.
    let technicalMessage: String
    let failedAt: Date
    let reason: AnalyticsAnalysisFailureReason
    let failedStage: AnalyticsAnalysisStage
    let recoveryStage: AnalysisRecoveryStage
    let retryState: AnalysisRetryState

    var presentation: AnalysisFailurePresentation {
        AnalysisFailurePresentation(
            reason: reason,
            failedStage: failedStage,
            recoveryStage: recoveryStage,
            retryState: retryState
        )
    }

    var errorMessage: String { presentation.message }
}
