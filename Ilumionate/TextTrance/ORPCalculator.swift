//  ORPCalculator.swift
//  Ilumionate
//
//  Optimal Recognition Point: the index of the letter to align to the fixed
//  anchor and tint. Standard Spritz-style rule based on letter count.

import Foundation

enum ORPCalculator {
    /// Zero-based display-character index of the pivot letter. The pivot choice
    /// is computed over letters/numbers only, then mapped back into the rendered
    /// word so apostrophes or other preserved punctuation are never highlighted.
    static func pivotIndex(for word: String) -> Int {
        let characters = Array(word)
        let wordCharacterIndexes = characters.indices.filter { index in
            let character = characters[index]
            return character.isLetter || character.isNumber
        }
        let targetLetterIndex: Int
        switch wordCharacterIndexes.count {
        case 0, 1: return 0
        case 2...5: targetLetterIndex = 1
        case 6...9: targetLetterIndex = 2
        default:    targetLetterIndex = 3
        }
        return wordCharacterIndexes[min(targetLetterIndex, wordCharacterIndexes.count - 1)]
    }
}
