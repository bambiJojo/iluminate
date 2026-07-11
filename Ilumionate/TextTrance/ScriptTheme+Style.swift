//  ScriptTheme+Style.swift
//  Ilumionate
//
//  Shared visual treatment for Reader script themes.

import SwiftUI

extension ScriptTheme {
    var symbol: String {
        switch self {
        case .relaxation: return "wind"
        case .sleep:      return "moon.zzz"
        case .focus:      return "scope"
        case .suggestion: return "sparkles"
        }
    }

    var accent: Color {
        switch self {
        case .relaxation: return .auroraTeal
        case .sleep:      return .bwDelta
        case .focus:      return .bwBeta
        case .suggestion: return .auroraPink
        }
    }
}
