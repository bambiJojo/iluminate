//  MinimalOverlayGestureTests.swift
//  IlumionateTests

import CoreGraphics
import Testing
@testable import Ilumionate

struct MinimalOverlayGestureTests {

    private let threshold = MinimalOverlayGesture.revealThreshold
    private let screen = CGSize(width: 402, height: 874)

    /// Low on the screen, so the anchor clamp never applies.
    private func origin(x: CGFloat) -> CGPoint { CGPoint(x: x, y: 700) }

    // MARK: - Target placement

    @Test("A touch on the centre line pulls straight up")
    func centreTouchPullsStraightUp() {
        let o = origin(x: screen.width / 2)
        let t = MinimalOverlayGesture.target(for: o, in: screen)

        #expect(abs(t.x - o.x) < 0.0001)
        #expect(abs(t.y - (o.y - threshold)) < 0.0001)
    }

    @Test("A touch left of centre aims the target inward")
    func leftTouchAimsRight() {
        let o = origin(x: 40)
        let t = MinimalOverlayGesture.target(for: o, in: screen)

        #expect(t.x > o.x)          // toward the middle
        #expect(t.y < o.y)          // still upward
    }

    @Test("A touch right of centre aims the target inward")
    func rightTouchAimsLeft() {
        let o = origin(x: 380)
        let t = MinimalOverlayGesture.target(for: o, in: screen)

        #expect(t.x < o.x)
        #expect(t.y < o.y)
    }

    /// Vertical distance is constant no matter where you touch. That is what
    /// makes following the drawn line and pulling straight up finish at the
    /// same instant.
    @Test("The target is always exactly one threshold above the touch")
    func targetHeightIsConstant() {
        for x in [10.0, 100.0, 201.0, 300.0, 395.0] {
            let o = origin(x: x)
            let t = MinimalOverlayGesture.target(for: o, in: screen)
            let start = MinimalOverlayGesture.anchor(for: o)
            #expect(abs((start.y - t.y) - threshold) < 0.01, "wrong height at x=\(x)")
        }
    }

    /// Without a cap the target leans so far that the gesture stops reading as
    /// "pull up" at the screen edges.
    @Test("The sideways lean is capped")
    func lateralLeanIsCapped() {
        for x in [2.0, 400.0] {
            let o = origin(x: x)
            let t = MinimalOverlayGesture.target(for: o, in: screen)
            let start = MinimalOverlayGesture.anchor(for: o)
            #expect(abs(t.x - start.x) <= threshold, "lean too wide at x=\(x)")
        }
    }

    @Test("A touch near the top is clamped down so the target stays on screen")
    func highTouchIsClamped() {
        let o = CGPoint(x: 200, y: 10)
        let t = MinimalOverlayGesture.target(for: o, in: screen)
        #expect(t.y > 0)
    }

    // MARK: - Progress

    @Test("Progress is zero at rest")
    func zeroAtRest() {
        #expect(MinimalOverlayGesture.progress(
            for: .zero, from: origin(x: 200), in: screen) == 0)
    }

    @Test("Pulling along the angled line completes the pull")
    func pullingAlongTheLineCompletes() {
        let o = origin(x: 40)
        let start = MinimalOverlayGesture.anchor(for: o)
        let t = MinimalOverlayGesture.target(for: o, in: screen)
        let along = CGSize(width: t.x - start.x, height: t.y - start.y)

        let p = MinimalOverlayGesture.progress(for: along, from: o, in: screen)
        #expect(abs(p - 1) < 0.0001)
    }

    /// The forgiveness rule. Eyes shut, nobody can aim a diagonal — a straight
    /// pull up must always work even when the target is angled away from it.
    @Test("A straight-up pull always completes, even from the screen edge")
    func straightUpAlwaysCompletes() {
        for x in [8.0, 40.0, 201.0, 360.0, 398.0] {
            let p = MinimalOverlayGesture.progress(
                for: CGSize(width: 0, height: -threshold),
                from: origin(x: x),
                in: screen
            )
            #expect(abs(p - 1) < 0.0001, "straight-up pull failed at x=\(x)")
        }
    }

    @Test("Progress is linear across the pull")
    func linearProgress() {
        let p = MinimalOverlayGesture.progress(
            for: CGSize(width: 0, height: -threshold / 2),
            from: origin(x: 200), in: screen)
        #expect(abs(p - 0.5) < 0.0001)
    }

    @Test("Progress clamps at both ends")
    func progressClamps() {
        let o = origin(x: 200)
        #expect(MinimalOverlayGesture.progress(
            for: CGSize(width: 0, height: -1000), from: o, in: screen) == 1)
        #expect(MinimalOverlayGesture.progress(
            for: CGSize(width: 0, height: 1000), from: o, in: screen) == 0)
    }

    // MARK: - Reveal decision

    @Test("Reveal fires exactly when progress completes")
    func revealAgreesWithProgress() {
        let o = origin(x: 200)
        let justShort = CGSize(width: 0, height: -(threshold - 1))
        let exactly = CGSize(width: 0, height: -threshold)

        #expect(MinimalOverlayGesture.isReveal(translation: justShort, from: o, in: screen) == false)
        #expect(MinimalOverlayGesture.isReveal(translation: exactly, from: o, in: screen))
    }

    /// The property the whole design rests on: brushing the screen mid-session
    /// must never reach the threshold, from any touch point.
    @Test("No small or downward movement ever reveals")
    func brushNeverReveals() {
        for x in [20.0, 200.0, 380.0] {
            for h in stride(from: -(threshold - 1), through: threshold, by: 17.0) {
                let revealed = MinimalOverlayGesture.isReveal(
                    translation: CGSize(width: 0, height: h),
                    from: origin(x: x), in: screen)
                #expect(revealed == false, "revealed at x=\(x) h=\(h)")
            }
        }
    }

    @Test("Downward drags never reveal")
    func downwardNeverReveals() {
        #expect(MinimalOverlayGesture.isReveal(
            translation: CGSize(width: 0, height: 300),
            from: origin(x: 200), in: screen) == false)
    }

    /// Regression: an earlier version measured travel along the angled line, so
    /// a long horizontal swipe from the screen edge projected onto it and
    /// opened the controls.
    @Test("A sideways drag never reveals, from any touch point")
    func sidewaysNeverReveals() {
        for x in [8.0, 20.0, 200.0, 390.0] {
            for width in [-500.0, -400.0, 400.0, 500.0] {
                let revealed = MinimalOverlayGesture.isReveal(
                    translation: CGSize(width: width, height: 0),
                    from: origin(x: x), in: screen)
                #expect(revealed == false, "revealed on sideways drag at x=\(x) w=\(width)")
            }
        }
    }

    @Test("A diagonal drag counts only its upward part")
    func diagonalCountsVerticalOnly() {
        let o = origin(x: 200)
        let p = MinimalOverlayGesture.progress(
            for: CGSize(width: 400, height: -threshold / 2), from: o, in: screen)
        #expect(abs(p - 0.5) < 0.0001)
    }
}
