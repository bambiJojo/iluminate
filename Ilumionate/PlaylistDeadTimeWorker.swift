//
//  PlaylistDeadTimeWorker.swift
//  Ilumionate
//
//  Keeps synchronous PCM scans off the actor that starts playlist playback.
//

import Foundation

typealias PlaylistDeadTimeOperation = @Sendable (URL) throws -> DeadTimeProfile

nonisolated enum PlaylistDeadTimeWorker {
    /// `@concurrent` is load-bearing. This app uses main-actor default isolation
    /// and approachable concurrency, so a plain async function would continue
    /// running on `PlaylistPlayerController`'s main actor.
    @concurrent
    static func analyze(
        url: URL,
        operation: PlaylistDeadTimeOperation? = nil
    ) async throws -> DeadTimeProfile {
        if let operation {
            return try operation(url)
        }
        return try AudioEnergyAnalyzer().analyze(url: url)
    }
}
