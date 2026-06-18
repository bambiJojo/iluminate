//  SubliminalLexicon.swift
//  Ilumionate
//
//  Fallback suggestion-word set. Applied only when a script contains no authored
//  [[ ]] subliminal marks. Tunable.

import Foundation

enum SubliminalLexicon {
    static let words: Set<String> = [
        "deeper", "relax", "sleep", "now", "drift", "calm", "down", "heavy",
        "let", "go", "breathe", "release", "still", "sink", "deep", "rest",
        "soften", "surrender"
    ]

    static func contains(_ word: String) -> Bool {
        words.contains(word.lowercased())
    }
}
