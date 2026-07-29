//
//  MinimalOverlayGesture.swift
//  Ilumionate
//
//  How a touch on the hidden-controls overlay is interpreted.
//
//  Extracted from the view because this decision has been wrong twice: the
//  reveal swipe was previously attached to an ancestor of a full-screen
//  Button, which silently swallowed it. Keeping the thresholds here means
//  they are pinned by tests rather than by hope.
//

import CoreGraphics

enum MinimalOverlayGesture {

    /// Upward travel required to reveal the controls, and the distance the
    /// pull target is drawn at — the affordance and the threshold are the same
    /// number so the picture never lies about the gesture.
    ///
    /// Sized for a comfortable thumb pull. Short enough to be easy, long enough
    /// that brushing the screen mid-session cannot reach it.
    static let revealThreshold: CGFloat = 72

    /// How far through the pull the user is: 0 at rest, 1 on arrival.
    /// Clamped, and downward or sideways movement contributes nothing.
    static func progress(for translation: CGSize) -> Double {
        guard revealThreshold > 0 else { return 0 }
        let pulled = -translation.height
        return min(1, max(0, Double(pulled / revealThreshold)))
    }

    /// Single source of truth for the commit decision, so the affordance
    /// filling up and the controls appearing can never disagree.
    static func isReveal(translation: CGSize) -> Bool {
        progress(for: translation) >= 1
    }
}
