//
//  Color+Extensions.swift
//  Ilumionate
//
//  Hex color support for the Trance Design System
//

import SwiftUI

extension Color {
    /// Initialize a Color from a hex string (e.g. "#FF0000" or "FF0000")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        let red = max(0.0, min(1.0, Double(r) / 255.0))
        let green = max(0.0, min(1.0, Double(g) / 255.0))
        let blue = max(0.0, min(1.0, Double(b) / 255.0))
        let alpha = max(0.0, min(1.0, Double(a) / 255.0))

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Converts a color temperature in Kelvin to a SwiftUI Color.
    /// Provides an accurate representation of blackbody radiation from warm amber (2000K) to cool white (6500K).
    static func fromKelvin(_ kelvin: Int) -> Color {
        let temp = Double(kelvin) / 100.0
        var red: Double, green: Double, blue: Double

        // Calculate Red
        if temp <= 66 {
            red = 255
        } else {
            red = temp - 60
            red = 329.698727446 * pow(red, -0.1332047592)
            red = max(0, min(255, red))
        }

        // Calculate Green
        if temp <= 66 {
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
            green = max(0, min(255, green))
        } else {
            green = temp - 60
            green = 288.1221695283 * pow(green, -0.0755148492)
            green = max(0, min(255, green))
        }

        // Calculate Blue
        if temp >= 66 {
            blue = 255
        } else {
            if temp <= 19 {
                blue = 0
            } else {
                blue = temp - 10
                blue = 138.5177312231 * log(blue) - 305.0447927307
                blue = max(0, min(255, blue))
            }
        }

        return Color(red: red / 255.0, green: green / 255.0, blue: blue / 255.0)
    }
}
