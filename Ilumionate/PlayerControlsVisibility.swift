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

    /// Whether the persistent Stop button has faded to its resting glyph.
    /// It never goes away — it is the one-tap exit — but at full strength it
    /// read as an undismissable banner over the whole session. Any touch
    /// brightens it again.
    private(set) var isStopControlDimmed: Bool = false

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
    private let stopDimDelay: Double
    private let idleWait: IdleWait
    private var hideTask: Task<Void, Never>?
    private var dimTask: Task<Void, Never>?

    init(
        voiceOverActive: @escaping @MainActor () -> Bool = { PlatformAccessibility.isVoiceOverRunning },
        autoHideDelay: Double = LiminalMotion.controlsAutoHideDelay,
        stopDimDelay: Double = LiminalMotion.stopControlDimDelay,
        idleWait: @escaping IdleWait = { try? await Task.sleep(for: $0) }
    ) {
        self.voiceOverActive = voiceOverActive
        self.autoHideDelay = autoHideDelay
        self.stopDimDelay = stopDimDelay
        self.idleWait = idleWait
    }

    /// Whether auto-hide is currently allowed.
    var canAutoHide: Bool { !isDrawerOpen && !isPaused && !voiceOverActive() }

    /// The compact player surface must keep a one-tap exit available whenever
    /// the full transport controls are hidden. This is especially important
    /// for modes that change the whole screen's brightness.
    var showsPersistentStopControl: Bool { !isVisible }

    /// User touched the screen: show controls and restart the idle timer.
    func registerInteraction() {
        dimTask?.cancel()
        withAnimation(LiminalMotion.fade) {
            isVisible = true
            isStopControlDimmed = false
        }
        scheduleAutoHide()
    }

    /// User touched the minimal overlay without revealing the controls:
    /// brighten the Stop button and restart its dim countdown.
    func registerOverlayTouch() {
        withAnimation(LiminalMotion.fade) { isStopControlDimmed = false }
        scheduleStopDim()
    }

    /// Force-hide now (respects suppression rules).
    func hideNow() {
        guard canAutoHide else { return }
        withAnimation(LiminalMotion.fade) { isVisible = false }
        scheduleStopDim()
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

    private func scheduleStopDim() {
        dimTask?.cancel()
        let wait = idleWait
        let delay = Duration.seconds(stopDimDelay)
        dimTask = Task { [weak self] in
            await wait(delay)
            guard let self, !Task.isCancelled, !self.isVisible else { return }
            withAnimation(LiminalMotion.fade) { self.isStopControlDimmed = true }
        }
    }

    func cancel() {
        hideTask?.cancel()
        dimTask?.cancel()
    }

    /// Awaits the pending countdown, so a test can observe the result without
    /// guessing how long the machine will take to get round to it.
    func awaitPendingAutoHide() async {
        await hideTask?.value
    }

    /// Awaits the pending Stop-button dim countdown; see `awaitPendingAutoHide`.
    func awaitPendingStopDim() async {
        await dimTask?.value
    }
}
