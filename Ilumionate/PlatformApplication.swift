//
//  PlatformApplication.swift
//  Ilumionate
//
//  Shared access to application behaviors that only have UIKit equivalents.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum PlatformApplication {
    static var keepsScreenAwake: Bool {
        get {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled
            #else
            false
            #endif
        }
        set {
            #if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = newValue
            #endif
        }
    }

    static var screenBrightness: CGFloat {
        get {
            #if canImport(UIKit)
            activeScreen?.brightness ?? 1.0
            #else
            1.0
            #endif
        }
        set {
            #if canImport(UIKit)
            activeScreen?.brightness = newValue
            #endif
        }
    }

    #if canImport(UIKit)
    private static var activeScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
    }
    #endif

    /// Whether the app is in the foreground when an on-device model request is
    /// made. Game Mode refuses Foundation Models for the foreground app, so the
    /// answer decides whether moving analysis to the background can help at
    /// all — see `AIAttemptSummary`.
    @MainActor
    static var activationState: AIRunActivationState {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        switch UIApplication.shared.applicationState {
        case .active:     return .foreground
        case .background: return .background
        case .inactive:   return .inactive
        @unknown default: return .inactive
        }
        #else
        // macOS has no Game Mode gating of this kind; treat it as foreground so
        // the summary never claims a comparison it did not make.
        return .foreground
        #endif
    }
}
