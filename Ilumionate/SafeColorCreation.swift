//
//  SafeColorCreation.swift
//  Ilumionate
//
//  Safe color creation with crash logging
//

import SwiftUI
import Foundation

/// Safe color creation utilities with crash logging
struct SafeColor {

    /// Safely create a Color with RGB values and opacity, with comprehensive logging
    static func rgb(_ red: Double, _ green: Double, _ blue: Double, opacity: Double = 1.0, context: String = "unknown") -> Color {

        // Log the creation attempt
        let colorInfo = "RGB(\(red), \(green), \(blue)) opacity(\(opacity))"
        OrbCrashLogger.shared.logColorCreation(colorInfo, context: context)

        // Validate input ranges
        let clampedRed = max(0.0, min(1.0, red))
        let clampedGreen = max(0.0, min(1.0, green))
        let clampedBlue = max(0.0, min(1.0, blue))
        let clampedOpacity = max(0.0, min(1.0, opacity))

        // Log if clamping was needed
        if red != clampedRed || green != clampedGreen || blue != clampedBlue || opacity != clampedOpacity {
            let warning = "Clamped values: R(\(red)→\(clampedRed)) G(\(green)→\(clampedGreen)) B(\(blue)→\(clampedBlue)) O(\(opacity)→\(clampedOpacity))"
            OrbCrashLogger.shared.logPotentialCrash("Color value out of range", context: "\(context): \(warning)")
        }

        // Create the base color
        let baseColor = Color(red: clampedRed, green: clampedGreen, blue: clampedBlue)

        // Apply opacity if needed
        if clampedOpacity < 1.0 {
            return baseColor.opacity(clampedOpacity)
        } else {
            return baseColor
        }
    }

    /// Safely create a RadialGradient with logging
    static func radialGradient(
        colors: [Color],
        center: UnitPoint = .center,
        startRadius: CGFloat = 0,
        endRadius: CGFloat = 100,
        context: String = "unknown"
    ) -> RadialGradient {

        OrbCrashLogger.shared.logGradientCreation("RadialGradient", colorCount: colors.count, context: context)

        // Validate parameters
        if colors.isEmpty {
            OrbCrashLogger.shared.logPotentialCrash("Empty color array for RadialGradient", context: context)
            return RadialGradient(colors: [Color.clear], center: center, startRadius: startRadius, endRadius: endRadius)
        }

        if startRadius < 0 || endRadius < 0 {
            let warning = "Negative radius values: start(\(startRadius)) end(\(endRadius))"
            OrbCrashLogger.shared.logPotentialCrash("Invalid RadialGradient radii", context: "\(context): \(warning)")
        }

        return RadialGradient(
            colors: colors,
            center: center,
            startRadius: max(0, startRadius),
            endRadius: max(0, endRadius)
        )
    }

    /// Safely create a LinearGradient with logging
    static func linearGradient(
        colors: [Color],
        startPoint: UnitPoint = .topLeading,
        endPoint: UnitPoint = .bottomTrailing,
        context: String = "unknown"
    ) -> LinearGradient {

        OrbCrashLogger.shared.logGradientCreation("LinearGradient", colorCount: colors.count, context: context)

        if colors.isEmpty {
            OrbCrashLogger.shared.logPotentialCrash("Empty color array for LinearGradient", context: context)
            return LinearGradient(colors: [Color.clear], startPoint: startPoint, endPoint: endPoint)
        }

        return LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }
}

