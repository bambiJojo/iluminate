//
//  ThemeMode.swift
//  Ilumionate
//
//  App-wide appearance selection persisted under the existing
//  AppSettingsManager.Key.appearanceMode UserDefaults key.
//

import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// Tolerant of legacy/unknown persisted strings.
    init(persisted: String?) {
        self = persisted.flatMap(ThemeMode.init(rawValue:)) ?? .system
    }

    var displayName: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil means "follow the device setting".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
