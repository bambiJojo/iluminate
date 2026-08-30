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

    /// Guardrail refusal attachments. Each embeds the prompt that was refused,
    /// which carries transcript excerpts, so these are kept out of the
    /// Finder-visible Documents root. See ERRORS.md ERR-024.
    static let guardrailFeedback = supportRoot
        .appending(path: "Guardrail Feedback", directoryHint: .isDirectory)

    /// The real cable inbox. `UIFileSharingEnabled` exposes the Documents
    /// *root*, and Finder's device Files tab drops onto the app row — it cannot
    /// deliver into a subfolder. Anything watching only a subfolder watches a
    /// directory the primary transport cannot write to.
    ///
    /// The root is shared space: `TrainingCorpus/`, `TrainingOutput/`, the
    /// review folder and the imported archive all live here. It is walked
    /// recursively — dragging twenty files usually means dragging the folder
    /// holding them — with app-owned directories excluded by name, and
    /// unrecognised files left untouched.
    static let cableRootInbox = URL.documentsDirectory

    /// Optional second source. Finder cannot reach it, but the iOS Files app
    /// can, and there an unrecognised file genuinely is a failed import.
    static let cableDedicatedInbox = URL.documentsDirectory
        .appending(path: "Incoming Audio", directoryHint: .isDirectory)

    /// Text and document counterpart to `cableDedicatedInbox`. Both dedicated
    /// inboxes accept either kind — classification is by file, not by folder —
    /// so a misfiled drop still imports. The second folder exists to make the
    /// capability discoverable in the Files app, not to partition it.
    static let cableTextInbox = URL.documentsDirectory
        .appending(path: "Incoming Text", directoryHint: .isDirectory)

    /// Where a successfully imported document's source file is kept.
    ///
    /// The reader stores only extracted text, so the dropped file is the user's
    /// only copy. Audio can be moved into private managed storage because the
    /// library still addresses it; a document has nothing addressing it, so it
    /// stays visible and recoverable here instead.
    static let cableImported = URL.documentsDirectory
        .appending(path: "_Imported", directoryHint: .isDirectory)

    /// Kept beside the intake rather than inside it, so rejected files stay
    /// visible and recoverable in Finder without being rescanned.
    static let cableReview = URL.documentsDirectory
        .appending(path: "_Needs Review", directoryHint: .isDirectory)
}
