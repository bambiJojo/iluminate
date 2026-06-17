//
//  ScriptCorpusExtractor.swift
//  CorpusGenKit
//
//  Dev-time importer for raw script books. It extracts atomic phase examples
//  from noisy RTF/text exports, preserving provenance while keeping page noise,
//  bylines, and stage directions out of model-facing text.
//

import CryptoKit
import Foundation
import CorpusKit

#if canImport(AppKit)
import AppKit
#endif

public enum ScriptCorpusExtractionFlag: String, Codable, Hashable, Sendable {
    case stageDirectionsRemoved
    case lowWordCount
    case mixedInstructionalText
    case needsReview
}

public struct ExtractedScriptBlock: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let phase: TrancePhase
    public let title: String
    public let sourceFilename: String
    public let sourcePath: String
    public let pageRange: ClosedRange<Int>?
    public let spokenText: String
    public let stageDirections: [String]
    public let wordCount: Int
    public let qualityFlags: Set<ScriptCorpusExtractionFlag>
}

public struct ScriptCorpusExtractionIssue: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let sourcePath: String
    public let message: String
}

public struct ScriptCorpusExtractionReport: Codable, Sendable {
    public let blocks: [ExtractedScriptBlock]
    public let issues: [ScriptCorpusExtractionIssue]
}

public enum ScriptCorpusExtractor {
    public static func extract(
        from directory: URL,
        fileManager: FileManager = .default
    ) -> ScriptCorpusExtractionReport {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]
        ) else {
            return ScriptCorpusExtractionReport(
                blocks: [],
                issues: [issue(sourcePath: directory.lastPathComponent, message: "Could not enumerate directory.")]
            )
        }

        var blocks: [ExtractedScriptBlock] = []
        var issues: [ScriptCorpusExtractionIssue] = []

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]),
                  values.isDirectory != true,
                  supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }

            let relativePath = displayPath(for: url, relativeTo: directory)
            do {
                let report = try extract(from: url, sourcePath: relativePath)
                blocks.append(contentsOf: report.blocks)
                issues.append(contentsOf: report.issues)
            } catch {
                issues.append(issue(sourcePath: relativePath, message: error.localizedDescription))
            }
        }

        return ScriptCorpusExtractionReport(
            blocks: blocks.sorted {
                if $0.phase.rawValue == $1.phase.rawValue {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return phaseSortIndex($0.phase) < phaseSortIndex($1.phase)
            },
            issues: issues
        )
    }

    public static func extract(from url: URL, sourcePath: String? = nil) throws -> ScriptCorpusExtractionReport {
        let text = try plainText(from: url)
        let sourcePath = sourcePath ?? url.lastPathComponent
        return extract(
            text: text,
            sourceFilename: url.lastPathComponent,
            sourcePath: sourcePath,
            fallbackPhase: inferredPhase(forPath: sourcePath)
        )
    }

    public static func extract(
        text: String,
        sourceFilename: String,
        sourcePath: String,
        fallbackPhase: TrancePhase?
    ) -> ScriptCorpusExtractionReport {
        let normalizedLines = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let annotated = annotate(lines: normalizedLines)
        let ranges = blockRanges(in: annotated)
        var blocks: [ExtractedScriptBlock] = []
        var issues: [ScriptCorpusExtractionIssue] = []

        for range in ranges {
            let title = titleText(from: annotated[range.titleIndex].text, nextLine: nextContentLine(after: range.titleIndex, in: annotated))
            guard title.isEmpty == false else { continue }

            let bodyLines = annotated[range.bodyRange].map(\.text)
            let cleanup = cleanedSpokenText(from: bodyLines)
            let phase = phaseFor(title: title, sourcePath: sourcePath, fallback: fallbackPhase)
            let wordCount = tokens(in: cleanup.spokenText).count

            guard cleanup.spokenText.isEmpty == false else {
                issues.append(issue(sourcePath: sourcePath, message: "Skipped '\(title)' because no spoken text remained after cleanup."))
                continue
            }

            var flags = cleanup.flags
            if wordCount < 40 { flags.insert(.lowWordCount) }
            if shouldReview(title: title, sourcePath: sourcePath, body: cleanup.spokenText) {
                flags.insert(.needsReview)
            }

            blocks.append(
                ExtractedScriptBlock(
                    id: deterministicID(sourcePath: sourcePath, title: title, phase: phase, text: cleanup.spokenText),
                    phase: phase,
                    title: title,
                    sourceFilename: sourceFilename,
                    sourcePath: sourcePath,
                    pageRange: pageRange(for: range, in: annotated),
                    spokenText: cleanup.spokenText,
                    stageDirections: cleanup.stageDirections,
                    wordCount: wordCount,
                    qualityFlags: flags
                )
            )
        }

        if blocks.isEmpty {
            issues.append(issue(sourcePath: sourcePath, message: "No script blocks were detected."))
        }

        return ScriptCorpusExtractionReport(blocks: blocks, issues: issues)
    }

    @discardableResult
    public static func writeScriptCorpus(
        _ report: ScriptCorpusExtractionReport,
        to outputDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try removeGeneratedFiles(in: outputDirectory, fileManager: fileManager)

        var written: [URL] = []
        for block in report.blocks where block.wordCount >= 40 {
            let phaseDirectory = outputDirectory.appending(path: block.phase.labelingPhase.rawValue, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: phaseDirectory, withIntermediateDirectories: true)
            let url = phaseDirectory.appending(path: "\(slug(for: block.title))-\(block.id.prefix(8)).txt")
            try block.spokenText.write(to: url, atomically: true, encoding: .utf8)
            written.append(url)
        }

        let manifestURL = outputDirectory.appending(path: "_extraction_manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: manifestURL, options: .atomic)
        written.append(manifestURL)

        return written.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

private extension ScriptCorpusExtractor {
    struct AnnotatedLine {
        let text: String
        let page: Int?
        let isContent: Bool
    }

    struct BlockRange {
        let titleIndex: Int
        let bodyRange: Range<Int>
    }

    struct CleanupResult {
        let spokenText: String
        let stageDirections: [String]
        let flags: Set<ScriptCorpusExtractionFlag>
    }

    static let supportedExtensions: Set<String> = ["rtf", "txt", "md"]

    static func plainText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "rtf" {
            return try rtfPlainText(from: data)
        }
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let string = String(data: data, encoding: .isoLatin1) {
            return string
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    static func removeGeneratedFiles(in outputDirectory: URL, fileManager: FileManager) throws {
        for phase in TrancePhase.orderedHypnosisPhases.map(\.labelingPhase) {
            let phaseDirectory = outputDirectory.appending(path: phase.rawValue, directoryHint: .isDirectory)
            guard fileManager.fileExists(atPath: phaseDirectory.path()) else { continue }
            let urls = try fileManager.contentsOfDirectory(at: phaseDirectory, includingPropertiesForKeys: nil)
            for url in urls where url.pathExtension.lowercased() == "txt" {
                try fileManager.removeItem(at: url)
            }
        }

        let manifestURL = outputDirectory.appending(path: "_extraction_manifest.json")
        if fileManager.fileExists(atPath: manifestURL.path()) {
            try fileManager.removeItem(at: manifestURL)
        }
    }

    static func rtfPlainText(from data: Data) throws -> String {
        #if canImport(AppKit)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        #endif

        if let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return stripRTF(raw)
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    static func stripRTF(_ raw: String) -> String {
        var output = ""
        var index = raw.startIndex

        while index < raw.endIndex {
            let character = raw[index]
            if character == "{" || character == "}" {
                index = raw.index(after: index)
                continue
            }
            guard character == "\\" else {
                output.append(character)
                index = raw.index(after: index)
                continue
            }

            index = raw.index(after: index)
            guard index < raw.endIndex else { break }
            let next = raw[index]
            if next == "\\" || next == "{" || next == "}" {
                output.append(next)
                index = raw.index(after: index)
                continue
            }
            if next == "'" {
                let first = raw.index(after: index)
                guard first < raw.endIndex else { break }
                let second = raw.index(after: first)
                guard second < raw.endIndex else { break }
                if let value = UInt8(String(raw[first...second]), radix: 16) {
                    output.append(Character(UnicodeScalar(value)))
                }
                index = raw.index(after: second)
                continue
            }

            let commandStart = index
            while index < raw.endIndex, raw[index].isLetter {
                index = raw.index(after: index)
            }
            let command = String(raw[commandStart..<index])
            while index < raw.endIndex, raw[index].isNumber || raw[index] == "-" {
                index = raw.index(after: index)
            }
            if index < raw.endIndex, raw[index].isWhitespace {
                index = raw.index(after: index)
            }
            if command == "par" || command == "line" {
                output.append("\n")
            }
        }
        return output
    }

    static func annotate(lines: [String]) -> [AnnotatedLine] {
        var currentPage: Int?
        return lines.map { line in
            if let page = pageNumber(in: line) {
                currentPage = page
                return AnnotatedLine(text: line, page: currentPage, isContent: false)
            }
            return AnnotatedLine(text: line, page: currentPage, isContent: line.isEmpty == false)
        }
    }

    static func blockRanges(in lines: [AnnotatedLine]) -> [BlockRange] {
        let headingIndices = lines.indices.filter { index in
            isScriptHeading(lines[index].text, nextLine: nextContentLine(after: index, in: lines))
        }

        return headingIndices.enumerated().compactMap { offset, titleIndex in
            let nextTitle = offset + 1 < headingIndices.count ? headingIndices[offset + 1] : lines.count
            let bodyStart = titleIndex + 1
            guard bodyStart < nextTitle else { return nil }
            return BlockRange(titleIndex: titleIndex, bodyRange: bodyStart..<nextTitle)
        }
    }

    static func isScriptHeading(_ line: String, nextLine: String?) -> Bool {
        let text = normalizedSpaces(line)
        guard text.count >= 3, text.count <= 90 else { return false }
        guard isNoiseLine(text) == false else { return false }
        guard text.hasPrefix("(") == false else { return false }
        guard genericSectionHeadings.contains(text.uppercased()) == false else { return false }
        guard titleSuffixes.contains(text.uppercased()) == false else { return false }
        guard likelyInstructionLine(text) == false else { return false }

        if nextLine?.hasPrefix("By ") == true { return true }
        if titleSuffixes.contains(nextLine?.uppercased() ?? "") { return true }
        if text.localizedCaseInsensitiveContains("awakening") { return hasTitleShape(text) }
        if text.localizedCaseInsensitiveContains("induction") { return hasTitleShape(text) }
        if text.localizedCaseInsensitiveContains("deepener") { return hasTitleShape(text) }
        if text.localizedCaseInsensitiveContains("depth test") { return hasTitleShape(text) }
        if text.localizedCaseInsensitiveContains("vehicle") { return hasTitleShape(text) }

        let letters = text.filter(\.isLetter)
        guard letters.count >= 3 else { return false }
        let uppercaseLetters = letters.filter(\.isUppercase).count
        return Double(uppercaseLetters) / Double(letters.count) > 0.85
    }

    static func hasTitleShape(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        guard letters.count >= 3 else { return false }
        let uppercaseLetters = letters.filter(\.isUppercase).count
        if Double(uppercaseLetters) / Double(letters.count) > 0.85 { return true }

        let minorWords: Set<String> = ["a", "an", "and", "as", "at", "by", "for", "from", "in", "of", "on", "or", "the", "to", "with"]
        let words = text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { minorWords.contains($0.lowercased()) == false }

        guard words.isEmpty == false else { return false }
        let titleWords = words.filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase || word.allSatisfy(\.isNumber)
        }
        return Double(titleWords.count) / Double(words.count) >= 0.75
    }

    static func titleText(from heading: String, nextLine: String?) -> String {
        let text = normalizedSpaces(heading)
        guard let nextLine, titleSuffixes.contains(nextLine.uppercased()) else {
            return text
        }
        if text.uppercased().hasSuffix(nextLine.uppercased()) {
            return text
        }
        return "\(text) \(titleCased(nextLine))"
    }

    static func cleanedSpokenText(from lines: [String]) -> CleanupResult {
        var spokenLines: [String] = []
        var stageDirections: [String] = []
        var flags = Set<ScriptCorpusExtractionFlag>()

        for rawLine in lines {
            let line = normalizedSpaces(rawLine)
            guard line.isEmpty == false else { continue }
            guard isNoiseLine(line) == false else { continue }
            guard line.hasPrefix("By ") == false else { continue }
            guard titleSuffixes.contains(line.uppercased()) == false else { continue }
            guard genericSectionHeadings.contains(line.uppercased()) == false else { continue }

            var extractedStageDirections: [String] = []
            let withoutDirections = removeParentheticals(from: line, removed: &extractedStageDirections)
            if extractedStageDirections.isEmpty == false {
                stageDirections.append(contentsOf: extractedStageDirections)
                flags.insert(.stageDirectionsRemoved)
            }

            let cleaned = normalizedSpaces(withoutDirections)
            guard cleaned.isEmpty == false else { continue }
            if likelyInstructionLine(cleaned) {
                flags.insert(.mixedInstructionalText)
                continue
            }
            spokenLines.append(cleaned)
        }

        return CleanupResult(
            spokenText: normalizedSpaces(spokenLines.joined(separator: " ")),
            stageDirections: stageDirections,
            flags: flags
        )
    }

    static func removeParentheticals(from line: String, removed: inout [String]) -> String {
        var output = ""
        var buffer = ""
        var depth = 0

        for character in line {
            if character == "(" || character == "[" {
                if depth == 0 { buffer = "" } else { buffer.append(character) }
                depth += 1
                continue
            }
            if character == ")" || character == "]" {
                if depth > 0 {
                    depth -= 1
                    if depth == 0 {
                        let direction = normalizedSpaces(buffer)
                        if direction.isEmpty == false { removed.append(direction) }
                    } else {
                        buffer.append(character)
                    }
                    continue
                }
            }
            if depth > 0 {
                buffer.append(character)
            } else {
                output.append(character)
            }
        }

        if depth > 0 {
            output.append(buffer)
        }
        return output
    }

    static func phaseFor(title: String, sourcePath: String, fallback: TrancePhase?) -> TrancePhase {
        let haystack = "\(title) \(sourcePath)"
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if haystack.contains("awakening") || haystack.contains("awakener") || haystack.contains("emergence") {
            return .emergence
        }
        if haystack.contains("fractionation") || haystack.contains("fractionate") || haystack.contains("fract") {
            return .deepening
        }
        if haystack.contains("confusion") || haystack.contains("analytical vehicle") || haystack.contains("vehicle") {
            return .deepening
        }
        if haystack.contains("deepener") || haystack.contains("deepening") || haystack.contains("depth test") {
            return .deepening
        }
        if haystack.contains("induction") || haystack.contains("induct") {
            return .induction
        }
        return fallback?.labelingPhase ?? .induction
    }

    static func inferredPhase(forPath path: String) -> TrancePhase? {
        let haystack = path
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if haystack.contains("awakening") || haystack.contains("awakener") || haystack.contains("emergence") {
            return .emergence
        }
        if haystack.contains("fractionation") || haystack.contains("fractionate") || haystack.contains("fract") {
            return .deepening
        }
        if haystack.contains("confusion") || haystack.contains("analytical vehicle") || haystack.contains("vehicle") {
            return .deepening
        }
        if haystack.contains("deepener") || haystack.contains("deepening") || haystack.contains("depth test") {
            return .deepening
        }
        if haystack.contains("induction") || haystack.contains("induct") {
            return .induction
        }
        return nil
    }

    static func shouldReview(title: String, sourcePath: String, body: String) -> Bool {
        let haystack = "\(title) \(sourcePath) \(body.prefix(240))".lowercased()
        return haystack.contains("depth test")
            || haystack.contains("analytical")
            || haystack.contains("vehicle")
            || haystack.contains("begin suggestions")
            || haystack.contains("enter script")
    }

    static func pageRange(for range: BlockRange, in lines: [AnnotatedLine]) -> ClosedRange<Int>? {
        let pages = lines[range.titleIndex..<range.bodyRange.upperBound].compactMap(\.page)
        guard let minPage = pages.min(), let maxPage = pages.max() else { return nil }
        return minPage...maxPage
    }

    static func pageNumber(in line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("-"), trimmed.hasSuffix("-") {
            let number = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            return Int(number)
        }
        return nil
    }

    static func isNoiseLine(_ line: String) -> Bool {
        let text = normalizedSpaces(line)
        guard text.isEmpty == false else { return true }
        if pageNumber(in: text) != nil { return true }
        if Int(text) != nil { return true }
        if text.hasPrefix("www.") || text.hasPrefix("http://") || text.hasPrefix("https://") { return true }
        if text.range(of: #"^\d+(\s+\d+)+$"#, options: .regularExpression) != nil { return true }
        return false
    }

    static func likelyInstructionLine(_ line: String) -> Bool {
        let text = line.lowercased()
        let prefixes = [
            "note:", "note that", "remember", "beware", "this induction", "this technique",
            "this method", "this one", "the purpose", "here are", "you may want",
            "if you have", "if your subject", "once you have", "after having conducted",
            "begin suggestion", "begin suggestions", "enter script", "insert suggestion",
            "spoken to the subject", "use the", "preparation for suggestion"
        ]
        return prefixes.contains { text.hasPrefix($0) }
    }

    static func nextContentLine(after index: Int, in lines: [AnnotatedLine]) -> String? {
        guard index + 1 < lines.count else { return nil }
        return lines[(index + 1)..<lines.count].first { $0.isContent }?.text
    }

    static func normalizedSpaces(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(in text: String) -> [String] {
        let pattern = #"[A-Za-z][A-Za-z']*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]).lowercased() }
        }
    }

    static func deterministicID(sourcePath: String, title: String, phase: TrancePhase, text: String) -> String {
        let seed = "\(sourcePath)|\(title)|\(phase.rawValue)|\(text.prefix(256))"
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func slug(for title: String) -> String {
        var slug = ""
        var lastWasDash = false
        for character in title.lowercased() {
            if character.isLetter || character.isNumber {
                slug.append(character)
                lastWasDash = false
            } else if lastWasDash == false {
                slug.append("-")
                lastWasDash = true
            }
        }
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func titleCased(_ value: String) -> String {
        value.lowercased()
            .split(separator: " ")
            .map { word in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    static func phaseSortIndex(_ phase: TrancePhase) -> Int {
        TrancePhase.orderedHypnosisPhases.firstIndex(of: phase.labelingPhase) ?? Int.max
    }

    static func displayPath(for url: URL, relativeTo directory: URL) -> String {
        let directoryPath = directory.standardizedFileURL.path()
        let filePath = url.standardizedFileURL.path()
        if filePath.hasPrefix(directoryPath + "/") {
            return String(filePath.dropFirst(directoryPath.count + 1))
        }
        return url.lastPathComponent
    }

    static func issue(sourcePath: String, message: String) -> ScriptCorpusExtractionIssue {
        let id = SHA256.hash(data: Data("\(sourcePath)|\(message)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return ScriptCorpusExtractionIssue(id: id, sourcePath: sourcePath, message: message)
    }

    static let titleSuffixes: Set<String> = [
        "INDUCTION",
        "INSTANT INDUCTION",
        "RAPID INDUCTION",
        "DEEPENER",
        "DEPTH TEST",
        "VEHICLE",
        "ANALYTICAL",
        "AWAKENING"
    ]

    static let genericSectionHeadings: Set<String> = [
        "INDUCTIONS",
        "INSTANT AND RAPID INDUCTIONS",
        "HOW THEY WORK",
        "DEEPENERS",
        "DEPTH TESTS",
        "ANALYTICAL VEHICLES",
        "AWAKENING"
    ]
}
