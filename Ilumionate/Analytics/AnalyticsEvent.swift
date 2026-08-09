//
//  AnalyticsEvent.swift
//  Ilumionate
//
//  Typed catalog of usage-analytics events. No SDK import lives here.
//  Parameter values are always enum raw values or bucketed numbers, so
//  no free-form user content can ever be attached to an event.
//

import Foundation

/// A single analytics signal: a stable name plus string-keyed parameters.
struct AnalyticsEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case signal
        case error(AnalyticsErrorCategory)
    }

    let name: String
    let parameters: [String: String]
    let kind: Kind

    init(
        _ name: String,
        _ parameters: [String: String] = [:],
        kind: Kind = .signal
    ) {
        self.name = name
        self.parameters = parameters
        self.kind = kind
    }
}

enum AnalyticsErrorCategory: Sendable {
    case thrownException
    case userInput
    case appState
}

enum AnalyticsError: String, Sendable {
    case audioFileImportFailed = "Audio.Import.FileFailed"
    case audioURLInvalid = "Audio.Import.URLInvalid"
    case audioURLServerRejected = "Audio.Import.URLServerRejected"
    case audioURLDownloadFailed = "Audio.Import.URLDownloadFailed"
    case audioAnalysisFailed = "Audio.Analysis.Failed"

    var category: AnalyticsErrorCategory {
        switch self {
        case .audioURLInvalid:
            .userInput
        case .audioFileImportFailed,
             .audioURLServerRejected,
             .audioURLDownloadFailed,
             .audioAnalysisFailed:
            .thrownException
        }
    }
}

/// Major navigable surfaces. Raw value becomes the event-name suffix.
enum AnalyticsScreen: String, CaseIterable, Sendable {
    // Core surfaces
    case home, library, read, create, profile
    case audioLibrary, analysisQueue, sessionDetail, player, onboarding
    // Long-tail surfaces (cut-list candidates)
    case browseSessions, sessionLibrary, libraryCreators, libraryFolders
    case streamingBrowser, phraseLibrary, lightScoreEditor
}

nonisolated enum SessionSource: String, Sendable {
    case preset, generated, textTrance, mindMachine
}

nonisolated enum PlaybackStartType: String, Sendable {
    case fresh, resumed
}

nonisolated enum PlaybackEndReason: String, Sendable {
    case completed, userStopped, dismissed
}

nonisolated enum SessionCompletionAction: String, Sendable {
    case done, replay, save, next
}

nonisolated enum PlaybackLifecycleTransition: String, Sendable {
    case backgrounded, foregrounded, interrupted, dismissed
}

nonisolated enum OnboardingCompletionAction: String, Sendable {
    case startWelcomeSession, exploreApp
}

/// The four doors on the launcher home screen. Raw values are wire format for
/// TelemetryDeck — renaming a case would silently split a metric in two, so
/// `audioLibrary` keeps its original spelling even though the door is "Listen".
nonisolated enum HomeCoreAction: String, Sendable {
    case audioLibrary, reader, visuals, pulse
}

nonisolated enum ActivationPath: String, Sendable {
    case playback, reading, audioAnalysis
}

nonisolated enum TimeToValueBucket: String, Equatable, Sendable {
    case under5Minutes, under1Hour, under1Day, oneDayOrMore

    init(seconds: TimeInterval) {
        switch max(0, seconds) {
        case ..<300: self = .under5Minutes
        case ..<3_600: self = .under1Hour
        case ..<86_400: self = .under1Day
        default: self = .oneDayOrMore
        }
    }
}

nonisolated enum AudioSource: String, Sendable {
    case files, url
}

nonisolated enum AudioFormatBucket: String, Equatable, Sendable {
    case mp3, m4a, wav, aiff, caf, other

    init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "mp3": self = .mp3
        case "m4a", "mp4", "aac": self = .m4a
        case "wav": self = .wav
        case "aif", "aiff": self = .aiff
        case "caf": self = .caf
        default: self = .other
        }
    }
}

nonisolated enum AudioDurationBucket: String, Equatable, Sendable {
    case underFiveMinutes, fiveToThirtyMinutes, thirtyToSixtyMinutes, sixtyMinutesOrMore

    init(seconds: TimeInterval) {
        switch max(0, seconds) {
        case ..<300: self = .underFiveMinutes
        case ..<1_800: self = .fiveToThirtyMinutes
        case ..<3_600: self = .thirtyToSixtyMinutes
        default: self = .sixtyMinutesOrMore
        }
    }
}

nonisolated enum AnalysisAttempt: String, Equatable, Sendable {
    case first, resumed
}

nonisolated enum AnalysisReadyAction: String, Sendable {
    case play
}

nonisolated enum AnalyticsAnalysisStage: String, Codable, Equatable, Sendable {
    case preparation, transcription, contentAnalysis, generation, persistence, unknown
}

nonisolated enum AnalyticsAnalysisFailureReason: String, Codable, Equatable, Sendable {
    case modelNotReady, modelInitialization, invalidAudio, noAudioData
    case transcription, contentAnalysis, generation, persistence, unknown

    init(error: any Error, stage: AnalyticsAnalysisStage) {
        if let analyzerError = error as? AnalyzerError {
            switch analyzerError {
            case .whisperKitNotInitialized:
                self = .modelNotReady
            case .whisperKitInitializationFailed:
                self = .modelInitialization
            case .transcriptionFailed:
                self = .transcription
            case .audioFileInvalid:
                self = .invalidAudio
            case .noAudioData:
                self = .noAudioData
            }
            return
        }

        switch stage {
        case .transcription: self = .transcription
        case .contentAnalysis: self = .contentAnalysis
        case .generation: self = .generation
        case .persistence: self = .persistence
        case .preparation, .unknown: self = .unknown
        }
    }
}

nonisolated enum ProcessingTimeBucket: String, Equatable, Sendable {
    case underOneMinute, oneToFiveMinutes, fiveToFifteenMinutes, fifteenMinutesOrMore

    init(seconds: TimeInterval) {
        switch max(0, seconds) {
        case ..<60: self = .underOneMinute
        case ..<300: self = .oneToFiveMinutes
        case ..<900: self = .fiveToFifteenMinutes
        default: self = .fifteenMinutesOrMore
        }
    }
}

nonisolated struct AudioAnalysisTelemetryContext: Equatable, Sendable {
    let format: AudioFormatBucket
    let duration: AudioDurationBucket
    let attempt: AnalysisAttempt

    init(format: AudioFormatBucket, duration: AudioDurationBucket, attempt: AnalysisAttempt) {
        self.format = format
        self.duration = duration
        self.attempt = attempt
    }

    init(audioFile: AudioFile, attempt: AnalysisAttempt) {
        self.init(
            format: AudioFormatBucket(fileExtension: audioFile.url.pathExtension),
            duration: AudioDurationBucket(seconds: audioFile.duration),
            attempt: attempt
        )
    }

    var parameters: [String: String] {
        [
            "format": format.rawValue,
            "duration": duration.rawValue,
            "attempt": attempt.rawValue,
        ]
    }
}

enum MindMachineMode: String, Sendable {
    case flash, colorPulse, bilateral, visualField
}

enum MindMachineEntryPoint: String, Sendable {
    case create, homePreset
}

nonisolated enum CreateMode: String, Sendable {
    case flash, colorPulse, bilateral, audioSession, visualField
}

nonisolated enum CreateFailureBucket: String, Sendable {
    case generation, persistence, cancelled, unknown
}

nonisolated enum ReturnWindow: String, Equatable, Sendable {
    case firstSeen, sameDay, oneToSevenDays, eightToThirtyDays, overThirtyDays

    init(days: Int?) {
        guard let days else {
            self = .firstSeen
            return
        }
        switch days {
        case ...0: self = .sameDay
        case 1...7: self = .oneToSevenDays
        case 8...30: self = .eightToThirtyDays
        default: self = .overThirtyDays
        }
    }
}

/// Bucketed completion fraction — exact playback time never leaves the device.
enum CompletionBucket: String, Sendable {
    case under25, b25_50, b50_75, b75_95, complete, notApplicable

    init(fraction: Double) {
        switch fraction {
        case ..<0.25: self = .under25
        case ..<0.50: self = .b25_50
        case ..<0.75: self = .b50_75
        case ..<0.95: self = .b75_95
        default:      self = .complete
        }
    }
}
