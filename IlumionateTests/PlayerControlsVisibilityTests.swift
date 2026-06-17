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
}
