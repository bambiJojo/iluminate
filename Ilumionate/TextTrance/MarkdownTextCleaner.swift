//
//  MarkdownTextCleaner.swift
//  Ilumionate
//
//  Strips Markdown syntax from imported `.md` so the reader never presents a
//  syntax marker as a word. The ORP display shows one word at a time, which
//  makes a stray `##` or `**` far more visible than it would be in a page of
//  running text.
//

import Foundation

nonisolated enum MarkdownTextCleaner {

    static func plainText(from markdown: String) -> String {
        var text = markdown

        // Fenced code: drop the fence lines, keep the code as prose.
        text = replace(#"^[ \t]*```[^\n]*$"#, in: text, options: [.anchorsMatchLines])
        // Horizontal rules, before list bullets — `---` would otherwise read as
        // a bullet with no content.
        text = replace(#"^[ \t]*([-*_])[ \t]*\1[ \t]*\1[\s\S]*?$"#, in: text, options: [.anchorsMatchLines])
        // Setext heading underlines.
        text = replace(#"^[ \t]*=+[ \t]*$"#, in: text, options: [.anchorsMatchLines])
        // ATX heading markers, keeping the heading text.
        text = replace(#"^[ \t]*#{1,6}[ \t]+"#, in: text, options: [.anchorsMatchLines])
        // Blockquote markers.
        text = replace(#"^[ \t]*>[ \t]?"#, in: text, options: [.anchorsMatchLines])
        // List bullets and ordered-list numbers.
        text = replace(#"^[ \t]*[-*+][ \t]+"#, in: text, options: [.anchorsMatchLines])
        text = replace(#"^[ \t]*\d+\.[ \t]+"#, in: text, options: [.anchorsMatchLines])
        // Images before links: an image is a link with a leading `!`, and its
        // alt text is rarely worth reading aloud.
        text = replace(#"!\[[^\]]*\]\([^)]*\)"#, in: text)
        text = replace(#"\[([^\]]*)\]\([^)]*\)"#, in: text, with: "$1")
        // Emphasis. Paired markers only, so `2 * 3` survives.
        text = replace(#"\*\*([^*\n]+)\*\*"#, in: text, with: "$1")
        text = replace(#"__([^_\n]+)__"#, in: text, with: "$1")
        text = replace(#"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, in: text, with: "$1")
        text = replace(#"(?<![\w_])_([^_\n]+)_(?![\w_])"#, in: text, with: "$1")
        // Inline code.
        text = replace(#"`([^`\n]+)`"#, in: text, with: "$1")
        // Raw HTML that sometimes rides along in Markdown.
        text = replace(#"<[^>\n]+>"#, in: text)

        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func replace(
        _ pattern: String,
        in text: String,
        with replacement: String = "",
        options: NSRegularExpression.Options = []
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
}
