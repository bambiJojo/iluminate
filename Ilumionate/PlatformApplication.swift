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
}
