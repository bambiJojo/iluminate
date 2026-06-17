//  TextTranceWordSizing.swift
//  Ilumionate

import CoreGraphics

struct TextTranceWordLayout: Equatable {
    let fontSize: CGFloat
    let anchorOffset: CGFloat
    let safePivot: Int
}

enum TextTranceWordSizing {
    static let defaultReferenceCharacterCount = 14
    static let horizontalSafetyMargin: CGFloat = 24
    static let maximumFontSize: CGFloat = 96
    static let absoluteMinimumFontSize: CGFloat = 6

    private static let likelyLongestPercentile = 0.95
    private static let monospacedCharacterWidthRatio: CGFloat = 0.6

    static func referenceCharacterCount(for words: [PacedWord]) -> Int {
        let counts = words
            .map { displayCharacterCount($0.text) }
            .sorted()
        guard !counts.isEmpty else { return defaultReferenceCharacterCount }

        let percentileIndex = Int((Double(counts.count - 1) * likelyLongestPercentile).rounded(.down))
        return max(defaultReferenceCharacterCount, counts[percentileIndex])
    }

    static func layout(for word: String,
                       pivot: Int,
                       containerWidth: CGFloat,
                       referenceCharacterCount: Int) -> TextTranceWordLayout {
        let characterCount = displayCharacterCount(word)
        let safePivot = safePivot(pivot, characterCount: characterCount)
        let referenceCount = max(defaultReferenceCharacterCount, referenceCharacterCount)
        let referencePivot = likelyPivot(forCharacterCount: referenceCount)
        let baseFontSize = fittingFontSize(
            characterCount: referenceCount,
            pivot: referencePivot,
            containerWidth: containerWidth
        )
        let wordFitFontSize = fittingFontSize(
            characterCount: characterCount,
            pivot: safePivot,
            containerWidth: containerWidth
        )
        let fontSize = max(
            absoluteMinimumFontSize,
            min(maximumFontSize, baseFontSize, wordFitFontSize)
        )
        let charWidth = fontSize * monospacedCharacterWidthRatio
        let wordCenter = CGFloat(max(characterCount - 1, 0)) / 2
        let anchorOffset = (wordCenter - CGFloat(safePivot)) * charWidth
        return TextTranceWordLayout(
            fontSize: fontSize,
            anchorOffset: anchorOffset,
            safePivot: safePivot
        )
    }

    private static func displayCharacterCount(_ word: String) -> Int {
        Array(word).count
    }

    private static func safePivot(_ pivot: Int, characterCount: Int) -> Int {
        guard characterCount > 0 else { return 0 }
        return min(max(pivot, 0), characterCount - 1)
    }

    private static func likelyPivot(forCharacterCount characterCount: Int) -> Int {
        switch characterCount {
        case ...1: return 0
        case 2...5: return 1
        case 6...9: return 2
        default: return 3
        }
    }

    private static func fittingFontSize(characterCount: Int,
                                        pivot: Int,
                                        containerWidth: CGFloat) -> CGFloat {
        guard characterCount > 0, containerWidth > horizontalSafetyMargin * 2 else {
            return maximumFontSize
        }
        let safePivot = safePivot(pivot, characterCount: characterCount)
        let availableHalfWidth = (containerWidth - horizontalSafetyMargin * 2) / 2
        let leftCharacters = CGFloat(safePivot) + 0.5
        let rightCharacters = CGFloat(characterCount - safePivot) - 0.5
        let limitingCharacters = max(leftCharacters, rightCharacters, 1)
        return availableHalfWidth / limitingCharacters / monospacedCharacterWidthRatio
    }
}
