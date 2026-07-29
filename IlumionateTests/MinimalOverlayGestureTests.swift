//  MinimalOverlayGestureTests.swift
//  IlumionateTests

import CoreGraphics
import Testing
@testable import Ilumionate

struct MinimalOverlayGestureTests {

    @Test("A deliberate upward swipe reveals the controls")
    func upwardSwipeReveals() {
        #expect(MinimalOverlayGesture.from(translation: CGSize(width: 0, height: -80)) == .reveal)
        #expect(MinimalOverlayGesture.from(translation: CGSize(width: 12, height: -120)) == .reveal)
    }

    @Test("A swipe just past the threshold still reveals")
    func thresholdBoundary() {
        #expect(MinimalOverlayGesture.from(translation: CGSize(width: 0, height: -41)) == .reveal)
        // Exactly at the threshold is not past it.
        #expect(MinimalOverlayGesture.from(translation: CGSize(width: 0, height: -40)) != .reveal)
    }

    @Test("A stationary touch only pulses the hint")
    func tapHints() {
        #expect(MinimalOverlayGesture.from(translation: .zero) == .hint)
        #expect(MinimalOverlayGesture.from(translation: CGSize(width: 4, height: 5)) == .hint)
    }

    /// The whole point of the change: brushing the screen mid-session must not
    /// light up the chrome.
    @Test("A brush or small drift never reveals")
    func smallMovementNeverReveals() {
        for h in stride(from: -39.0, through: 39.0, by: 13.0) {
            let result = MinimalOverlayGesture.from(translation: CGSize(width: 0, height: h))
            #expect(result != .reveal)
        }
    }

    @Test("Downward and sideways drags are ignored")
    func otherDirectionsIgnored() {
        #expect(MinimalOverlayGesture.from(translation: CGSize(width: 0, height: 90)) == .ignore)
        #expect(MinimalOverlayGesture.from(translation: CGSize(width: 120, height: 0)) == .ignore)
        #expect(MinimalOverlayGesture.from(translation: CGSize(width: -120, height: 2)) == .ignore)
    }

    /// A mostly-sideways swipe that happens to clear the vertical threshold is
    /// still a reveal — fingers wander when the eyes are shut.
    @Test("A sloppy diagonal swipe still reveals")
    func sloppyDiagonalReveals() {
        #expect(MinimalOverlayGesture.from(translation: CGSize(width: 90, height: -60)) == .reveal)
    }
}
