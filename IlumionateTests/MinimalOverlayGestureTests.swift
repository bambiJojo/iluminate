//  MinimalOverlayGestureTests.swift
//  IlumionateTests

import CoreGraphics
import Testing
@testable import Ilumionate

struct MinimalOverlayGestureTests {

    private let threshold = MinimalOverlayGesture.revealThreshold

    // MARK: - Progress

    @Test("Progress is zero at rest")
    func zeroAtRest() {
        #expect(MinimalOverlayGesture.progress(for: .zero) == 0)
    }

    @Test("Progress reaches one exactly at the threshold")
    func oneAtThreshold() {
        let p = MinimalOverlayGesture.progress(for: CGSize(width: 0, height: -threshold))
        #expect(abs(p - 1) < 0.0001)
    }

    @Test("Progress is linear across the pull")
    func linearProgress() {
        let half = MinimalOverlayGesture.progress(for: CGSize(width: 0, height: -threshold / 2))
        #expect(abs(half - 0.5) < 0.0001)
    }

    @Test("Progress clamps at both ends")
    func progressClamps() {
        #expect(MinimalOverlayGesture.progress(for: CGSize(width: 0, height: -1000)) == 1)
        #expect(MinimalOverlayGesture.progress(for: CGSize(width: 0, height: 1000)) == 0)
    }

    @Test("Sideways movement contributes nothing")
    func sidewaysIgnored() {
        #expect(MinimalOverlayGesture.progress(for: CGSize(width: 500, height: 0)) == 0)
        // A diagonal pull is judged only on its vertical component.
        let diagonal = MinimalOverlayGesture.progress(
            for: CGSize(width: 300, height: -threshold)
        )
        #expect(abs(diagonal - 1) < 0.0001)
    }

    // MARK: - Reveal decision

    @Test("Reveal fires exactly when progress completes")
    func revealAgreesWithProgress() {
        let justShort = CGSize(width: 0, height: -(threshold - 1))
        let exactly = CGSize(width: 0, height: -threshold)

        #expect(MinimalOverlayGesture.isReveal(translation: justShort) == false)
        #expect(MinimalOverlayGesture.isReveal(translation: exactly))
        // The affordance filling up and the controls appearing must never disagree.
        #expect(MinimalOverlayGesture.progress(for: exactly) >= 1)
    }

    /// The property the whole design rests on: brushing the screen mid-session
    /// must never reach the threshold.
    @Test("No small or downward movement ever reveals")
    func brushNeverReveals() {
        for h in stride(from: -(threshold - 1), through: threshold, by: 9.0) {
            let t = CGSize(width: 0, height: h)
            #expect(MinimalOverlayGesture.isReveal(translation: t) == false)
        }
    }

    @Test("Downward drags never reveal")
    func downwardNeverReveals() {
        #expect(MinimalOverlayGesture.isReveal(translation: CGSize(width: 0, height: 300)) == false)
    }
}
