//
//  SwipeRevealHint.swift
//  Ilumionate
//
//  Decides whether the player still shows "Swipe up to show controls".
//  The hint teaches a gesture; once someone has used it, it is just clutter
//  over the session, so it retires for good after the first reveal.
//

import Foundation

struct SwipeRevealHint {
    /// Successful reveals after which the hint stops appearing.
    static let retireAfterReveals = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isVisible: Bool {
        revealCount < Self.retireAfterReveals
    }

    /// Call when a swipe or pull actually revealed the controls.
    func recordReveal() {
        guard isVisible else { return }
        defaults.set(revealCount + 1, forKey: AppSettingsManager.Key.swipeRevealCount)
    }

    private var revealCount: Int {
        defaults.integer(forKey: AppSettingsManager.Key.swipeRevealCount)
    }
}
