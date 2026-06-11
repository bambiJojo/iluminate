//  ORPCalculator.swift
//  Ilumionate
//
//  Optimal Recognition Point: the index of the letter to align to the fixed
//  anchor and tint. Standard Spritz-style rule based on letter count.

import Foundation

enum ORPCalculator {
    /// Zero-based index of the pivot letter, computed over letters only
    /// (trailing/leading punctuation does not shift the pivot).
    static func pivotIndex(for word: String) -> Int {
        let letters = word.count { $0.isLetter || $0.isNumber }
        switch letters {
        case 0, 1: return 0
        case 2...5: return 1
        case 6...9: return 2
        default:    return 3
        }
    }
}
