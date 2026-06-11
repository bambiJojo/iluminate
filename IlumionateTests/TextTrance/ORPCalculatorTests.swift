//  ORPCalculatorTests.swift
//  IlumionateTests

import Testing
@testable import Ilumionate

struct ORPCalculatorTests {

    @Test("Pivot index follows the standard ORP rule",
          arguments: [
            ("a", 0),        // 1 letter -> 1st
            ("to", 1),       // 2-5 -> 2nd
            ("rest", 1),     // 2-5 -> 2nd
            ("softly", 2),   // 6-9 -> 3rd
            ("downward", 2), // 6-9 -> 3rd (8 letters)
            ("consciously", 3) // 10+ -> 4th
          ])
    func pivotIndex(word: String, expected: Int) {
        #expect(ORPCalculator.pivotIndex(for: word) == expected)
    }

    @Test func emptyWordIsZero() {
        #expect(ORPCalculator.pivotIndex(for: "") == 0)
    }

    @Test func pivotIgnoresTrailingPunctuationForLength() {
        // "deeper." has 6 letters + 1 punctuation; pivot computed on letters only.
        #expect(ORPCalculator.pivotIndex(for: "deeper.") == 2)
    }
}
