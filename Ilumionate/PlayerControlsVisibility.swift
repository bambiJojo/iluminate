//
//  PlayerControlsVisibility.swift
//  Ilumionate
//
//  Observable model for Pure Void controls auto-hide. Controls fade after
//  an idle delay, but never while the drawer is open or VoiceOver is running.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class PlayerControlsVisibility {
    var isVisible: Bool = true
    var isDrawerOpen: Bool = false

    private let voiceOverActive: @MainActor () -> Bool
    private var hideTask: Task<Void, Never>?

    init(voiceOverActive: @escaping @MainActor () -> Bool = { UIAccessibility.isVoiceOverRunning }) {
        self.voiceOverActive = voiceOverActive
    }

    /// Whether auto-hide is currently allowed.
    var canAutoHide: Bool { !isDrawerOpen && !voiceOverActive() }

    /// User touched the screen: show controls and restart the idle timer.
    func registerInteraction() {
        withAnimation(LiminalMotion.fade) { isVisible = true }
        scheduleAutoHide()
    }

    /// Force-hide now (respects suppression rules).
    func hideNow() {
        guard canAutoHide else { return }
        withAnimation(LiminalMotion.fade) { isVisible = false }
    }

    /// Begin/refresh the idle countdown.
    func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LiminalMotion.controlsAutoHideDelay))
            guard let self, !Task.isCancelled else { return }
            self.hideNow()
        }
    }

    func cancel() { hideTask?.cancel() }
}
