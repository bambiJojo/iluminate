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
