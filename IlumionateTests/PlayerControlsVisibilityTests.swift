//
//  PlayerControlsVisibilityTests.swift
//  IlumionateTests
//

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

    /// Short delay so these run fast; 0.2s is a generous settle window.
    private static let testDelay: Double = 0.05
    private static let settle: UInt64 = 200_000_000

    @Test("Controls hide once the idle delay elapses")
    func idleTimerHides() async {
        let v = PlayerControlsVisibility(autoHideDelay: Self.testDelay)
        v.registerInteraction()
        #expect(v.isVisible == true)

        try? await Task.sleep(nanoseconds: Self.settle)
        #expect(v.isVisible == false)
    }

    /// The reported bug: the idle timer fires while the "···" sheet is open and
    /// is swallowed by the drawer guard, and nothing ever re-arms it — so the
    /// controls stayed on screen forever once the sheet was dismissed.
    @Test("Closing a drawer re-arms the idle timer")
    func closingDrawerReArmsTimer() async {
        let v = PlayerControlsVisibility(autoHideDelay: Self.testDelay)
        v.registerInteraction()
        v.isDrawerOpen = true

        // Let the original timer fire and get swallowed by the drawer guard.
        try? await Task.sleep(nanoseconds: Self.settle)
        #expect(v.isVisible == true)

        v.isDrawerOpen = false

        try? await Task.sleep(nanoseconds: Self.settle)
        #expect(v.isVisible == false)
    }

    @Test("Opening a drawer does not itself hide the controls")
    func openingDrawerKeepsControlsUp() async {
        let v = PlayerControlsVisibility(autoHideDelay: Self.testDelay)
        v.registerInteraction()
        v.isDrawerOpen = true

        try? await Task.sleep(nanoseconds: Self.settle)
        #expect(v.isVisible == true)
    }

    @Test("Each interaction postpones the hide")
    func interactionPostponesHide() async {
        let v = PlayerControlsVisibility(autoHideDelay: Self.testDelay)
        v.registerInteraction()

        for _ in 0..<3 {
            try? await Task.sleep(nanoseconds: 20_000_000)   // inside the idle window
            v.registerInteraction()
            #expect(v.isVisible == true)
        }

        try? await Task.sleep(nanoseconds: Self.settle)
        #expect(v.isVisible == false)
    }
}
