//
//  LightSession+Metadata.swift
//  Ilumionate
//
//  Derived display metadata for LightSession — category, tagline, icon, and
//  gradient colors used by featured and compact session cards.
//

import SwiftUI

extension LightSession {

    // MARK: - Frequency Analysis

    /// Median frequency across all light-score moments (representative of the
    /// session's primary light-pattern rate rather than the highest peak).
    var dominantFrequency: Double {
        let sorted = light_score.map { LightSafety.clampFlashHz($0.frequency) }.sorted()
        guard !sorted.isEmpty else { return LightSafety.maxFlashHz }
        return sorted[sorted.count / 2]
    }

    // MARK: - Pattern Category

    var brainwaveCategory: BrainwaveCategory {
        switch dominantFrequency {
        case 0.5..<1.0: return .sleep
        case 1.0..<1.5: return .relax
        case 1.5..<2.0: return .focus
        case 2.0..<2.5: return .energy
        default:        return .trance
        }
    }

    // MARK: - Tagline

    var tagline: String {
        let name = displayName.lowercased()
        if name.contains("peniston")    { return "Alpha–Theta Frequency Arc" }
        if name.contains("schumann")    { return "7.83 Hz Pulse Pattern" }
        if name.contains("gamma")       { return "Fast Pulse Pattern" }
        if name.contains("smr")         { return "Layered Pulse Pattern" }
        if name.contains("anxiety")     { return "Descending Frequency Arc" }
        if name.contains("hypnagogic")  { return "Slow Frequency Descent" }
        if name.contains("defrag")      { return "Cycling Frequency Pattern" }
        if name.contains("bilateral")   { return "Alternating Left–Right Pattern" }
        if name.contains("delta")       { return "Low-Frequency Pattern" }
        if name.contains("creativity")  { return "Variable Frequency Arc" }
        if name.contains("sunrise")     { return "Rising Frequency Arc" }
        if name.contains("hypnosis")    { return "Audio-Synchronized Hypnosis Arc" }
        if name.contains("relax")       { return "Slow Frequency Descent" }
        if name.contains("focus")       { return "Midrange Frequency Pattern" }
        if name.contains("restoration") { return "Low-Frequency Pattern" }
        if name.contains("threshold")   { return "Slow Frequency Descent" }
        return brainwaveCategory.rawValue + " Frequency Pattern"
    }

    // MARK: - Icon

    var categoryIcon: String {
        switch brainwaveCategory {
        case .sleep:  return "moon.stars.fill"
        case .relax:  return "leaf.fill"
        case .focus:  return "target"
        case .energy: return "bolt.fill"
        case .trance: return "sparkles"
        }
    }

    // MARK: - Gradient Colors

    var gradientColors: [Color] {
        switch brainwaveCategory {
        case .sleep:  return [.bwDelta, .bwTheta]
        case .relax:  return [.bwTheta, .lavender]
        case .focus:  return [.bwAlpha, .roseDeep]
        case .energy: return [.bwBeta, .warmAccent]
        case .trance: return [.roseGold, .bwGamma]
        }
    }

    // MARK: - Accent Color

    var accentColor: Color {
        switch brainwaveCategory {
        case .sleep:  return .bwDelta
        case .relax:  return .bwTheta
        case .focus:  return .bwAlpha
        case .energy: return .bwBeta
        case .trance: return .roseGold
        }
    }
}
