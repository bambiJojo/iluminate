//
//  PlayerControlsVisibility.swift
//  Ilumionate
//
//  Observable model for Pure Void controls auto-hide. Controls fade after
//  an idle delay, but never while the drawer is open or VoiceOver is running.
//

import SwiftUI

@MainActor
@Observable
final class PlayerControlsVisibility {
    var isVisible: Bool = true

    /// Whether the persistent Stop button has shrunk to its icon-only
    /// resting form. It never goes away — it is the one-tap exit — but at full
    /// size it read as an undismissable banner over the whole session. Any
    /// touch expands it again.
    private(set) var isStopControlCompact: Bool = false

    /// Set once the user has revealed the controls by swiping, persisted
    /// through `SwipeRevealHint` so the hint never returns.
    private(set) var isSwipeHintLearned: Bool

    /// Set while a sheet ("···", track list) or a bloom slider is open, which
    /// suppresses auto-hide. Closing it re-arms the idle timer: the original
    /// timer will have fired and been swallowed by the suppression guard, so
    /// without this the controls would stay on screen indefinitely.
    var isDrawerOpen: Bool = false {
        didSet {
            guard oldValue, !isDrawerOpen else { return }
            scheduleAutoHide()
        }
    }

    /// Set while playback is not running. Someone who has paused is deciding
    /// something, not sinking into a session, and hiding the controls leaves
    /// them facing a still screen with nothing to touch. Re-arms on resume, for
    /// the same reason `isDrawerOpen` does.
    var isPaused: Bool = false {
        didSet {
            guard oldValue, !isPaused else { return }
            scheduleAutoHide()
        }
    }

    /// How the idle countdown waits.
    ///
    /// Injectable so tests need no wall clock. Sleeping for a short real delay
    /// and then sleeping a bit longer to observe the result only works while the
    /// machine is idle: run under the full suite, where dozens of `@MainActor`
    /// suites queue on one actor, the countdown's task was not scheduled for
    /// tens of seconds and the assertions read a stale value.
    typealias IdleWait = @Sendable (Duration) async -> Void

    private let voiceOverActive: @MainActor () -> Bool
    private let autoHideDelay: Double
    private let stopCompactDelay: Double
    private let swipeHint: SwipeRevealHint
    private let idleWait: IdleWait
    private var hideTask: Task<Void, Never>?
    private var compactTask: Task<Void, Never>?

    init(
        voiceOverActive: @escaping @MainActor () -> Bool = { PlatformAccessibility.isVoiceOverRunning },
        autoHideDelay: Double = LiminalMotion.controlsAutoHideDelay,
        stopCompactDelay: Double = LiminalMotion.stopControlCompactDelay,
        swipeHint: SwipeRevealHint = SwipeRevealHint(),
        idleWait: @escaping IdleWait = { try? await Task.sleep(for: $0) }
    ) {
        self.voiceOverActive = voiceOverActive
        self.autoHideDelay = autoHideDelay
        self.stopCompactDelay = stopCompactDelay
        self.swipeHint = swipeHint
        self.isSwipeHintLearned = !swipeHint.isVisible
        self.idleWait = idleWait
    }

    /// Whether auto-hide is currently allowed.
    var canAutoHide: Bool { !isDrawerOpen && !isPaused && !voiceOverActive() }

    /// The compact player surface must keep a one-tap exit available whenever
    /// the full transport controls are hidden. This is especially important
    /// for modes that change the whole screen's brightness.
    var showsPersistentStopControl: Bool { !isVisible }

    /// "Swipe up to show controls" teaches a gesture, so it shows only until
    /// the gesture is learned, and only while the Stop button is expanded —
    /// it times out with the same idle countdown rather than sitting on
    /// screen for the whole session.
    var showsSwipeHint: Bool {
        showsPersistentStopControl && !isSwipeHintLearned && !isStopControlCompact
    }

    /// User touched the screen: show controls and restart the idle timer.
    func registerInteraction() {
        compactTask?.cancel()
        withAnimation(LiminalMotion.fade) {
            isVisible = true
            isStopControlCompact = false
        }
        scheduleAutoHide()
    }

    /// A swipe or pull revealed the controls. Only a reveal from the hidden
    /// state proves the gesture was learned.
    func registerSwipeReveal() {
        if !isVisible, !isSwipeHintLearned {
            swipeHint.recordReveal()
            isSwipeHintLearned = true
        }
        registerInteraction()
    }

    /// User touched the minimal overlay without revealing the controls:
    /// expand the Stop button and restart its idle countdown.
    func registerOverlayTouch() {
        withAnimation(LiminalMotion.fade) { isStopControlCompact = false }
        scheduleStopCompact()
    }

    /// Force-hide now (respects suppression rules).
    func hideNow() {
        guard canAutoHide else { return }
        withAnimation(LiminalMotion.fade) { isVisible = false }
        scheduleStopCompact()
    }

    /// Begin/refresh the idle countdown.
    func scheduleAutoHide() {
        hideTask?.cancel()
        let wait = idleWait
        let delay = Duration.seconds(autoHideDelay)
        hideTask = Task { [weak self] in
            await wait(delay)
            guard let self, !Task.isCancelled else { return }
            self.hideNow()
        }
    }

    private func scheduleStopCompact() {
        compactTask?.cancel()
        let wait = idleWait
        let delay = Duration.seconds(stopCompactDelay)
        compactTask = Task { [weak self] in
            await wait(delay)
            guard let self, !Task.isCancelled, !self.isVisible else { return }
            withAnimation(LiminalMotion.fade) { self.isStopControlCompact = true }
        }
    }

    func cancel() {
        hideTask?.cancel()
        compactTask?.cancel()
    }

    /// Awaits the pending countdown, so a test can observe the result without
    /// guessing how long the machine will take to get round to it.
    func awaitPendingAutoHide() async {
        await hideTask?.value
    }

    /// Awaits the pending Stop-button idle countdown; see `awaitPendingAutoHide`.
    func awaitPendingStopCompact() async {
        await compactTask?.value
    }
}
