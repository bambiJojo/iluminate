//
//  PlayerControlsVisibility.swift
//  Ilumionate
//
//  Observable model for Pure Void controls auto-hide. Controls fade after
//  an idle delay, but never while the drawer is open or VoiceOver is running.
//

import SwiftUI

@MainActor
@Observable
final class PlayerControlsVisibility {
    var isVisible: Bool = true

    /// Set while a sheet ("···", track list) or a bloom slider is open, which
    /// suppresses auto-hide. Closing it re-arms the idle timer: the original
    /// timer will have fired and been swallowed by the suppression guard, so
    /// without this the controls would stay on screen indefinitely.
    var isDrawerOpen: Bool = false {
        didSet {
            guard oldValue, !isDrawerOpen else { return }
            scheduleAutoHide()
        }
    }

    private let voiceOverActive: @MainActor () -> Bool
    private let autoHideDelay: Double
    private var hideTask: Task<Void, Never>?

    init(
        voiceOverActive: @escaping @MainActor () -> Bool = { PlatformAccessibility.isVoiceOverRunning },
        autoHideDelay: Double = LiminalMotion.controlsAutoHideDelay
    ) {
        self.voiceOverActive = voiceOverActive
        self.autoHideDelay = autoHideDelay
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
            try? await Task.sleep(for: .seconds(self?.autoHideDelay ?? LiminalMotion.controlsAutoHideDelay))
            guard let self, !Task.isCancelled else { return }
            self.hideNow()
        }
    }

    func cancel() { hideTask?.cancel() }
}
