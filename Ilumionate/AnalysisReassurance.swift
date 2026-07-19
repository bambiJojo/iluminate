//
//  AnalysisReassurance.swift
//  Ilumionate
//
//  Time-based reassurance copy shown while a long analysis is running.
//  Analysis is a one-time cost per file (results are cached by content
//  fingerprint), so the messaging frames the wait as an investment.
//

import Foundation

/// Produces the "still working, hang in there" message for long-running
/// analyses. Pure function of elapsed time so it is trivially testable and
/// every progress surface (overlay bar, full-screen view) stays consistent.
nonisolated enum AnalysisReassurance {

    /// No reassurance is shown before this much time has elapsed —
    /// short analyses should finish without ever seeing it.
    static let activationDelay: TimeInterval = 45

    /// Once active, the message rotates at this cadence.
    static let rotationInterval: TimeInterval = 20

    /// Rotation order: acknowledge the wait first, then explain why it's worth it.
    static let messages: [String] = [
        "Still working — hang in there. Deep audio analysis takes a little while.",
        "This is a one-time thing: each file only ever needs to be analyzed once.",
        "Once it's done, this file's light session loads instantly — every time you play it.",
        "Longer files take longer, but the result is totally worth the wait."
    ]

    /// Returns the reassurance message for the given elapsed time, or `nil`
    /// while the analysis is still young enough not to need one.
    static func message(elapsed: TimeInterval) -> String? {
        guard elapsed >= activationDelay else { return nil }
        let rotations = Int((elapsed - activationDelay) / rotationInterval)
        return messages[rotations % messages.count]
    }
}
