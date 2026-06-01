//
//  Logging.swift
//  Ilumionate
//
//  Centralized os.Logger categories. Replaces ad-hoc print() debugging so logs
//  are level-filterable, attributed to a subsystem/category, and stripped from
//  release output when appropriate.
//

import os

/// Per-subsystem loggers for the app. Use the category that matches the call site's domain.
///
/// Loggers are explicitly `nonisolated`: with `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, these static properties would otherwise be main-actor isolated and
/// unusable from nonisolated domain code (analyzers, parsers, services). `Logger`
/// is `Sendable`, so this is safe and removes a whole class of Swift 6 isolation
/// errors at the logging layer.
enum Log {
    nonisolated private static let subsystem = "com.byronquine.lumenSync"

    /// Content analysis pipeline: transcription, phase analysis, generation, queueing.
    nonisolated static let analysis = Logger(subsystem: subsystem, category: "analysis")
    /// Audio capture, import, playback, and sync.
    nonisolated static let audio = Logger(subsystem: subsystem, category: "audio")
    /// Real-time light engine and entrainment.
    nonisolated static let engine = Logger(subsystem: subsystem, category: "engine")
    /// Streaming sources and in-app browser.
    nonisolated static let streaming = Logger(subsystem: subsystem, category: "streaming")
    /// SwiftUI views and presentation.
    nonisolated static let ui = Logger(subsystem: subsystem, category: "ui")
    /// Anything that doesn't fit a more specific category.
    nonisolated static let general = Logger(subsystem: subsystem, category: "general")
}
