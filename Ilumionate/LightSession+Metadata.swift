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
    /// session's primary entrainment target rather than the highest peak).
    var dominantFrequency: Double {
        let sorted = light_score.map(\.frequency).sorted()
        guard !sorted.isEmpty else { return 10.0 }
        return sorted[sorted.count / 2]
    }

    // MARK: - Brainwave Category

    var brainwaveCategory: BrainwaveCategory {
        switch dominantFrequency {
        case 0.5..<4:  return .sleep
        case 4..<8:    return .relax
        case 8..<14:   return .focus
        default:       return .trance
        }
    }

    // MARK: - Tagline

    var tagline: String {
        let name = displayName.lowercased()
        if name.contains("peniston")    { return "Alpha-Theta Protocol" }
        if name.contains("schumann")    { return "7.83 Hz Earth Resonance" }
        if name.contains("gamma")       { return "40 Hz Neural Clarity" }
        if name.contains("smr")         { return "Sleep Architecture" }
        if name.contains("anxiety")     { return "Beta to Theta Descent" }
        if name.contains("hypnagogic")  { return "Waking Dream State" }
        if name.contains("defrag")      { return "Beta Cycling Protocol" }
        if name.contains("bilateral")   { return "EMDR-Inspired" }
        if name.contains("delta")       { return "Deep Recovery" }
        if name.contains("creativity")  { return "Divergent Thinking" }
        if name.contains("sunrise")     { return "Circadian Awakening" }
        if name.contains("hypnosis")    { return "Elman Induction Arc" }
        if name.contains("relax")       { return "Theta Descent" }
        if name.contains("focus")       { return "Alpha-Beta Clarity" }
        if name.contains("restoration") { return "Slow-Wave Recovery" }
        if name.contains("threshold")   { return "Hypnagogic State" }
        return brainwaveCategory.rawValue + " Entrainment"
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
