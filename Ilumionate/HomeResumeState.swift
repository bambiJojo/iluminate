//
//  HomeResumeState.swift
//  Ilumionate
//
//  What the home resume pill shows.
//
//  Derived from PlaybackProgressStore rather than from its own record: that
//  store already persists contentID, kind, title, progress and duration, keeps
//  the twenty most recent entries newest-first, and is already what LibraryView
//  reads. A second source of truth would only be a second thing to keep in sync.
//

import Foundation

struct HomeResumeState: Equatable, Sendable {
    let contentID: String
    let kind: ResumablePlaybackKind
    let title: String
    /// Clamped to 0...1.
    let progress: Double
    /// Seconds left, never negative.
    let remaining: TimeInterval

    init?(snapshot: PlaybackProgressSnapshot?) {
        guard let snapshot, snapshot.duration > 0 else { return nil }
        let clamped = min(max(snapshot.progress, 0), 1)
        self.contentID = snapshot.contentID
        self.kind = snapshot.kind
        self.title = snapshot.title
        self.progress = clamped
        self.remaining = max(0, snapshot.duration - snapshot.duration * clamped)
    }
}
