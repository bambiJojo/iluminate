//  WordTokenizer.swift
//  Ilumionate
//
//  Splits segment text into display tokens. Punctuation is removed from the
//  displayed glyphs and promoted into control signals: a trailing-punctuation
//  PauseKind, and an authored-subliminal flag from [[ ]] marks.

import Foundation

/// Strength-ordered so pauses can be merged with `max`. Raw values are the rank.
enum PauseKind: Int, Equatable, Sendable {
    case none = 0
    case brief      // , ; :
    case medium     // em-dash
    case breath     // . ! ?
    case drift      // …
}

struct WordToken: Equatable, Sendable {
    let text: String          // display glyphs only — punctuation stripped
    let pause: PauseKind      // derived from trailing punctuation
    let isSubliminal: Bool    // authored [[ ]] mark (engine resolves the rest)
}

enum WordTokenizer {

    static func tokenize(_ text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var insideMark = false
        for piece in text.split(whereSeparator: \.isWhitespace) {
            var word = String(piece)
            let opens = word.contains("[[")
            let closes = word.contains("]]")
            word = word.replacing("[[", with: "").replacing("]]", with: "")
            let subliminal = insideMark || opens
            if opens { insideMark = true }
            if closes { insideMark = false }
            appendWord(word, subliminal: subliminal, into: &tokens)
        }
        return tokens
    }

    /// Split a whitespace piece on hyphen / em-dash into display sub-words.
    private static func appendWord(_ piece: String,
                                   subliminal: Bool,
                                   into tokens: inout [WordToken]) {
        for segment in splitOnHyphens(piece) {
            // An em-dash before this segment is a medium pause on the previous word.
            if segment.precededByEmDash { mergePauseIntoPrevious(.medium, &tokens) }

            let cleaned = stripped(segment.text)
            guard !cleaned.display.isEmpty else {
                // pure punctuation / empty: fold its pause into the previous word
                mergePauseIntoPrevious(cleaned.pause, &tokens)
                continue
            }
            tokens.append(WordToken(text: cleaned.display,
                                    pause: cleaned.pause,
                                    isSubliminal: subliminal))
        }
    }

    private struct Segment { let text: String; let precededByEmDash: Bool }

    /// Split on "-" (U+002D) and "—" (U+2014), recording whether each segment
    /// was preceded by an em-dash so the previous word can take a medium pause.
    private static func splitOnHyphens(_ piece: String) -> [Segment] {
        var segments: [Segment] = []
        var current = ""
        var precededByEmDash = false
        for ch in piece {
            if ch == "-" || ch == "\u{2014}" {
                segments.append(Segment(text: current, precededByEmDash: precededByEmDash))
                current = ""
                precededByEmDash = (ch == "\u{2014}")
            } else {
                current.append(ch)
            }
        }
        segments.append(Segment(text: current, precededByEmDash: precededByEmDash))
        return segments
    }

    private static func mergePauseIntoPrevious(_ pause: PauseKind, _ tokens: inout [WordToken]) {
        guard pause != .none, let last = tokens.last else { return }
        tokens[tokens.count - 1] = WordToken(
            text: last.text,
            pause: strongest(last.pause, pause),
            isSubliminal: last.isSubliminal)
    }

    private static let trailingMarks: [Character: PauseKind] = [
        ".": .breath, "!": .breath, "?": .breath, "…": .drift,
        ",": .brief, ";": .brief, ":": .brief
    ]
    // Removed from display but contribute no pause.
    private static let neutralTrailing: Set<Character> =
        ["\"", "'", ")", "]", "\u{201D}", "\u{2019}"]   // " ' ) ] ” ’
    private static let neutralLeading: Set<Character> =
        ["\"", "'", "(", "[", "\u{201C}", "\u{2018}"]   // " ' ( [ “ ‘

    /// Strip surrounding quotes/brackets + trailing punctuation; return the
    /// display text and the strongest trailing pause. Internal apostrophes and
    /// periods (contractions, decimals) are preserved.
    private static func stripped(_ word: String) -> (display: String, pause: PauseKind) {
        var chars = Array(word)
        while let first = chars.first, neutralLeading.contains(first) {
            chars.removeFirst()
        }
        var pause: PauseKind = .none
        while let last = chars.last {
            // literal "..." → ellipsis/drift
            if last == ".", chars.count >= 3, chars.suffix(3).allSatisfy({ $0 == "." }) {
                pause = strongest(pause, .drift)
                chars.removeLast(3)
                continue
            }
            if let kind = trailingMarks[last] {
                pause = strongest(pause, kind)
                chars.removeLast()
            } else if neutralTrailing.contains(last) {
                chars.removeLast()
            } else {
                break
            }
        }
        return (String(chars), pause)
    }

    static func strongest(_ a: PauseKind, _ b: PauseKind) -> PauseKind {
        a.rawValue >= b.rawValue ? a : b
    }
}
