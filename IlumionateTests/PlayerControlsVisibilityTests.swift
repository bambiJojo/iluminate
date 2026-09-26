//
//  PlayerControlsVisibilityTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

@MainActor
struct PlayerControlsVisibilityTests {

    @Test("Starts visible")
    func startsVisible() {
        let v = PlayerControlsVisibility()
        #expect(v.isVisible == true)
    }

    @Test("Interaction shows controls")
    func interactionShows() {
        let v = PlayerControlsVisibility()
        v.hideNow()
        #expect(v.isVisible == false)
        v.registerInteraction()
        #expect(v.isVisible == true)
    }

    @Test("Hidden controls leave the persistent stop control available")
    func hiddenControlsLeavePersistentStopAvailable() {
        let v = PlayerControlsVisibility()
        v.hideNow()

        #expect(v.showsPersistentStopControl)
    }

    @Test("Auto-hide is suppressed while the drawer is open")
    func drawerSuppressesHide() {
        let v = PlayerControlsVisibility()
        v.isDrawerOpen = true
        v.hideNow()
        #expect(v.isVisible == true)   // refuses to hide while drawer is open
    }

    @Test("Auto-hide is suppressed under VoiceOver")
    func voiceOverSuppressesHide() {
        let v = PlayerControlsVisibility(voiceOverActive: { true })
        v.hideNow()
        #expect(v.isVisible == true)
    }

    @Test("Auto-hide is suppressed while playback is not running")
    func pauseSuppressesHide() {
        // A paused session that hides its controls leaves the user facing a
        // still screen with nothing to touch.
        let v = PlayerControlsVisibility()
        v.isPaused = true
        v.hideNow()
        #expect(v.isVisible == true)
        #expect(v.canAutoHide == false)
    }

    @Test("Resuming allows auto-hide again")
    func resumeRestoresAutoHide() {
        let v = PlayerControlsVisibility()
        v.isPaused = true
        v.isPaused = false
        #expect(v.canAutoHide)
        v.hideNow()
        #expect(v.isVisible == false)
    }

    // MARK: - Idle timer

    // No wall clock. The countdown's wait is injected and returns immediately,
    // and `awaitPendingAutoHide()` reports when the hide has actually run — so
    // these no longer depend on the machine getting round to a 50ms timer
    // inside a 200ms window, which is what failed under the full suite.
    private static func immediateHide() -> PlayerControlsVisibility {
        PlayerControlsVisibility(idleWait: { _ in })
    }

    @Test("Controls hide once the idle delay elapses")
    func idleTimerHides() async {
        let v = Self.immediateHide()
        v.registerInteraction()
        #expect(v.isVisible == true)

        await v.awaitPendingAutoHide()
        #expect(v.isVisible == false)
    }

    /// The reported bug: the idle timer fires while the "···" sheet is open and
    /// is swallowed by the drawer guard, and nothing ever re-arms it — so the
    /// controls stayed on screen forever once the sheet was dismissed.
    @Test("Closing a drawer re-arms the idle timer")
    func closingDrawerReArmsTimer() async {
        let v = Self.immediateHide()
        v.registerInteraction()
        v.isDrawerOpen = true

        // The original countdown fires and is swallowed by the drawer guard.
        await v.awaitPendingAutoHide()
        #expect(v.isVisible == true)

        v.isDrawerOpen = false

        await v.awaitPendingAutoHide()
        #expect(v.isVisible == false)
    }

    @Test("Opening a drawer does not itself hide the controls")
    func openingDrawerKeepsControlsUp() async {
        let v = Self.immediateHide()
        v.registerInteraction()
        v.isDrawerOpen = true

        await v.awaitPendingAutoHide()
        #expect(v.isVisible == true)
    }

    @Test("Each interaction postpones the hide")
    func interactionPostponesHide() async {
        // A countdown that only completes once released, so "still inside the
        // idle window" is a fact rather than a race against a 20ms sleep.
        let gate = IdleGate()
        let v = PlayerControlsVisibility(idleWait: { _ in await gate.wait() })
        v.registerInteraction()

        for _ in 0..<3 {
            v.registerInteraction()
            #expect(v.isVisible == true)
        }

        gate.release()
        await v.awaitPendingAutoHide()
        #expect(v.isVisible == false)
    }

    // MARK: - Stop control idle state

    /// The reported bug: the Stop button sat at full size for the whole
    /// session and could not be dismissed. It must stay available, so it
    /// shrinks to an icon instead of disappearing.
    @Test("The stop control goes compact once the controls have been hidden a while")
    func stopControlCompactsAfterIdle() async {
        let v = Self.immediateHide()
        v.registerInteraction()
        await v.awaitPendingAutoHide()
        #expect(v.showsPersistentStopControl)

        // Not-yet-compact is covered by stopControlWaitsBeforeCompacting: with
        // an instant wait the countdown may already have run by this point.
        await v.awaitPendingStopCompact()
        #expect(v.isStopControlCompact)
        #expect(v.showsPersistentStopControl)
    }

    @Test("The stop control waits for its own idle delay before going compact")
    func stopControlWaitsBeforeCompacting() async {
        let gate = IdleGate()
        let v = PlayerControlsVisibility(idleWait: { _ in await gate.wait() })
        v.hideNow()
        #expect(v.isStopControlCompact == false)

        gate.release()
        await v.awaitPendingStopCompact()
        #expect(v.isStopControlCompact)
    }

    @Test("Touching the screen expands a compact stop control")
    func touchExpandsStopControl() async {
        let v = Self.immediateHide()
        v.hideNow()
        await v.awaitPendingStopCompact()
        #expect(v.isStopControlCompact)

        v.registerOverlayTouch()
        #expect(v.isStopControlCompact == false)
        #expect(v.isVisible == false)   // a touch alone does not reveal the controls
    }

    @Test("Revealing the controls clears the compact state")
    func revealClearsCompact() async {
        let v = Self.immediateHide()
        v.hideNow()
        await v.awaitPendingStopCompact()

        v.registerInteraction()
        #expect(v.isStopControlCompact == false)
    }

    @Test("A compact countdown that fires after the controls return does nothing")
    func staleCompactIgnoredWhenVisible() async {
        let gate = IdleGate()
        let v = PlayerControlsVisibility(idleWait: { _ in await gate.wait() })
        v.hideNow()
        v.isPaused = true        // controls come back and stay up
        v.registerInteraction()

        gate.release()
        await v.awaitPendingStopCompact()
        #expect(v.isStopControlCompact == false)
    }

    // MARK: - Swipe hint

    private static func withHintDefaults(
        _ body: (UserDefaults) async throws -> Void
    ) async throws {
        let suite = "PlayerControlsVisibilityTests.hint.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    @Test("A new user sees the swipe hint while the controls are hidden")
    func hintShowsForNewUser() async throws {
        try await Self.withHintDefaults { defaults in
            let v = PlayerControlsVisibility(
                swipeHint: SwipeRevealHint(defaults: defaults),
                idleWait: { _ in await IdleGate().wait() }
            )
            #expect(v.showsSwipeHint == false)   // controls up: nothing to hint at
            v.hideNow()
            #expect(v.showsSwipeHint)
        }
    }

    @Test("The hint goes away the moment the swipe is learned, and stays gone")
    func hintRetiresOnFirstReveal() async throws {
        try await Self.withHintDefaults { defaults in
            let v = PlayerControlsVisibility(
                swipeHint: SwipeRevealHint(defaults: defaults),
                idleWait: { _ in await IdleGate().wait() }
            )
            v.hideNow()
            v.registerSwipeReveal()
            v.hideNow()
            #expect(v.showsSwipeHint == false)

            // A later session reads the persisted state.
            let next = PlayerControlsVisibility(swipeHint: SwipeRevealHint(defaults: defaults))
            next.hideNow()
            #expect(next.showsSwipeHint == false)
        }
    }

    @Test("The hint times out with the stop control's idle countdown")
    func hintTimesOut() async throws {
        try await Self.withHintDefaults { defaults in
            let v = PlayerControlsVisibility(
                swipeHint: SwipeRevealHint(defaults: defaults),
                idleWait: { _ in }
            )
            v.hideNow()
            await v.awaitPendingStopCompact()
            #expect(v.showsSwipeHint == false)
            #expect(v.showsPersistentStopControl)   // the exit itself stays
        }
    }

    @Test("A swipe while the controls are already up does not count as learning")
    func revealWhileVisibleDoesNotRetireHint() async throws {
        try await Self.withHintDefaults { defaults in
            let v = PlayerControlsVisibility(
                swipeHint: SwipeRevealHint(defaults: defaults),
                idleWait: { _ in await IdleGate().wait() }
            )
            v.registerSwipeReveal()   // controls start visible
            v.hideNow()
            #expect(v.showsSwipeHint)
        }
    }
}

/// A countdown the test decides the length of.
private final class IdleGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiting.append(continuation)
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        isOpen = true
        let pending = waiting
        waiting.removeAll()
        lock.unlock()
        for continuation in pending { continuation.resume() }
    }
}
