//  ReaderSectionIndex.swift
//  Ilumionate
//
//  Builds a lightweight table of contents for reader playback. The index uses
//  authored headings when imported text exposes them, then falls back to script
//  segment boundaries for bundled phase-structured scripts.

import Foundation

struct ReaderSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let wordIndex: Int
}

enum ReaderSectionIndex {
    static func sections(for script: TranceScript, arc: ScriptArc) -> [ReaderSection] {
        var playableSegments: [(segment: TranceScriptSegment, index: Int, wordIndex: Int, wordCount: Int)] = []
        var headingSections: [ReaderSection] = []
        var wordOffset = 0

        for (segmentIndex, segment) in script.segments.enumerated() {
            guard segmentPlays(segment, in: arc) else { continue }

            let tokens = WordTokenizer.tokenize(segment.text)
            if tokens.isEmpty == false {
                playableSegments.append((segment, segmentIndex, wordOffset, tokens.count))
                headingSections.append(contentsOf: detectedHeadings(
                    in: segment.text,
                    segmentIndex: segmentIndex,
                    baseWordIndex: wordOffset
                ))
            }
            wordOffset += tokens.count

            if arc == .handoff, segment.triggersHandoff == true { break }
        }

        let explicitSections = normalized(headingSections)
        if explicitSections.isEmpty == false {
            if let first = explicitSections.first, first.wordIndex > 0 {
                return [ReaderSection(id: "beginning-0", title: "Beginning", wordIndex: 0)]
                    + explicitSections
            }
            return explicitSections
        }

        return fallbackSections(from: playableSegments)
    }

    private static func detectedHeadings(in text: String,
                                         segmentIndex: Int,
                                         baseWordIndex: Int) -> [ReaderSection] {
        var sections: [ReaderSection] = []
        var lineWordOffset = 0

        for (lineIndex, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = displayTitle(rawLine)
            let wordCount = WordTokenizer.tokenize(line).count
            defer { lineWordOffset += wordCount }

            guard isHeading(line, wordCount: wordCount) else { continue }
            let wordIndex = baseWordIndex + lineWordOffset
            sections.append(ReaderSection(
                id: "heading-\(segmentIndex)-\(lineIndex)-\(wordIndex)",
                title: line,
                wordIndex: wordIndex
            ))
        }

        return sections
    }

    private static func fallbackSections(
        from playableSegments: [(segment: TranceScriptSegment, index: Int, wordIndex: Int, wordCount: Int)]
    ) -> [ReaderSection] {
        guard playableSegments.count > 1 else { return [] }

        var phaseCounts: [TrancePhase: Int] = [:]
        for item in playableSegments {
            phaseCounts[item.segment.phase, default: 0] += 1
        }

        var seenPhaseCounts: [TrancePhase: Int] = [:]
        return playableSegments.enumerated().map { ordinal, item in
            let phase = item.segment.phase
            seenPhaseCounts[phase, default: 0] += 1
            let title = phaseCounts[phase, default: 0] > 1
                ? "\(phase.displayName) \(seenPhaseCounts[phase, default: 0])"
                : phase.displayName
            return ReaderSection(
                id: "segment-\(item.index)-\(item.wordIndex)-\(ordinal)",
                title: title,
                wordIndex: item.wordIndex
            )
        }
    }

    private static func normalized(_ sections: [ReaderSection]) -> [ReaderSection] {
        var seenWordIndexes: Set<Int> = []
        return sections
            .sorted { $0.wordIndex < $1.wordIndex }
            .filter { section in
                guard seenWordIndexes.contains(section.wordIndex) == false else { return false }
                seenWordIndexes.insert(section.wordIndex)
                return true
            }
    }

    private static func segmentPlays(_ segment: TranceScriptSegment, in arc: ScriptArc) -> Bool {
        guard let arcs = segment.arcs else { return true }
        return arcs.contains(arc)
    }

    private static func isHeading(_ line: String, wordCount: Int) -> Bool {
        guard wordCount > 0,
              wordCount <= 12,
              line.count <= 100,
              containsLetter(line),
              line.range(of: #"https?://"#, options: [.regularExpression, .caseInsensitive]) == nil
        else { return false }

        if matches(#"^\s*(chapter|chap\.?|section|part|book|volume|vol\.?|act)\b"#, in: line) {
            return true
        }

        if matches(#"^\s*(prologue|epilogue|foreword|preface|introduction|afterword|acknowledgments|acknowledgements)(\s*[:\-].*)?\s*$"#, in: line) {
            return true
        }

        if matches(#"^\s*\d{1,3}(\s*[\.)])?(\s+.+)?\s*$"#, in: line) {
            return true
        }

        if isRomanNumeral(line)
            || matches(#"^\s*[IVXLCDM]{1,8}\s*[\.)](\s+.+)?\s*$"#, in: line)
            || matches(#"^\s*[IVXLCDM]{1,8}\s*[-:]\s*.+\s*$"#, in: line) {
            return true
        }

        return isAllCapsHeading(line, wordCount: wordCount)
    }

    private static func isAllCapsHeading(_ line: String, wordCount: Int) -> Bool {
        guard wordCount <= 8,
              line.range(of: #"[.!?]$"#, options: .regularExpression) == nil
        else { return false }

        let letterScalars = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letterScalars.count >= 2 else { return false }
        return letterScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
    }

    private static func isRomanNumeral(_ line: String) -> Bool {
        let stripped = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".:)"))
            .uppercased()
        guard stripped.isEmpty == false else { return false }

        let roman = CharacterSet(charactersIn: "IVXLCDM")
        return stripped.unicodeScalars.allSatisfy { roman.contains($0) }
    }

    private static func containsLetter(_ line: String) -> Bool {
        line.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private static func matches(_ pattern: String, in line: String) -> Bool {
        line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func displayTitle(_ rawLine: String) -> String {
        rawLine
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
