//
//  PlatformAccessibility.swift
//  Ilumionate
//
//  Small cross-platform bridge for accessibility preferences used outside
//  SwiftUI's environment.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
enum PlatformAccessibility {
    static var isReduceMotionEnabled: Bool {
        #if canImport(UIKit)
        UIAccessibility.isReduceMotionEnabled
        #elseif canImport(AppKit)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        false
        #endif
    }

    static var isVoiceOverRunning: Bool {
        #if canImport(UIKit)
        UIAccessibility.isVoiceOverRunning
        #elseif canImport(AppKit)
        NSWorkspace.shared.isVoiceOverEnabled
        #else
        false
        #endif
    }
}
