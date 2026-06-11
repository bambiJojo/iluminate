//  WordTokenizer.swift
//  Ilumionate
//
//  Splits segment text into display tokens, flagging sentence-ending words so
//  the pacing engine can insert a hold pause (the hypnotic "breathing room").

import Foundation

struct WordToken: Equatable, Sendable {
    let text: String
    let endsSentence: Bool
}

enum WordTokenizer {
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]

    static func tokenize(_ text: String) -> [WordToken] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map { raw in
                let word = String(raw)
                let ends = word.last.map { sentenceEnders.contains($0) } ?? false
                return WordToken(text: word, endsSentence: ends)
            }
    }
}
