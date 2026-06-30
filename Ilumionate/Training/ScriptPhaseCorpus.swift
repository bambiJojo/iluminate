//
//  ScriptPhaseCorpus.swift
//  Ilumionate
//
//  Loads phase-labeled script libraries from text/RTF files. These examples
//  teach the analyzer language cues, not audio timing or boundary truth.
//

import CryptoKit
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

nonisolated struct ScriptPhaseCorpusIssue: Identifiable, Hashable, Sendable {
    enum Severity: String, Hashable, Sendable {
        case warning
        case error
    }

    let id = UUID()
    let severity: Severity
    let filename: String
    let message: String
}

nonisolated struct ScriptPhaseExample: Identifiable, Hashable, Sendable {
    let id: UUID
    let phase: TrancePhase
    let title: String
    let sourceFilename: String
    let sourcePath: String
    let sourcePackID: String?
    let sourcePackLabel: String?
    let text: String
    let wordCount: Int

    init(
        id: UUID,
        phase: TrancePhase,
        title: String,
        sourceFilename: String,
        sourcePath: String,
        sourcePackID: String? = nil,
        sourcePackLabel: String? = nil,
        text: String,
        wordCount: Int
    ) {
        self.id = id
        self.phase = phase
        self.title = title
        self.sourceFilename = sourceFilename
        self.sourcePath = sourcePath
        self.sourcePackID = sourcePackID
        self.sourcePackLabel = sourcePackLabel
        self.text = text
        self.wordCount = wordCount
    }
}

nonisolated struct ScriptPhaseCorpus: Sendable {
    let directories: [URL]
    let examples: [ScriptPhaseExample]
    let issues: [ScriptPhaseCorpusIssue]

    static let empty = ScriptPhaseCorpus(directories: [], examples: [], issues: [])

    static func loadDefault(
        fileManager: FileManager = .default,
        currentDirectory: URL = URL(filePath: FileManager.default.currentDirectoryPath),
        documentsDirectory: URL = .documentsDirectory,
        bundle: Bundle = .main
    ) -> ScriptPhaseCorpus {
        load(
            from: defaultDirectoryCandidates(
                currentDirectory: currentDirectory,
                documentsDirectory: documentsDirectory,
                bundle: bundle
            ),
            fileManager: fileManager
        )
    }

    static func load(
        from directory: URL,
        fileManager: FileManager = .default
    ) -> ScriptPhaseCorpus {
        load(from: [directory], fileManager: fileManager)
    }

    static func load(
        from directories: [URL],
        fileManager: FileManager = .default
    ) -> ScriptPhaseCorpus {
        let existingDirectories = uniqueURLs(directories)
            .filter { fileManager.fileExists(atPath: $0.path()) }

        guard !existingDirectories.isEmpty else { return .empty }

        var examples: [ScriptPhaseExample] = []
        var issues: [ScriptPhaseCorpusIssue] = []

        for directory in existingDirectories {
            let files: [URL]
            do {
                files = try scriptFiles(in: directory, fileManager: fileManager)
            } catch {
                issues.append(
                    ScriptPhaseCorpusIssue(
                        severity: .error,
                        filename: directory.lastPathComponent,
                        message: error.localizedDescription
                    )
                )
                continue
            }

            for url in files {
                guard let phase = inferredPhase(for: url, relativeTo: directory) else {
                    issues.append(
                        ScriptPhaseCorpusIssue(
                            severity: .warning,
                            filename: displayPath(for: url, relativeTo: directory),
                            message: "Could not infer a canonical phase from the filename or folder."
                        )
                    )
                    continue
                }

                do {
                    let text = try plainText(from: url)
                    let normalizedText = normalizeWhitespace(in: text)
                    let wordCount = ScriptPhaseTextAnalyzer.tokens(in: normalizedText).count
                    guard wordCount >= 12 else {
                        issues.append(
                            ScriptPhaseCorpusIssue(
                                severity: .warning,
                                filename: displayPath(for: url, relativeTo: directory),
                                message: "Script text was too short to use as phase evidence."
                            )
                        )
                        continue
                    }

                    examples.append(
                        ScriptPhaseExample(
                            id: deterministicID(for: url, phase: phase, text: normalizedText),
                            phase: phase,
                            title: title(for: url),
                            sourceFilename: url.lastPathComponent,
                            sourcePath: displayPath(for: url, relativeTo: directory),
                            sourcePackID: sourcePackID(for: url, relativeTo: directory),
                            sourcePackLabel: sourcePackLabel(for: url, relativeTo: directory),
                            text: normalizedText,
                            wordCount: wordCount
                        )
                    )
                } catch {
                    issues.append(
                        ScriptPhaseCorpusIssue(
                            severity: .error,
                            filename: displayPath(for: url, relativeTo: directory),
                            message: error.localizedDescription
                        )
                    )
                }
            }
        }

        return ScriptPhaseCorpus(
            directories: existingDirectories,
            examples: examples.sorted {
                if $0.phase.rawValue == $1.phase.rawValue {
                    return $0.sourcePath.localizedStandardCompare($1.sourcePath) == .orderedAscending
                }
                return phaseSortIndex($0.phase) < phaseSortIndex($1.phase)
            },
            issues: issues
        )
    }

    static func signature(
        for corpus: ScriptPhaseCorpus,
        fileManager: FileManager = .default
    ) -> String? {
        guard !corpus.directories.isEmpty else { return nil }

        let parts = corpus.directories.map { directory -> String in
            let files = (try? scriptFiles(in: directory, fileManager: fileManager)) ?? []
            let fileParts = files.map { url -> String in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                let size = values?.fileSize ?? 0
                return "\(displayPath(for: url, relativeTo: directory)):\(modified):\(size)"
            }
            return "\(directory.standardizedFileURL.path())[\(fileParts.joined(separator: ","))]"
        }

        let data = Data(parts.joined(separator: "|").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultDirectoryCandidates(
        currentDirectory: URL,
        documentsDirectory: URL,
        bundle: Bundle
    ) -> [URL] {
        var candidates: [URL] = [
            TrainingCorpusLocation.defaultURL(documentsDirectory: documentsDirectory)
                .appending(path: "ScriptCorpus", directoryHint: .isDirectory),
            TrainingCorpusLocation.defaultURL(documentsDirectory: documentsDirectory)
                .appending(path: "Scripts", directoryHint: .isDirectory)
        ]

        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL.appending(path: "ScriptCorpus", directoryHint: .isDirectory))
        }

        var cursor = currentDirectory.standardizedFileURL
        while true {
            candidates.append(cursor.appending(path: "ScriptCorpus", directoryHint: .isDirectory))

            let parent = cursor.deletingLastPathComponent().standardizedFileURL
            guard parent.path() != cursor.path() else { break }
            cursor = parent
        }

        return candidates
    }

    private static func scriptFiles(in directory: URL, fileManager: FileManager) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isDirectory != true else { continue }
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            files.append(url)
        }

        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func inferredPhase(for url: URL, relativeTo directory: URL) -> TrancePhase? {
        let haystack = displayPath(for: url, relativeTo: directory)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        let matches: [(needles: [String], phase: TrancePhase)] = [
            (["awakening", "awakener", "emergence", "emerge"], .emergence),
            (["fractionation", "fractionate", "fract"], .fractionation),
            (["confusion"], .confusion),
            (["brainwashing", "brainwash"], .brainwashing),
            (["deepener", "deepening", "depth test", "depthtest", "depth tests", "depthtests"], .deepening),
            (["induction", "inductions", "induct"], .induction),
            (["suggestion", "suggestions"], .suggestions),
            (["pre talk", "pretalk"], .preTalk)
        ]

        return matches.first { entry in
            entry.needles.contains { haystack.contains($0) }
        }?.phase.labelingPhase
    }

    private static func plainText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        switch url.pathExtension.lowercased() {
        case "rtf":
            return try rtfPlainText(from: data)
        default:
            if let string = String(data: data, encoding: .utf8) {
                return string
            }
            if let string = String(data: data, encoding: .isoLatin1) {
                return string
            }
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private static func rtfPlainText(from data: Data) throws -> String {
        #if canImport(UIKit) || canImport(AppKit)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        if let attributed = try? NSAttributedString(
            data: data,
            options: options,
            documentAttributes: nil
        ) {
            return attributed.string
        }
        #endif

        if let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            return stripRTF(raw)
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    private static func stripRTF(_ raw: String) -> String {
        var output = ""
        var index = raw.startIndex

        while index < raw.endIndex {
            let character = raw[index]

            if character == "{" || character == "}" {
                index = raw.index(after: index)
                continue
            }

            if character != "\\" {
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
                let hex = String(raw[first...second])
                if let value = UInt8(hex, radix: 16) {
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

    private static func normalizeWhitespace(in text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayPath(for url: URL, relativeTo directory: URL) -> String {
        let directoryPath = normalizedDirectoryPath(directory)
        let filePath = url.standardizedFileURL.resolvingSymlinksInPath().path()
        if filePath.hasPrefix(directoryPath + "/") {
            return String(filePath.dropFirst(directoryPath.count + 1))
        }
        return url.lastPathComponent
    }

    private static func normalizedDirectoryPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.resolvingSymlinksInPath().path()
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func sourcePackID(for url: URL, relativeTo directory: URL) -> String? {
        let components = displayPath(for: url, relativeTo: directory)
            .split(separator: "/")
            .map(String.init)
        guard components.count >= 3, let firstComponent = components.first else { return nil }

        let normalized = normalizedPathComponent(firstComponent)
        guard !phaseFolderHints.contains(normalized) else { return nil }
        return normalized.isEmpty ? nil : normalized
    }

    private static func sourcePackLabel(for url: URL, relativeTo directory: URL) -> String? {
        guard let sourcePackID = sourcePackID(for: url, relativeTo: directory) else { return nil }
        switch sourcePackID {
        case "bambi":
            return "Bambi corpus"
        default:
            let words = sourcePackID
                .split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return "\(words.joined(separator: " ")) corpus"
        }
    }

    private static func normalizedPathComponent(_ component: String) -> String {
        component
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func title(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func deterministicID(for url: URL, phase: TrancePhase, text: String) -> UUID {
        let seed = "\(url.standardizedFileURL.path())|\(phase.rawValue)|\(text.prefix(512))"
        let bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func phaseSortIndex(_ phase: TrancePhase) -> Int {
        TrancePhase.orderedHypnosisPhases.firstIndex(of: phase) ?? Int.max
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            let path = url.standardizedFileURL.path()
            guard seen.insert(path).inserted else { return nil }
            return url
        }
    }

    private static let supportedExtensions: Set<String> = ["rtf", "txt", "md"]
    private static let phaseFolderHints: Set<String> = [
        "awakening",
        "awakener",
        "emergence",
        "emerge",
        "fractionation",
        "fractionate",
        "fract",
        "confusion",
        "brainwashing",
        "brainwash",
        "deepener",
        "deepening",
        "depth-test",
        "depthtest",
        "depth-tests",
        "depthtests",
        "induction",
        "inductions",
        "induct",
        "suggestion",
        "suggestions",
        "pre-talk",
        "pretalk"
    ]
}

struct ScriptPhaseTermStatistic: Hashable, Sendable {
    let term: String
    let count: Int
    let share: Double
}

struct ScriptPhaseTextEvidence: Sendable {
    let words: [ScriptPhaseTermStatistic]
    let phrases: [ScriptPhaseTermStatistic]
    let waymarkerMatches: [HypnosisWaymarkerMatch]
}

nonisolated enum ScriptPhaseTextAnalyzer {
    static func evidence(in text: String) -> ScriptPhaseTextEvidence {
        let allTokens = tokens(in: text)
        let wordCounts = tokenFrequency(in: allTokens)
        let phraseCounts = phraseFrequency(in: allTokens)
        let wordTotal = max(wordCounts.values.reduce(0, +), 1)
        let phraseTotal = max(phraseCounts.values.reduce(0, +), 1)

        let words = wordCounts.map { word, count in
            ScriptPhaseTermStatistic(
                term: word,
                count: count,
                share: Double(count) / Double(wordTotal)
            )
        }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.term < rhs.term }
            return lhs.count > rhs.count
        }

        let phrases = phraseCounts.map { phrase, count in
            ScriptPhaseTermStatistic(
                term: phrase,
                count: count,
                share: Double(count) / Double(phraseTotal)
            )
        }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count { return lhs.term < rhs.term }
            return lhs.count > rhs.count
        }

        return ScriptPhaseTextEvidence(
            words: Array(words.prefix(24)),
            phrases: Array(phrases.prefix(24)),
            waymarkerMatches: detectWaymarkers(in: phraseCounts)
        )
    }

    static func tokens(in text: String) -> [String] {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'"))
        let normalized = String(
            text
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .unicodeScalars
                .map { allowedCharacters.contains($0) ? Character($0) : " " }
        )

        return normalized
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token.trimmingCharacters(in: CharacterSet(charactersIn: "'")).lowercased()
            }
            .filter { !$0.isEmpty }
    }

    private static func tokenFrequency(in words: [String]) -> [String: Int] {
        words.reduce(into: [:]) { counts, word in
            guard !stopWords.contains(word) else { return }
            guard word.count >= 3 else { return }
            guard word.rangeOfCharacter(from: .letters) != nil else { return }
            counts[word, default: 0] += 1
        }
    }

    private static func phraseFrequency(in words: [String]) -> [String: Int] {
        guard words.count >= 2 else { return [:] }

        var counts: [String: Int] = [:]
        let maxPhraseLength = min(4, words.count)
        for phraseLength in 2...maxPhraseLength {
            for startIndex in 0...(words.count - phraseLength) {
                let phraseWords = Array(words[startIndex..<(startIndex + phraseLength)])
                guard shouldTrackPhrase(phraseWords) else { continue }
                counts[phraseWords.joined(separator: " "), default: 0] += 1
            }
        }
        return counts
    }

    private static func shouldTrackPhrase(_ words: [String]) -> Bool {
        let meaningfulWordCount = words.filter { !stopWords.contains($0) && $0.count >= 3 }.count
        guard meaningfulWordCount >= 1 else { return false }
        guard Set(words).count > 1 else { return false }

        let ignoredPhrases = Set([
            "and you can",
            "and as you",
            "as you can",
            "you can feel"
        ])
        return !ignoredPhrases.contains(words.joined(separator: " "))
    }

    private static func detectWaymarkers(in phraseCounts: [String: Int]) -> [HypnosisWaymarkerMatch] {
        HypnosisWaymarkerLexicon.allPatterns.compactMap { pattern in
            guard let count = phraseCounts[pattern.phrase], count > 0 else { return nil }
            return HypnosisWaymarkerMatch(
                phrase: pattern.phrase,
                phase: pattern.phase.labelingPhase,
                count: count,
                score: Double(count) * pattern.weight
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.score - rhs.score) < 0.001 {
                return lhs.phrase < rhs.phrase
            }
            return lhs.score > rhs.score
        }
    }

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "for",
        "from", "had", "has", "have", "he", "her", "hers", "him", "his", "i",
        "if", "in", "into", "is", "it", "its", "just", "let", "me", "my",
        "now", "of", "on", "or", "our", "ours", "she", "so", "that", "the",
        "their", "theirs", "them", "there", "these", "they", "this", "those",
        "to", "up", "was", "we", "were", "with", "you", "your", "yours"
    ]
}
