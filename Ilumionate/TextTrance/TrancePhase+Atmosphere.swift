//  TrancePhase+Atmosphere.swift
//  Ilumionate
//
//  The single phase→colour table for the reader. Both the background visual and
//  the word's glow read this, so they can never drift apart.

import SwiftUI

extension TrancePhase {
    var atmosphereColor: Color {
        switch self {
        case .preTalk, .transitional:    return .phaseIntro
        case .induction:                 return .phaseInduction
        case .deepening:                 return .phaseDeepener
        case .fractionation, .confusion: return .phaseFractionation
        case .suggestions, .therapy, .eroticSuggestions, .conditioning, .brainwashing:
            return .phaseSuggestion
        case .emergence:                 return .phaseAwakening
        }
    }
}
