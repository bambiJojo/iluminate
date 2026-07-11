//  ReadingDocumentImporter.swift
//  Ilumionate
//
//  Extracts plain reader text from imported PDFs and ePub files.

import Compression
import Foundation
import PDFKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ReadingDocumentImportError: LocalizedError, Equatable {
    case unsupportedFileType
    case unreadablePDF
    case unreadableEPUB
    case noReadableText
    case unsupportedZipEntry(String)
    case corruptZipArchive

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "Import a PDF or ePub file."
        case .unreadablePDF:
            return "This PDF could not be opened."
        case .unreadableEPUB:
            return "This ePub could not be opened."
        case .noReadableText:
            return "No readable text was found in this document."
        case .unsupportedZipEntry(let filename):
            return "\(filename) uses an unsupported ePub compression method."
        case .corruptZipArchive:
            return "This ePub file appears to be damaged."
        }
    }
}

enum ReadingDocumentImporter {
    nonisolated static var supportedContentTypes: [UTType] {
        var types: [UTType] = [.pdf]
        if let epub = UTType(filenameExtension: "epub") {
            types.append(epub)
        } else if let epub = UTType("org.idpf.epub-container") {
            types.append(epub)
        }
        return types
    }

    nonisolated static func extract(from url: URL) throws -> ExtractedReadingDocument {
        guard let kind = ReadingDocumentKind(fileExtension: url.pathExtension) else {
            throw ReadingDocumentImportError.unsupportedFileType
        }

        switch kind {
        case .pdf:
            return try extractPDF(from: url)
        case .epub:
            return try extractEPUB(from: url)
        }
    }

    private nonisolated static func extractPDF(from url: URL) throws -> ExtractedReadingDocument {
        guard let pdf = PDFDocument(url: url) else {
            throw ReadingDocumentImportError.unreadablePDF
        }

        let pageText = (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .map(ReaderDocumentHTMLExtractor.normalizeText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let text = ReaderDocumentHTMLExtractor.normalizeText(pageText)
        guard wordCount(in: text) >= 8 else {
            throw ReadingDocumentImportError.noReadableText
        }

        let title = documentTitle(
            preferred: pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
            fallbackURL: url
        )

        return ExtractedReadingDocument(
            title: title,
            kind: .pdf,
            originalFilename: url.lastPathComponent,
            text: text
        )
    }

    private nonisolated static func extractEPUB(from url: URL) throws -> ExtractedReadingDocument {
        let archive: EPUBArchive
        do {
            archive = try EPUBArchive(data: Data(contentsOf: url))
        } catch let error as ReadingDocumentImportError {
            throw error
        } catch {
            throw ReadingDocumentImportError.unreadableEPUB
        }

        let package = try EPUBPackage(archive: archive)
        let text = try package.readingText()
        guard wordCount(in: text) >= 8 else {
            throw ReadingDocumentImportError.noReadableText
        }

        return ExtractedReadingDocument(
            title: documentTitle(preferred: package.title, fallbackURL: url),
            kind: .epub,
            originalFilename: url.lastPathComponent,
            text: text
        )
    }

    private nonisolated static func documentTitle(preferred: String?, fallbackURL: URL) -> String {
        let cleaned = ReaderDocumentHTMLExtractor.normalizeTitle(preferred ?? "")
        if !cleaned.isEmpty { return cleaned }
        let filename = fallbackURL.deletingPathExtension().lastPathComponent
        return filename.isEmpty ? "Imported Document" : filename
    }

    nonisolated static func wordCount(in text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }
}

private struct EPUBPackage {
    let archive: EPUBArchive
    let packagePath: String
    let packageDirectory: String
    let title: String?
    let manifest: [String: ManifestItem]
    let spine: [String]

    nonisolated init(archive: EPUBArchive) throws {
        self.archive = archive
        packagePath = try Self.packagePath(in: archive)
        packageDirectory = Self.directoryPath(for: packagePath)

        guard let opf = archive.string(forPath: packagePath) else {
            throw ReadingDocumentImportError.unreadableEPUB
        }

        title = Self.metadataTitle(in: opf)
        manifest = Self.manifestItems(in: opf)
        spine = Self.spineIDs(in: opf)
    }

    nonisolated func readingText() throws -> String {
        let orderedItems = spine.compactMap { manifest[$0] }
        let htmlItems = orderedItems.isEmpty
            ? manifest.values.sorted { $0.href < $1.href }
            : orderedItems

        let sections = htmlItems.compactMap { item -> String? in
            guard item.isReadableText else { return nil }
            let path = Self.resolve(item.href, relativeTo: packageDirectory)
            guard let html = archive.string(forPath: path) else { return nil }
            let text = ReaderDocumentHTMLExtractor.readerText(fromHTML: html)
            guard ReadingDocumentImporter.wordCount(in: text) > 0 else { return nil }

            if let heading = ReaderDocumentHTMLExtractor.chapterTitle(fromHTML: html),
               !text.localizedCaseInsensitiveContains(heading) {
                return "\(heading)\n\n\(text)"
            }
            return text
        }

        let text = ReaderDocumentHTMLExtractor.normalizeText(sections.joined(separator: "\n\n"))
        if text.isEmpty { throw ReadingDocumentImportError.noReadableText }
        return text
    }

    private nonisolated static func packagePath(in archive: EPUBArchive) throws -> String {
        if let container = archive.string(forPath: "META-INF/container.xml"),
           let path = firstAttribute("full-path", in: container) {
            return normalizeArchivePath(path)
        }

        if let opfPath = archive.paths.first(where: { $0.lowercased().hasSuffix(".opf") }) {
            return opfPath
        }

        throw ReadingDocumentImportError.unreadableEPUB
    }

    private nonisolated static func metadataTitle(in opf: String) -> String? {
        guard let rawTitle = firstCapture(
            #"<\s*(?:dc:)?title\b[^>]*>([\s\S]*?)<\s*/\s*(?:dc:)?title\s*>"#,
            in: opf
        ) else {
            return nil
        }
        return ReaderDocumentHTMLExtractor.normalizeTitle(rawTitle)
    }

    private nonisolated static func manifestItems(in opf: String) -> [String: ManifestItem] {
        tags(named: "item", in: opf).reduce(into: [:]) { result, tag in
            let attributes = attributes(in: tag)
            guard let id = attributes["id"], let href = attributes["href"] else { return }
            result[id] = ManifestItem(
                id: id,
                href: href,
                mediaType: attributes["media-type"] ?? ""
            )
        }
    }

    private nonisolated static func spineIDs(in opf: String) -> [String] {
        tags(named: "itemref", in: opf).compactMap { tag in
            let attributes = attributes(in: tag)
            if attributes["linear"]?.lowercased() == "no" { return nil }
            return attributes["idref"]
        }
    }

    private nonisolated static func resolve(_ href: String, relativeTo basePath: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        let baseURL = URL(fileURLWithPath: "/" + basePath, isDirectory: true)
        let resolved = URL(fileURLWithPath: decoded, relativeTo: baseURL)
            .standardizedFileURL
            .path
        return normalizeArchivePath(String(resolved.drop { $0 == "/" }))
    }

    private nonisolated static func directoryPath(for archivePath: String) -> String {
        let normalized = normalizeArchivePath(archivePath)
        guard let slashIndex = normalized.lastIndex(of: "/") else { return "" }
        return String(normalized[..<slashIndex])
    }

    private nonisolated static func normalizeArchivePath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private nonisolated static func tags(named name: String, in text: String) -> [String] {
        let pattern = #"<\s*\#(name)\b[^>]*>"#
        return matches(pattern, in: text)
    }

    private nonisolated static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*["']([^"']*)["']"#
        return capturePairs(pattern, in: tag).reduce(into: [:]) { result, pair in
            result[pair.0.lowercased()] = pair.1
        }
    }

    private nonisolated static func firstAttribute(_ attribute: String, in text: String) -> String? {
        attributes(in: text)[attribute.lowercased()]
    }

    private nonisolated static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private nonisolated static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private nonisolated static func capturePairs(_ pattern: String, in text: String) -> [(String, String)] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 2,
                  let keyRange = Range(match.range(at: 1), in: text),
                  let valueRange = Range(match.range(at: 2), in: text) else {
                return nil
            }
            return (String(text[keyRange]), String(text[valueRange]))
        }
    }

    struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String

        nonisolated var isReadableText: Bool {
            let lowercasedType = mediaType.lowercased()
            let lowercasedHref = href.lowercased()
            return lowercasedType.contains("html")
                || lowercasedHref.hasSuffix(".xhtml")
                || lowercasedHref.hasSuffix(".html")
                || lowercasedHref.hasSuffix(".htm")
        }
    }
}

private struct EPUBArchive {
    let entries: [String: Entry]
    let data: Data

    nonisolated var paths: [String] { Array(entries.keys) }

    nonisolated init(data: Data) throws {
        self.data = data
        entries = try Self.readEntries(from: data)
    }

    nonisolated func string(forPath path: String) -> String? {
        guard let data = try? data(forPath: path) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        return nil
    }

    nonisolated func data(forPath path: String) throws -> Data? {
        let normalized = Self.normalize(path)
        let entry = entries[normalized]
            ?? entries.first { $0.key.lowercased() == normalized.lowercased() }?.value
        guard let entry else { return nil }

        let compressedData = data.subdata(in: entry.dataRange)
        switch entry.compressionMethod {
        case 0:
            return compressedData
        case 8:
            return try Self.inflate(compressedData, expectedSize: entry.uncompressedSize)
        default:
            throw ReadingDocumentImportError.unsupportedZipEntry(entry.filename)
        }
    }

    private nonisolated static func readEntries(from data: Data) throws -> [String: Entry] {
        guard let eocdOffset = endOfCentralDirectoryOffset(in: data),
              data.u32(at: eocdOffset) == 0x06054b50 else {
            throw ReadingDocumentImportError.corruptZipArchive
        }

        let entryCount = Int(data.u16(at: eocdOffset + 10))
        let centralDirectoryOffset = Int(data.u32(at: eocdOffset + 16))
        var offset = centralDirectoryOffset
        var entries: [String: Entry] = [:]

        for _ in 0..<entryCount {
            guard offset + 46 <= data.count,
                  data.u32(at: offset) == 0x02014b50 else {
                throw ReadingDocumentImportError.corruptZipArchive
            }

            let compressionMethod = data.u16(at: offset + 10)
            let compressedSize = Int(data.u32(at: offset + 20))
            let uncompressedSize = Int(data.u32(at: offset + 24))
            let filenameLength = Int(data.u16(at: offset + 28))
            let extraLength = Int(data.u16(at: offset + 30))
            let commentLength = Int(data.u16(at: offset + 32))
            let localHeaderOffset = Int(data.u32(at: offset + 42))
            let nameStart = offset + 46
            let nameEnd = nameStart + filenameLength
            guard nameEnd <= data.count else {
                throw ReadingDocumentImportError.corruptZipArchive
            }

            let filenameData = data.subdata(in: nameStart..<nameEnd)
            guard let filename = String(data: filenameData, encoding: .utf8) else {
                throw ReadingDocumentImportError.corruptZipArchive
            }

            guard localHeaderOffset + 30 <= data.count,
                  data.u32(at: localHeaderOffset) == 0x04034b50 else {
                throw ReadingDocumentImportError.corruptZipArchive
            }

            let localFilenameLength = Int(data.u16(at: localHeaderOffset + 26))
            let localExtraLength = Int(data.u16(at: localHeaderOffset + 28))
            let dataStart = localHeaderOffset + 30 + localFilenameLength + localExtraLength
            let dataEnd = dataStart + compressedSize
            guard dataStart <= dataEnd, dataEnd <= data.count else {
                throw ReadingDocumentImportError.corruptZipArchive
            }

            let normalized = normalize(filename)
            if !normalized.hasSuffix("/") {
                entries[normalized] = Entry(
                    filename: normalized,
                    compressionMethod: compressionMethod,
                    uncompressedSize: uncompressedSize,
                    dataRange: dataStart..<dataEnd
                )
            }

            offset = nameEnd + extraLength + commentLength
        }

        return entries
    }

    private nonisolated static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let earliest = max(0, data.count - 65_557)
        for offset in stride(from: data.count - 22, through: earliest, by: -1) {
            if data.u32(at: offset) == 0x06054b50 { return offset }
        }
        return nil
    }

    private nonisolated static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        let outputCapacity = max(expectedSize, 1)
        var output = Data(count: outputCapacity)
        let decodedCount = output.withUnsafeMutableBytes { outputBuffer in
            input.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    outputCapacity,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard decodedCount > 0 else {
            throw ReadingDocumentImportError.corruptZipArchive
        }

        output.removeSubrange(decodedCount..<output.count)
        return output
    }

    private nonisolated static func normalize(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    struct Entry {
        let filename: String
        let compressionMethod: UInt16
        let uncompressedSize: Int
        let dataRange: Range<Int>
    }
}

private enum ReaderDocumentHTMLExtractor {
    nonisolated static func readerText(fromHTML html: String) -> String {
        var text = html
        text = replace(#"<!--[\s\S]*?-->"#, in: text)
        text = replace(#"<\s*(script|style|svg|noscript)\b[^>]*>[\s\S]*?<\s*/\s*\1\s*>"#, in: text)
        text = replace(#"<\s*br\s*/?\s*>"#, in: text, with: "\n")
        text = replace(#"</\s*(p|div|li|h[1-6]|section|article|blockquote|tr|td)\s*>"#, in: text, with: "\n")
        text = replace(#"<[^>]+>"#, in: text)
        return normalizeText(decodeHTMLEntities(text))
    }

    nonisolated static func chapterTitle(fromHTML html: String) -> String? {
        let headingPattern = #"<\s*h[1-3]\b[^>]*>([\s\S]*?)<\s*/\s*h[1-3]\s*>"#
        if let heading = firstCapture(headingPattern, in: html) {
            let title = normalizeTitle(heading)
            if !title.isEmpty { return title }
        }

        let titlePattern = #"<\s*title\b[^>]*>([\s\S]*?)<\s*/\s*title\s*>"#
        guard let title = firstCapture(titlePattern, in: html) else { return nil }
        let normalized = normalizeTitle(title)
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated static func normalizeTitle(_ text: String) -> String {
        normalizeText(decodeHTMLEntities(stripTags(text)))
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    nonisolated static func normalizeText(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { collapseSpaces($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.joined(separator: "\n\n")
    }

    private nonisolated static func stripTags(_ text: String) -> String {
        replace(#"<[^>]+>"#, in: text)
    }

    private nonisolated static func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return text
        }
        return attributed.string
    }

    private nonisolated static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private nonisolated static func collapseSpaces(_ text: String) -> String {
        replace(#"[ \t\f\v]+"#, in: text, with: " ", options: [])
    }

    private nonisolated static func replace(
        _ pattern: String,
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
}

private extension Data {
    nonisolated func u16(at offset: Int) -> UInt16 {
        UInt16(self[offset])
            | UInt16(self[offset + 1]) << 8
    }

    nonisolated func u32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
