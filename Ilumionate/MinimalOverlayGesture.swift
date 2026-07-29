//
//  MinimalOverlayGesture.swift
//  Ilumionate
//
//  Where the pull target sits and how far through the pull the user is.
//
//  Extracted from the view because this decision has been wrong twice: the
//  reveal swipe was once attached to an ancestor of a full-screen Button,
//  which silently swallowed it. Keeping the geometry here means it is pinned
//  by tests rather than by hope.
//

import CoreGraphics

enum MinimalOverlayGesture {

    /// Travel required to reveal, and the distance the target is drawn at.
    ///
    /// Sized so the target clears the hand doing the pulling — at 72pt it sat
    /// under the user's own finger. Still an easy thumb travel, and far beyond
    /// anything a brush could reach.
    static let revealThreshold: CGFloat = 150

    /// Keeps the target on screen when the touch starts high up.
    private static let topMargin: CGFloat = 60

    /// The touch point, held far enough down the screen that the target above
    /// it still has room to be drawn.
    static func anchor(for origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x, y: max(origin.y, revealThreshold + topMargin))
    }

    /// How far sideways the target may lean. Caps the angle at roughly 31° so
    /// the gesture always reads as a pull upward rather than a swipe across.
    private static let maximumLateralLean: CGFloat = 90

    /// Where to draw the target: always exactly `revealThreshold` *above* the
    /// touch, leaning sideways toward the screen's centre line. Pulling toward
    /// the middle reads better than pulling toward a corner, and a touch
    /// already on the centre line gets a straight-up pull.
    ///
    /// The lean is horizontal only. Vertical distance is constant, which is
    /// what makes following the drawn line and pulling straight up complete at
    /// exactly the same moment — and what stops a long sideways swipe from
    /// counting for anything.
    static func target(for origin: CGPoint, in size: CGSize) -> CGPoint {
        let start = anchor(for: origin)
        let toCentre = size.width / 2 - start.x
        let lean = min(max(toCentre, -maximumLateralLean), maximumLateralLean)
        return CGPoint(x: start.x + lean, y: start.y - revealThreshold)
    }

    /// How far through the pull the user is: 0 at rest, 1 on arrival.
    ///
    /// Upward travel is the only thing that counts. Sideways movement
    /// contributes nothing — otherwise a long horizontal swipe would project
    /// onto an angled target and open the controls, which is precisely the
    /// accidental gesture this design exists to prevent.
    static func progress(for translation: CGSize, from origin: CGPoint, in size: CGSize) -> Double {
        guard revealThreshold > 0 else { return 0 }
        return min(1, max(0, Double(-translation.height / revealThreshold)))
    }

    /// Single source of truth for the commit decision, so the target filling up
    /// and the controls appearing can never disagree.
    static func isReveal(translation: CGSize, from origin: CGPoint, in size: CGSize) -> Bool {
        progress(for: translation, from: origin, in: size) >= 1
    }
}
