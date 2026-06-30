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

enum SessionSource: String, Sendable {
    case preset, generated, textTrance, mindMachine
}

enum AudioSource: String, Sendable {
    case files, url
}

enum MindMachineMode: String, Sendable {
    case flash, colorPulse, bilateral
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
