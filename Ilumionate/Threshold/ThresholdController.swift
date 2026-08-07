//
//  ThresholdController.swift
//  Ilumionate
//
//  Owns the launch threshold's clock, its phase, and the decision about
//  whether it should run at all.
//
//  The controller takes an injected `now` on every call rather than reading the
//  clock itself, so the whole phase machine is testable without waiting.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class ThresholdController {

    enum Phase: Equatable {
        case running(start: Date)
        case exiting(from: ThresholdChoreography.Frame, start: Date)
        case finished
    }

    private let choreography: ThresholdChoreography
    private(set) var phase: Phase

    /// - Parameters:
    ///   - isSuppressed: when true the threshold never appears. See
    ///     `shouldSuppress` for the two cases that set it.
    ///   - motion: `.reduced` mirrors the Reduce Motion accessibility setting.
    init(isSuppressed: Bool, motion: ThresholdChoreography.Motion, now: Date = .now) {
        self.choreography = ThresholdChoreography(motion: motion)
        self.phase = isSuppressed ? .finished : .running(start: now)
    }

    var isPresenting: Bool {
        phase != .finished
    }

    var isExiting: Bool {
        if case .exiting = phase { return true }
        return false
    }

    var totalDuration: TimeInterval {
        choreography.totalDuration
    }

    /// Restarts the clock. The view calls this on appear so the arc is timed
    /// from the first frame actually drawn, not from init.
    func begin(at now: Date) {
        guard case .running = phase else { return }
        phase = .running(start: now)
    }

    /// Captures the current frame and eases out from it. A no-op unless the
    /// arc is still running, so a double tap cannot restart the interpolation.
    func skip(now: Date) {
        guard case .running = phase else { return }
        phase = .exiting(from: frame(at: now), start: now)
    }

    func finish() {
        phase = .finished
    }

    func frame(at now: Date) -> ThresholdChoreography.Frame {
        switch phase {
        case .running(let start):
            choreography.frame(atElapsed: now.timeIntervalSince(start))
        case .exiting(let captured, let start):
            choreography.exitFrame(
                from: captured,
                progress: now.timeIntervalSince(start) / ThresholdChoreography.skipDuration
            )
        case .finished:
            choreography.frame(atElapsed: choreography.totalDuration)
        }
    }

    /// True once the current phase has run its course at `now`.
    func hasElapsed(at now: Date) -> Bool {
        switch phase {
        case .running(let start):
            now.timeIntervalSince(start) >= choreography.totalDuration
        case .exiting(_, let start):
            now.timeIntervalSince(start) >= ThresholdChoreography.skipDuration
        case .finished:
            true
        }
    }

    // MARK: - Suppression

    /// The threshold stands down in two situations, both of them cases where
    /// playing it would actively hurt.
    static var shouldSuppress: Bool {
        // First launch: `ContentView.checkForFirstLaunch()` raises Onboarding
        // 800ms after appear — squarely inside the Bloom beat. Onboarding is
        // the entry experience that time; the threshold is not needed.
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            return true
        }

        #if canImport(UIKit)
        // VoiceOver: a decorative animation with nothing to announce that
        // blocks the shell for 2.6 seconds is hostile to a screen reader user.
        if UIAccessibility.isVoiceOverRunning {
            return true
        }
        #endif

        return false
    }
}
