//  ReadableWebTextExtractor.swift
//  Ilumionate
//
//  Converts user-approved webpage HTML into plain reader text before it can
//  become a Text Trance script segment. This is intentionally fetch-free:
//  source eligibility, terms review, and persistence stay outside this type.

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ReadableWebTextExtractionError: LocalizedError, Equatable {
    case noReadableText

    var errorDescription: String? {
        switch self {
        case .noReadableText:
            return "No readable article text was found."
        }
    }
}

enum ReadableWebTextExtractor {
    private static let minimumWordCount = 8

    static func extract(fromHTML html: String) throws -> String {
        let cleanedHTML = removeNonReaderBlocks(from: html)
        let fragment = bestReadableFragment(in: cleanedHTML)
            ?? bodyFragment(in: cleanedHTML)
            ?? cleanedHTML
        let text = normalize(plainText(fromHTMLFragment: truncateHTMLAtBoilerplate(fragment)))

        guard wordCount(in: text) >= minimumWordCount else {
            throw ReadableWebTextExtractionError.noReadableText
        }
        return text
    }

    static func normalizePlainText(_ text: String) throws -> String {
        let normalized = normalize(text)
        guard wordCount(in: normalized) >= minimumWordCount else {
            throw ReadableWebTextExtractionError.noReadableText
        }
        return normalized
    }

    static func title(fromHTML html: String) -> String? {
        guard let titleHTML = firstCapture(
            matching: #"<title\b[^>]*>([\s\S]*?)</title>"#,
            in: html
        ) else {
            return nil
        }

        let title = normalize(plainText(fromHTMLFragment: titleHTML))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func removeNonReaderBlocks(from html: String) -> String {
        var result = replacing(pattern: #"<!--[\s\S]*?-->"#, in: html)
        result = replacing(
            pattern: #"<\s*(script|style|noscript|svg|canvas|iframe|form|button|select|textarea|nav|header|footer|aside|menu|dialog)\b[^>]*>[\s\S]*?<\s*/\s*\1\s*>"#,
            in: result
        )
        result = replacing(
            pattern: #"<\s*(meta|link|base|input|img|source|picture|video|audio|embed|object)\b[^>]*>"#,
            in: result
        )

        let chromeTerms = #"advert(?:isement|ising)?|(?<![a-z0-9])ads?(?![a-z0-9])|ad[-_ ]?(?:container|banner|slot|unit)|advanced[-_ ]?ads|awac|banner|cookie|consent|modal|newsletter|subscribe|share|social|sidebar|related|recommend|comments?|comment[-_ ]?(?:form|reply)|reply|respond|promo|sponsor|breadcrumb|pagination|nav|menu|widget"#
        // Never treat the document's structural containers as chrome: theme
        // classes routinely tack chrome-ish tokens (e.g. "has-sidebar") onto
        // <body>/<html>, and the lazy backreference match would then delete the
        // entire page body along with the article.
        let chromeAttributePattern =
            #"<(?!(?:body|html)\b)([a-z][a-z0-9]*)\b(?=[^>]*(?:class|id|role|aria-label)\s*=\s*["'][^"']*(?:"# +
            chromeTerms +
            #")[^"']*["'])[^>]*>[\s\S]*?<\s*/\s*\1\s*>"#

        // A few passes handle simple nested chrome such as an ad inside a modal.
        for _ in 0..<3 {
            let next = replacing(pattern: chromeAttributePattern, in: result)
            if next == result { break }
            result = next
        }
        return result
    }

    private static func bestReadableFragment(in html: String) -> String? {
        let candidateGroups: [(pattern: String, specificity: Int)] = [
            (
                #"<([a-z][a-z0-9]*)\b(?=[^>]*(?:role|itemprop|class|id)\s*=\s*["'][^"']*(?:articlebody|article-body|article_content|article-text|entry-content|single-content|post-content|post_content|post-body|story-body|story_content|chapter|readable|script-content|main-content|body-content)[^"']*["'])[^>]*>[\s\S]*?<\s*/\s*\1\s*>"#,
                260
            ),
            (#"<article\b[^>]*>[\s\S]*?</article>"#, 190),
            (#"<main\b[^>]*>[\s\S]*?</main>"#, 70),
            (
                #"<([a-z][a-z0-9]*)\b(?=[^>]*(?:role|class|id)\s*=\s*["'][^"']*(?:main|content-area|site-main|content-wrap)[^"']*["'])[^>]*>[\s\S]*?<\s*/\s*\1\s*>"#,
                45
            )
        ]

        let scoredCandidates = candidateGroups.flatMap { group in
            fragments(matching: group.pattern, in: html).compactMap { fragment -> (html: String, score: Int)? in
                let score = readableScore(for: fragment, specificity: group.specificity)
                guard score > Int.min else { return nil }
                return (fragment, score)
            }
        }

        return scoredCandidates.max { lhs, rhs in
            lhs.score < rhs.score
        }?.html
    }

    private static func bodyFragment(in html: String) -> String? {
        fragments(matching: #"<body\b[^>]*>[\s\S]*?</body>"#, in: html).first
    }

    private static func plainText(fromHTMLFragment html: String) -> String {
        var result = html
        result = replacing(
            pattern: #"<([a-z][a-z0-9]*)\b(?=[^>]*(?:hidden|aria-hidden\s*=\s*["']true["']|style\s*=\s*["'][^"']*display\s*:\s*none))[^>]*>[\s\S]*?<\s*/\s*\1\s*>"#,
            in: result
        )
        result = replacing(pattern: #"<\s*br\s*/?\s*>"#, in: result, with: "\n")
        result = replacing(
            pattern: #"</\s*(p|div|li|h[1-6]|section|article|main|blockquote|tr|td|pre)\s*>"#,
            in: result,
            with: "\n"
        )
        result = replacing(pattern: #"<[^>]+>"#, in: result)
        return decodeHTMLEntities(result)
    }

    private static func truncateHTMLAtBoilerplate(_ html: String) -> String {
        let markers = [
            "Return to Free Hypnosis Scripts",
            "Search For Hypnosis",
            "Could you help us",
            "Did we help you",
            "Leave a Reply",
            "Recent Comments"
        ]

        let lowercased = html.lowercased()
        let markerIndexes = markers.compactMap { marker -> String.Index? in
            lowercased.range(of: marker.lowercased())?.lowerBound
        }

        guard let firstIndex = markerIndexes.min() else {
            return html
        }
        return String(html[..<firstIndex])
    }

    private static func normalize(_ text: String) -> String {
        let spaced = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        let lines = truncateAtBoilerplate(
            spaced
            .components(separatedBy: .newlines)
            .map { collapseSpaces(in: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !isChromeLine($0) }
        )

        return lines.joined(separator: "\n\n")
    }

    private static func truncateAtBoilerplate(_ lines: [String]) -> [String] {
        let markers = [
            "return to free hypnosis scripts",
            "search for hypnosis",
            "could you help us",
            "did we help you",
            "leave a reply",
            "recent comments",
            "your email address will not be published",
            "comment *",
            "name *",
            "email *",
            "save my name",
            "disclaimer:"
        ]

        guard let markerIndex = lines.firstIndex(where: { line in
            let folded = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            return markers.contains { folded.contains($0) }
        }) else {
            return lines
        }
        return Array(lines.prefix(markerIndex))
    }

    private static func isChromeLine(_ line: String) -> Bool {
        let folded = line.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let shortChromeTerms = [
            "home", "menu", "search", "login", "log in", "sign in", "sign up",
            "subscribe", "newsletter", "share", "advertisement", "privacy",
            "terms", "cookie", "cookies", "accept", "skip to content"
        ]

        if shortChromeTerms.contains(folded) { return true }
        guard wordCount(in: folded) <= 5 else { return false }
        return shortChromeTerms.contains { folded.contains($0) }
    }

    private static func readableScore(for html: String, specificity: Int) -> Int {
        let truncatedHTML = truncateHTMLAtBoilerplate(html)
        let text = normalize(plainText(fromHTMLFragment: truncatedHTML))
        let words = wordCount(in: text)
        guard words >= minimumWordCount else { return Int.min }

        let paragraphCount = fragments(
            matching: #"<\s*(p|blockquote|li|pre)\b[^>]*>"#,
            in: truncatedHTML
        ).count
        let linkCount = fragments(
            matching: #"<\s*a\b[^>]*>[\s\S]*?<\s*/\s*a\s*>"#,
            in: truncatedHTML
        ).count
        let formControlCount = fragments(
            matching: #"<\s*(input|textarea|select|button|form)\b"#,
            in: truncatedHTML
        ).count
        let boilerplatePenalty = boilerplateMarkerCount(in: truncatedHTML) * 45
        let headingOnlyPenalty = looksLikeHeadingOnly(text) ? 500 : 0

        return words
            + specificity
            + min(paragraphCount, 12) * 12
            - linkCount * 8
            - formControlCount * 30
            - boilerplatePenalty
            - headingOnlyPenalty
    }

    private static func boilerplateMarkerCount(in html: String) -> Int {
        let folded = html.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let markers = [
            "leave a reply",
            "recent comments",
            "comment-form",
            "search for hypnosis",
            "make money online",
            "advertisement",
            "newsletter",
            "subscribe"
        ]
        return markers.reduce(0) { total, marker in
            folded.contains(marker) ? total + 1 : total
        }
    }

    private static func looksLikeHeadingOnly(_ text: String) -> Bool {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count <= 2 else { return false }
        return wordCount(in: text) < 20
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        #if canImport(UIKit) || canImport(AppKit)
        guard let data = text.data(using: .utf8) else { return text }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) {
            return attributed.string
        }
        #endif
        return text
    }

    private static func collapseSpaces(in text: String) -> String {
        replacing(pattern: #"[ \t\f\v]+"#, in: text, with: " ", options: [])
    }

    private static func wordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }

    private static func replacing(
        pattern: String,
        in text: String,
        with replacement: String = "",
        options: NSRegularExpression.Options = [.caseInsensitive, .dotMatchesLineSeparators]
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }

    private static func fragments(matching pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private static func firstCapture(matching pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let matchRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[matchRange])
    }
}
