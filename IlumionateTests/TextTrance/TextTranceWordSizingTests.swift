//  TextTranceWordSizingTests.swift
//  IlumionateTests

import CoreGraphics
import Testing
@testable import Ilumionate

struct TextTranceWordSizingTests {

    @Test func referenceCharacterCountUsesReaderDefaultForShortScripts() {
        let words = [
            PacedWord(text: "rest", pivotIndex: 1, phase: .induction, startTime: 0, duration: 1),
            PacedWord(text: "now", pivotIndex: 1, phase: .induction, startTime: 1, duration: 1)
        ]

        #expect(TextTranceWordSizing.referenceCharacterCount(for: words) == 14)
    }

    @Test func referenceCharacterCountIgnoresRareOutlierWords() {
        var words = (0..<19).map { index in
            PacedWord(text: "gentle", pivotIndex: 2, phase: .induction, startTime: Double(index), duration: 1)
        }
        words.append(PacedWord(text: "extraordinarilywide", pivotIndex: 3, phase: .suggestions, startTime: 19, duration: 1))

        #expect(TextTranceWordSizing.referenceCharacterCount(for: words) == 14)
    }

    @Test func referenceCharacterCountExpandsWhenLongWordsAreCommon() {
        let commonLongWord = "extraordinarily"
        let words = (0..<20).map { index in
            PacedWord(text: commonLongWord, pivotIndex: 3, phase: .suggestions, startTime: Double(index), duration: 1)
        }

        #expect(TextTranceWordSizing.referenceCharacterCount(for: words) == Array(commonLongWord).count)
    }

    @Test func onlyWordsLongerThanTheReferenceShrinkThemselves() {
        let containerWidth: CGFloat = 390
        let referenceCount = 14
        let firstShortWord = TextTranceWordSizing.layout(
            for: "rest",
            pivot: 1,
            containerWidth: containerWidth,
            referenceCharacterCount: referenceCount
        )
        let secondShortWord = TextTranceWordSizing.layout(
            for: "calm",
            pivot: 1,
            containerWidth: containerWidth,
            referenceCharacterCount: referenceCount
        )
        let longerWord = TextTranceWordSizing.layout(
            for: "extraordinarilywide",
            pivot: 3,
            containerWidth: containerWidth,
            referenceCharacterCount: referenceCount
        )

        #expect(abs(firstShortWord.fontSize - secondShortWord.fontSize) < 0.0001)
        #expect(longerWord.fontSize < firstShortWord.fontSize)
    }
}
