//
//  AppStoragePaths.swift
//  Ilumionate
//

import Foundation

/// Stable locations for user-visible intake and private implementation data.
nonisolated enum AppStoragePaths {
    static let supportRoot = URL.applicationSupportDirectory
        .appending(path: "LumeSync", directoryHint: .isDirectory)

    static let managedAudio = supportRoot
        .appending(path: "Audio", directoryHint: .isDirectory)

    static let analysisDirectory = supportRoot
        .appending(path: "Analysis", directoryHint: .isDirectory)

    static let analysisCache = analysisDirectory
        .appending(path: "AnalysisCache.json")

    static let analysisProgress = analysisDirectory
        .appending(path: "AnalysisProgress.json")

    static let generatedSessions = supportRoot
        .appending(path: "GeneratedSessions", directoryHint: .isDirectory)

    static let analyzerConfig = supportRoot
        .appending(path: "AnalyzerConfig.json")

    /// The real cable inbox. `UIFileSharingEnabled` exposes the Documents
    /// *root*, and Finder's device Files tab drops onto the app row — it cannot
    /// deliver into a subfolder. Anything watching only a subfolder watches a
    /// directory the primary transport cannot write to.
    ///
    /// The root is shared space: `TrainingCorpus/`, `TrainingOutput/`, and the
    /// review folder all live here, so it is scanned non-recursively and
    /// unrecognised files are left untouched.
    static let cableRootInbox = URL.documentsDirectory

    /// Optional second source. Finder cannot reach it, but the iOS Files app
    /// can, and there an unrecognised file genuinely is a failed import.
    static let cableDedicatedInbox = URL.documentsDirectory
        .appending(path: "Incoming Audio", directoryHint: .isDirectory)

    /// Kept beside the intake rather than inside it, so rejected files stay
    /// visible and recoverable in Finder without being rescanned.
    static let cableReview = URL.documentsDirectory
        .appending(path: "_Needs Review", directoryHint: .isDirectory)
}
