# Reader File-Drop Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Finder/Files cable-drop inbox so a dropped `.txt`, `.md`, `.pdf`, or `.epub` reaches the TextTrance reader library, alongside the audio it already admits.

**Architecture:** Route inside the existing `CableAudioImportService` rather than adding a second scanner, so a mixed batch settles as one unit. A new `CableInboxFileKind` classifies each settled file; audio keeps its current branch, reader documents go through a new `ReaderInboxAdmission` into `ReadingDocumentStore`. Source files move to a visible `_Imported/` folder on success.

**Tech Stack:** Swift 6.2, strict concurrency, SwiftUI, Swift Testing. iOS 18.0 / macOS 26.0 deployment. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-28-reader-file-drop-ingestion-design.md`

---

## Orientation for someone new to this codebase

Read these before starting. They are the load-bearing facts.

**The settle heuristic is the delicate part.** `CableAudioImportService.importAvailableFiles()` takes two directory snapshots a second apart and refuses to move *anything* while *any* file in the directory has been modified in the last 5 seconds. This exists because Finder copies a batch one file at a time, and moving an early file mid-batch makes the whole drag fail with "required file cannot be found." Do not touch this logic. This plan only changes what happens to a file *after* it has settled.

**The root is scanned recursively with name-based exclusion.** `FileManager.enumerator` walks Documents, skipping descendants of directories named in `excludedRootDirectoryNames`. Adding a new app-owned directory under Documents **without** adding it to that set means the scanner re-scans its own output on every pass, forever.

**Root vs dedicated inbox differ in one way only.** An unrecognised file at the Documents root belongs to somebody else and is left alone. The same file in a dedicated inbox is a failed import and goes to `_Needs Review`.

**Reader documents do not keep their source file.** `ReadingDocumentStore` extracts text into Application Support and stores only that. So the dropped file is the user's only copy, which is why it moves to a visible `_Imported/` rather than being deleted.

**Test filters that match nothing still report success.** Always run via `Scripts/run-tests.sh`, which fails when zero cases ran. Swift Testing identifiers end in `()`; suite-level filters do not. See ERRORS.md ERR-002.

**Build and test commands used throughout:**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/SUITE_NAME
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

**New files must be added to the `Ilumionate` target in Xcode** (and test files to `IlumionateTests`). A new `.swift` file that is not a target member compiles nowhere and fails with "cannot find X in scope."

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `Ilumionate/TextTrance/MarkdownTextCleaner.swift` | Create | Strip Markdown syntax so the ORP reader never displays `##` or `**` as a word |
| `Ilumionate/CableInboxFileKind.swift` | Create | Classify a settled file: `.audio`, `.readerDocument`, `.unrecognized` |
| `Ilumionate/ReaderInboxAdmission.swift` | Create | Admit one reader document; map errors to rejection vs failure |
| `Ilumionate/TextTrance/ReadingDocument.swift` | Modify | Add `.text` kind |
| `Ilumionate/TextTrance/ReadingDocumentImporter.swift` | Modify | Plain-text extraction, size cap, `supportedFileExtensions` |
| `Ilumionate/TextTrance/ReadingDocumentStore.swift` | Modify | Report whether an import replaced an existing document |
| `Ilumionate/AppStoragePaths.swift` | Modify | `cableTextInbox`, `cableImported`; fix stale doc comment |
| `Ilumionate/CableAudioImportService.swift` → `CableFileImportService.swift` | Rename + modify | Route by kind; move originals to `_Imported/` |
| `Ilumionate/CableAudioImportResult.swift` → `CableFileImportResult.swift` | Rename + modify | Carry `importedDocuments`; count both kinds in copy |
| `Ilumionate/CableAudioImportModel.swift` → `CableFileImportModel.swift` | Rename + modify | Count documents in the session total |
| `Ilumionate/ContentView.swift` | Modify | Alert gains an Open Reader action |
| `Ilumionate/LibraryAddMenu.swift`, `LibraryView.swift` | Modify | "Check Incoming Files" |
| `ERRORS.md` | Modify | Log the unbounded ePub read |

---

## Task 1: Plain text becomes a reader document kind

**Files:**
- Modify: `Ilumionate/TextTrance/ReadingDocument.swift:9-35`
- Modify: `Ilumionate/TextTrance/ReadingDocumentImporter.swift:17-56`
- Test: `IlumionateTests/TextTrance/ReadingDocumentImporterTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside `struct ReadingDocumentImporterTests`:

```swift
    @Test func extractsPlainTextFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Evening Script.txt")
        try Data("Let your shoulders drop and your breathing slow right down now.".utf8)
            .write(to: url)

        let extracted = try ReadingDocumentImporter.extract(from: url)

        #expect(extracted.kind == .text)
        #expect(extracted.title == "Evening Script")
        #expect(extracted.originalFilename == "Evening Script.txt")
        #expect(extracted.text == "Let your shoulders drop and your breathing slow right down now.")
    }

    @Test func rejectsPlainTextWithTooFewWords() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Stub.txt")
        try Data("Too short.".utf8).write(to: url)

        #expect(throws: ReadingDocumentImportError.noReadableText) {
            try ReadingDocumentImporter.extract(from: url)
        }
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReadingDocumentImporterTests
```

Expected: FAIL — `.text` is not a member of `ReadingDocumentKind`.

- [ ] **Step 3: Add the `.text` kind**

In `ReadingDocument.swift`, extend `ReadingDocumentKind`:

```swift
enum ReadingDocumentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case pdf
    case epub
    case text

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .pdf:  return "PDF"
        case .epub: return "ePub"
        case .text: return "Text"
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .pdf:  return "doc.richtext.fill"
        case .epub: return "book.closed.fill"
        case .text: return "doc.text.fill"
        }
    }

    nonisolated init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "pdf":  self = .pdf
        case "epub": self = .epub
        case "txt", "md", "markdown": self = .text
        default: return nil
        }
    }
}
```

`.text` is added **last** so the `String` raw values of `.pdf` and `.epub` are untouched and previously persisted `documents.json` still decodes.

- [ ] **Step 4: Add plain-text extraction**

In `ReadingDocumentImporter.swift`, add the extension set and route the new kind. Replace the `supportedContentTypes` property and `extract(from:)` with:

```swift
    nonisolated static let supportedFileExtensions: Set<String> = [
        "txt", "md", "markdown", "pdf", "epub"
    ]

    nonisolated static var supportedContentTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText]
        if let epub = UTType(filenameExtension: "epub") {
            types.append(epub)
        } else if let epub = UTType("org.idpf.epub-container") {
            types.append(epub)
        }
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
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
        case .text:
            return try extractPlainText(from: url)
        }
    }

    private nonisolated static func extractPlainText(from url: URL) throws -> ExtractedReadingDocument {
        let data = try Data(contentsOf: url)
        guard let raw = decodeText(data) else {
            throw ReadingDocumentImportError.noReadableText
        }

        let text = ReaderDocumentHTMLExtractor.normalizeText(raw)
        guard wordCount(in: text) >= 8 else {
            throw ReadingDocumentImportError.noReadableText
        }

        return ExtractedReadingDocument(
            title: documentTitle(preferred: nil, fallbackURL: url),
            kind: .text,
            originalFilename: url.lastPathComponent,
            text: text
        )
    }

    /// UTF-8 first, Latin-1 as a fallback. A file that decodes as neither is
    /// binary wearing a `.txt` extension, and is refused rather than rendered
    /// as replacement characters in the reader.
    private nonisolated static func decodeText(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1)
    }
```

Also update the `unsupportedFileType` message, which currently names only two formats:

```swift
        case .unsupportedFileType:
            return "Import a text, Markdown, PDF, or ePub file."
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReadingDocumentImporterTests
```

Expected: PASS, including the pre-existing ePub and PDF cases.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/TextTrance/ReadingDocument.swift Ilumionate/TextTrance/ReadingDocumentImporter.swift IlumionateTests/TextTrance/ReadingDocumentImporterTests.swift
git commit -m "feat: the reader imports plain text files"
```

---

## Task 2: Markdown syntax is stripped before reading

The ORP reader displays one word at a time. A literal `##` or `**word**` in the word stream is visible garbage, so `.md` gets cleaned and `.txt` does not.

**Files:**
- Create: `Ilumionate/TextTrance/MarkdownTextCleaner.swift`
- Modify: `Ilumionate/TextTrance/ReadingDocumentImporter.swift`
- Test: `IlumionateTests/TextTrance/MarkdownTextCleanerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/TextTrance/MarkdownTextCleanerTests.swift`:

```swift
//  MarkdownTextCleanerTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

struct MarkdownTextCleanerTests {

    @Test func stripsHeadingMarkers() {
        #expect(MarkdownTextCleaner.plainText(from: "## Deep Rest") == "Deep Rest")
    }

    @Test func stripsEmphasisMarkers() {
        let cleaned = MarkdownTextCleaner.plainText(from: "You feel **calm** and _steady_ now.")
        #expect(cleaned == "You feel calm and steady now.")
    }

    @Test func keepsLinkTextAndDropsTheURL() {
        let cleaned = MarkdownTextCleaner.plainText(from: "Read [the guide](https://example.com) later.")
        #expect(cleaned == "Read the guide later.")
    }

    @Test func stripsListBulletsAndBlockquoteMarkers() {
        let cleaned = MarkdownTextCleaner.plainText(from: "- breathe in\n- breathe out\n> settle")
        #expect(cleaned == "breathe in\nbreathe out\nsettle")
    }

    @Test func stripsCodeFencesAndInlineBackticks() {
        let cleaned = MarkdownTextCleaner.plainText(from: "```\nlet x = 1\n```\nSay `now` softly.")
        #expect(cleaned == "let x = 1\nSay now softly.")
    }

    @Test func stripsHorizontalRules() {
        #expect(MarkdownTextCleaner.plainText(from: "one\n---\ntwo") == "one\ntwo")
    }

    /// An asterisk that is not emphasis must survive, or ordinary prose gets
    /// mangled.
    @Test func leavesLoneAsterisksAlone() {
        #expect(MarkdownTextCleaner.plainText(from: "2 * 3 = 6") == "2 * 3 = 6")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/MarkdownTextCleanerTests
```

Expected: FAIL — "cannot find 'MarkdownTextCleaner' in scope".

- [ ] **Step 3: Write the cleaner**

Create `Ilumionate/TextTrance/MarkdownTextCleaner.swift`:

```swift
//  MarkdownTextCleaner.swift
//  Ilumionate
//
//  Strips Markdown syntax from imported `.md` so the reader never presents a
//  syntax marker as a word. The ORP display shows one word at a time, which
//  makes a stray `##` or `**` far more visible than it would be in a page of
//  running text.

import Foundation

nonisolated enum MarkdownTextCleaner {

    static func plainText(from markdown: String) -> String {
        var text = markdown

        // Fenced code: drop the fence lines, keep the code as prose.
        text = replace(#"^\s*```[^\n]*$"#, in: text, options: [.anchorsMatchLines])
        // Horizontal rules, before list bullets — `---` would otherwise read as
        // a bullet with no content.
        text = replace(#"^\s*([-*_])\s*\1\s*\1[\s\1]*$"#, in: text, options: [.anchorsMatchLines])
        // Setext heading underlines.
        text = replace(#"^\s*=+\s*$"#, in: text, options: [.anchorsMatchLines])
        // ATX heading markers, keeping the heading text.
        text = replace(#"^\s*#{1,6}\s+"#, in: text, options: [.anchorsMatchLines])
        // Blockquote markers.
        text = replace(#"^\s*>\s?"#, in: text, options: [.anchorsMatchLines])
        // List bullets and ordered-list numbers.
        text = replace(#"^\s*[-*+]\s+"#, in: text, options: [.anchorsMatchLines])
        text = replace(#"^\s*\d+\.\s+"#, in: text, options: [.anchorsMatchLines])
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
```

- [ ] **Step 4: Run the cleaner tests to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/MarkdownTextCleanerTests
```

Expected: PASS, 7 tests.

- [ ] **Step 5: Write the failing integration test**

Append to `ReadingDocumentImporterTests`:

```swift
    @Test func cleansMarkdownSyntaxOnImport() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Session.md")
        try Data("""
        # Deep Rest

        You feel **calm** and _steady_ as the whole room grows quiet.
        """.utf8).write(to: url)

        let extracted = try ReadingDocumentImporter.extract(from: url)

        #expect(extracted.kind == .text)
        #expect(extracted.text.contains("**") == false)
        #expect(extracted.text.contains("#") == false)
        #expect(extracted.text.contains("You feel calm and steady as the whole room grows quiet."))
    }

    /// `.txt` is passed through untouched — an asterisk in a plain text file is
    /// an asterisk, not emphasis.
    @Test func leavesPlainTextSyntaxUntouched() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Literal.txt")
        try Data("Multiply 2 * 3 and note the **stars** stay exactly where they are.".utf8)
            .write(to: url)

        let extracted = try ReadingDocumentImporter.extract(from: url)

        #expect(extracted.text.contains("**stars**"))
    }
```

- [ ] **Step 6: Run it to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReadingDocumentImporterTests
```

Expected: FAIL on `cleansMarkdownSyntaxOnImport` — the `#` survives.

- [ ] **Step 7: Route Markdown through the cleaner**

In `ReadingDocumentImporter.extractPlainText`, replace the line building `text`:

```swift
        let isMarkdown = ["md", "markdown"].contains(url.pathExtension.lowercased())
        let cleaned = isMarkdown ? MarkdownTextCleaner.plainText(from: raw) : raw
        let text = ReaderDocumentHTMLExtractor.normalizeText(cleaned)
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReadingDocumentImporterTests
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Ilumionate/TextTrance/MarkdownTextCleaner.swift Ilumionate/TextTrance/ReadingDocumentImporter.swift IlumionateTests/TextTrance/MarkdownTextCleanerTests.swift IlumionateTests/TextTrance/ReadingDocumentImporterTests.swift
git commit -m "feat: strip markdown syntax from imported .md scripts"
```

---

## Task 3: Oversized text files are refused

`extractPlainText` reads the whole file and runs several full-string regex passes over it. An unbounded read is a memory cliff, so the size is checked before the read.

**Files:**
- Modify: `Ilumionate/TextTrance/ReadingDocumentImporter.swift`
- Test: `IlumionateTests/TextTrance/ReadingDocumentImporterTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ReadingDocumentImporterTests`:

```swift
    @Test func refusesOversizedPlainText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Huge.txt")
        let sentence = "the quiet settles over everything around you now and again "
        let repeats = (ReadingDocumentImporter.maximumPlainTextByteCount / sentence.utf8.count) + 2
        try Data(String(repeating: sentence, count: repeats).utf8).write(to: url)

        #expect(throws: ReadingDocumentImportError.textFileTooLarge) {
            try ReadingDocumentImporter.extract(from: url)
        }
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReadingDocumentImporterTests
```

Expected: FAIL — `maximumPlainTextByteCount` and `textFileTooLarge` do not exist.

- [ ] **Step 3: Add the error case and the cap**

In `ReadingDocumentImportError`, add the case and its message:

```swift
    case textFileTooLarge
```

```swift
        case .textFileTooLarge:
            return "This text file is too large to import."
```

In `ReadingDocumentImporter`, add the constant and check it before reading:

```swift
    /// Roughly 1.3 million words — far past any plausible reader session, and
    /// the point at which the full-string regex passes in extraction become a
    /// memory concern rather than a cost.
    nonisolated static let maximumPlainTextByteCount = 8 * 1024 * 1024
```

At the top of `extractPlainText(from:)`, before `Data(contentsOf:)`:

```swift
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        if let fileSize, fileSize > maximumPlainTextByteCount {
            throw ReadingDocumentImportError.textFileTooLarge
        }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReadingDocumentImporterTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/ReadingDocumentImporter.swift IlumionateTests/TextTrance/ReadingDocumentImporterTests.swift
git commit -m "fix: refuse plain text imports above 8MB"
```

---

## Task 4: The store reports whether an import replaced an existing document

`ReadingDocumentImportWorker.prepare` silently replaces any document matching content hash **or** filename, and has no "already in library" signal. The cable path needs that signal to report a duplicate honestly. The existing `importDocument` signature is kept so its four call sites stay untouched.

**Files:**
- Modify: `Ilumionate/TextTrance/ReadingDocumentStore.swift:44-58`
- Test: `IlumionateTests/TextTrance/ReadingDocumentImporterTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `ReadingDocumentImporterTests`:

```swift
    @MainActor
    @Test func reportsWhenAnImportReplacesAnExistingDocument() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ReadingDocumentStore(
            directoryURL: directory.appending(path: "Documents", directoryHint: .isDirectory)
        )
        let url = directory.appending(path: "Script.txt")
        try Data("Let your shoulders drop and your breathing slow right down now.".utf8)
            .write(to: url)

        let first = try await store.importDocumentReportingReplacement(from: url)
        #expect(first.replacedExisting == false)

        let second = try await store.importDocumentReportingReplacement(from: url)
        #expect(second.replacedExisting)
        #expect(store.documents.count == 1)
    }
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReadingDocumentImporterTests
```

Expected: FAIL — no `importDocumentReportingReplacement`.

- [ ] **Step 3: Add the outcome type and the reporting method**

In `ReadingDocumentStore.swift`, above the class:

```swift
struct ReadingDocumentImportOutcome: Sendable {
    let document: ReadingDocument
    /// True when this import superseded a document already in the library,
    /// matched by content hash or original filename.
    let replacedExisting: Bool
}
```

Replace the existing `importDocument(from:originalFilename:)` with these two:

```swift
    func importDocument(from url: URL, originalFilename: String? = nil) async throws -> ReadingDocument {
        try await importDocumentReportingReplacement(
            from: url,
            originalFilename: originalFilename
        ).document
    }

    func importDocumentReportingReplacement(
        from url: URL,
        originalFilename: String? = nil
    ) async throws -> ReadingDocumentImportOutcome {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }

        let prepared = try await ReadingDocumentImportWorker.prepare(
            sourceURL: url,
            originalFilename: originalFilename,
            textDirectoryURL: textDirectoryURL,
            existingDocuments: documents
        )
        documents.removeAll { prepared.replacedDocumentIDs.contains($0.id) }
        documents.insert(prepared.document, at: 0)
        documents.sort { $0.importedAt > $1.importedAt }
        try persist()
        return ReadingDocumentImportOutcome(
            document: prepared.document,
            replacedExisting: prepared.replacedDocumentIDs.isEmpty == false
        )
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReadingDocumentImporterTests
```

Expected: PASS, with the two pre-existing store tests still green.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/TextTrance/ReadingDocumentStore.swift IlumionateTests/TextTrance/ReadingDocumentImporterTests.swift
git commit -m "feat: reading document store reports replaced imports"
```

---

## Task 5: Rename the cable intake to reflect what it now handles

Pure rename, no behavior change. Done **before** the routing work so later tasks are written once under the final names.

**Files:**
- Rename: `Ilumionate/CableAudioImportService.swift` → `Ilumionate/CableFileImportService.swift`
- Rename: `Ilumionate/CableAudioImportResult.swift` → `Ilumionate/CableFileImportResult.swift`
- Rename: `Ilumionate/CableAudioImportModel.swift` → `Ilumionate/CableFileImportModel.swift`
- Rename: `IlumionateTests/CableAudioImportTests.swift` → `IlumionateTests/CableFileImportTests.swift`
- Rename: `IlumionateTests/CableAudioRootInboxTests.swift` → `IlumionateTests/CableFileRootInboxTests.swift`
- Rename: `IlumionateTests/CableAudioImportModelTests.swift` → `IlumionateTests/CableFileImportModelTests.swift`
- Modify: `Ilumionate/ContentView.swift:41`

- [ ] **Step 1: Confirm the suite is green before touching anything**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableAudioImportTests -only-testing:IlumionateTests/CableAudioRootInboxTests -only-testing:IlumionateTests/CableAudioImportModelTests
```

Expected: PASS. If this is red before you start, stop and report it — do not rename over a failing suite.

- [ ] **Step 2: Rename the files**

```bash
git mv Ilumionate/CableAudioImportService.swift Ilumionate/CableFileImportService.swift
git mv Ilumionate/CableAudioImportResult.swift Ilumionate/CableFileImportResult.swift
git mv Ilumionate/CableAudioImportModel.swift Ilumionate/CableFileImportModel.swift
git mv IlumionateTests/CableAudioImportTests.swift IlumionateTests/CableFileImportTests.swift
git mv IlumionateTests/CableAudioRootInboxTests.swift IlumionateTests/CableFileRootInboxTests.swift
git mv IlumionateTests/CableAudioImportModelTests.swift IlumionateTests/CableFileImportModelTests.swift
```

- [ ] **Step 3: Rename the symbols**

```bash
grep -rl "CableAudioImport\|CableAudioScan" Ilumionate IlumionateTests --include="*.swift" \
  | xargs sed -i '' \
    -e 's/CableAudioImportService/CableFileImportService/g' \
    -e 's/CableAudioImportResult/CableFileImportResult/g' \
    -e 's/CableAudioImportFailure/CableFileImportFailure/g' \
    -e 's/CableAudioImportModel/CableFileImportModel/g' \
    -e 's/CableAudioImportTests/CableFileImportTests/g' \
    -e 's/CableAudioRootInboxTests/CableFileRootInboxTests/g' \
    -e 's/CableAudioImportModelTests/CableFileImportModelTests/g' \
    -e 's/CableAudioImportTitleTests/CableFileImportTitleTests/g' \
    -e 's/CableAudioScan/CableFileScan/g'
```

Then update the file-header comments inside the three renamed source files and three renamed test files, which still say the old filename.

- [ ] **Step 4: Update the Xcode project references**

The renamed files must point at the new paths in `Ilumionate.xcodeproj/project.pbxproj`. Open the project in Xcode, confirm no file shows in red, and that each renamed file still has the correct target membership (`Ilumionate` for sources, `IlumionateTests` for tests).

- [ ] **Step 5: Build and run the suite to verify the rename changed nothing**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableFileImportTests -only-testing:IlumionateTests/CableFileRootInboxTests -only-testing:IlumionateTests/CableFileImportModelTests
```

Expected: PASS, with the same test count as Step 1.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename cable audio intake to cable file intake"
```

---

## Task 6: Storage paths for the text inbox and the imported archive

**Files:**
- Modify: `Ilumionate/AppStoragePaths.swift`
- Modify: `Ilumionate/CableFileImportService.swift` (`excludedRootDirectoryNames`)
- Test: `IlumionateTests/CableFileRootInboxTests.swift`

- [ ] **Step 1: Write the failing test**

This is the regression test for the infinite-rescan bug. The fixture in this file
is `RootInboxFixture`, whose `rootInboxURL` stands in for the Documents root.
Append to `CableFileRootInboxTests`:

```swift
    @Test("App-owned intake directories are never descended into")
    func skipsOwnIntakeDirectories() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        for directory in ["_Imported", "_Needs Review", "Incoming Text"] {
            let nested = fixture.rootInboxURL.appending(path: directory, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try fixture.validMP3Data.write(to: nested.appending(path: "Already Handled.mp3"))
        }

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.isEmpty)
        #expect(result.duplicates.isEmpty)
        #expect(result.rejected.isEmpty)
        for directory in ["_Imported", "_Needs Review", "Incoming Text"] {
            #expect(FileManager.default.fileExists(
                atPath: fixture.rootInboxURL
                    .appending(path: "\(directory)/Already Handled.mp3")
                    .path
            ))
        }
    }
```


- [ ] **Step 2: Run it to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableFileRootInboxTests
```

Expected: FAIL — the file in `_Imported/` and `Incoming Text/` is imported, because neither name is excluded.

- [ ] **Step 3: Add the paths**

In `AppStoragePaths.swift`, after `cableDedicatedInbox`:

```swift
    /// Text and document counterpart to `cableDedicatedInbox`. Both dedicated
    /// inboxes accept either kind — classification is by file, not by folder —
    /// so a misfiled drop still imports. The second folder exists to make the
    /// capability discoverable in the Files app, not to partition it.
    static let cableTextInbox = URL.documentsDirectory
        .appending(path: "Incoming Text", directoryHint: .isDirectory)

    /// Where a successfully imported document's source file is kept.
    ///
    /// The reader stores only extracted text, so the dropped file is the user's
    /// only copy. Audio can be moved into private managed storage because the
    /// library still addresses it; a document has nothing addressing it, so it
    /// stays visible and recoverable here instead.
    static let cableImported = URL.documentsDirectory
        .appending(path: "_Imported", directoryHint: .isDirectory)
```

Correct the stale comment on `cableRootInbox` — the code uses a recursive `FileManager.enumerator` with name-based exclusion, not a flat scan. Replace the second paragraph of its doc comment:

```swift
    /// The root is shared space: `TrainingCorpus/`, `TrainingOutput/`, the
    /// review folder and the imported archive all live here. It is walked
    /// recursively — dragging twenty files usually means dragging the folder
    /// holding them — with app-owned directories excluded by name, and
    /// unrecognised files left untouched.
```

- [ ] **Step 4: Exclude both directories from the walk**

In `CableFileImportService.swift`, add to `appOwnedDirectoryNames`:

```swift
    private static let appOwnedDirectoryNames: Set<String> = [
        "TrainingCorpus",
        "TrainingOutput",
        "GeneratedSessions",
        "Inbox",            // iOS places externally-opened documents here
        "_Imported"         // this service's own output; descending re-imports it forever
    ]
```

Add an `importedURL` stored property, an init parameter, and include it plus the text inbox in the exclusion set. In the initializer signature add:

```swift
        textInboxURL: URL? = AppStoragePaths.cableTextInbox,
        importedURL: URL = AppStoragePaths.cableImported,
```

with matching stored properties and assignments, and extend the exclusion set:

```swift
    private var excludedRootDirectoryNames: Set<String> {
        var names = Self.appOwnedDirectoryNames
        names.insert(reviewURL.lastPathComponent)
        names.insert(importedURL.lastPathComponent)
        // Each dedicated inbox is walked as its own source, with its own
        // rejection policy. Descending into one from the root would relabel it.
        if let dedicatedInboxURL {
            names.insert(dedicatedInboxURL.lastPathComponent)
        }
        if let textInboxURL {
            names.insert(textInboxURL.lastPathComponent)
        }
        return names
    }
```

Extend `snapshots()` to walk the text inbox as a second `.dedicated` source:

```swift
    private func snapshots() throws -> [URL: CableFileSnapshot] {
        var found = try snapshots(
            in: rootInboxURL,
            source: .root,
            excluding: excludedRootDirectoryNames
        )
        for inbox in [dedicatedInboxURL, textInboxURL].compactMap({ $0 }) {
            let nested = try snapshots(
                in: inbox,
                source: .dedicated,
                excluding: [reviewURL.lastPathComponent, importedURL.lastPathComponent]
            )
            found.merge(nested) { current, _ in current }
        }
        return found
    }
```

And create both new directories in `prepareDirectories()`:

```swift
        if let textInboxURL {
            try FileManager.default.createDirectory(
                at: textInboxURL,
                withIntermediateDirectories: true
            )
        }
```

- [ ] **Step 5: Update the test fixtures to pass the new URLs**

In both `CableFileImportTests` and `CableFileRootInboxTests` fixtures, add `textInboxURL` and `importedURL` pointing inside the fixture's temporary root, and pass them to `makeService()`. For `CableImportFixture`:

```swift
    let textInboxURL: URL
    let importedURL: URL
```

```swift
        textInboxURL = rootURL.appending(path: "Incoming Text", directoryHint: .isDirectory)
        importedURL = rootIntakeURL.appending(path: "_Imported", directoryHint: .isDirectory)
```

```swift
        try FileManager.default.createDirectory(at: textInboxURL, withIntermediateDirectories: true)
```

and in `makeService()`:

```swift
            textInboxURL: textInboxURL,
            importedURL: importedURL,
```

`importedURL` sits **inside** `rootIntakeURL` so the exclusion test exercises the real arrangement: the archive lives under the scanned root.

Apply the same additions to `RootInboxFixture` in `CableFileRootInboxTests.swift`, where the scanned root is `rootInboxURL`:

```swift
    let textInboxURL: URL
    let importedURL: URL
```

```swift
        textInboxURL = rootInboxURL.appending(path: "Incoming Text", directoryHint: .isDirectory)
        importedURL = rootInboxURL.appending(path: "_Imported", directoryHint: .isDirectory)
```

Add `textInboxURL` to the existing directory-creation loop:

```swift
        for url in [rootInboxURL, dedicatedInboxURL, textInboxURL, managedAudioURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
```

and pass both into `makeService(minimumSettleAge:)`:

```swift
            textInboxURL: textInboxURL,
            importedURL: importedURL,
```

- [ ] **Step 6: Run the cable suites to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableFileImportTests -only-testing:IlumionateTests/CableFileRootInboxTests
```

Expected: PASS, including the new exclusion test.

- [ ] **Step 7: Commit**

```bash
git add Ilumionate/AppStoragePaths.swift Ilumionate/CableFileImportService.swift IlumionateTests/CableFileImportTests.swift IlumionateTests/CableFileRootInboxTests.swift
git commit -m "feat: add text inbox and imported archive to cable intake paths"
```

---

## Task 7: Classify a settled file by kind

**Files:**
- Create: `Ilumionate/CableInboxFileKind.swift`
- Test: `IlumionateTests/CableInboxFileKindTests.swift`

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/CableInboxFileKindTests.swift`:

```swift
//  CableInboxFileKindTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

struct CableInboxFileKindTests {

    @Test func classifiesAudioExtensions() {
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Session.mp3")) == .audio)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Session.m4a")) == .audio)
    }

    @Test func classifiesReaderDocumentExtensions() {
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Script.txt")) == .readerDocument)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Script.md")) == .readerDocument)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Book.pdf")) == .readerDocument)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Book.epub")) == .readerDocument)
    }

    @Test func classifiesAnythingElseAsUnrecognized() {
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/photo.heic")) == .unrecognized)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/README")) == .unrecognized)
    }

    @Test func ignoresExtensionCasing() {
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Book.PDF")) == .readerDocument)
        #expect(CableInboxFileKind(url: URL(filePath: "/tmp/Session.MP3")) == .audio)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableInboxFileKindTests
```

Expected: FAIL — "cannot find 'CableInboxFileKind' in scope".

- [ ] **Step 3: Write the classifier**

Create `Ilumionate/CableInboxFileKind.swift`:

```swift
//
//  CableInboxFileKind.swift
//  Ilumionate
//

import Foundation

/// What a settled inbox file is, and therefore which subsystem may admit it.
///
/// Classification is by extension alone. Content validation is deliberately
/// left to the admitting step, which already does it and can explain a failure
/// in its own terms: audio checks its magic bytes, and a document that is
/// really binary fails extraction and is filed as invalid.
nonisolated enum CableInboxFileKind: Sendable, Equatable {
    case audio
    case readerDocument
    case unrecognized

    init(url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        if AudioDownloadValidation.audioExtensions.contains(fileExtension) {
            self = .audio
        } else if ReadingDocumentImporter.supportedFileExtensions.contains(fileExtension) {
            self = .readerDocument
        } else {
            self = .unrecognized
        }
    }
}
```

Add the file to the `Ilumionate` target and the test file to `IlumionateTests`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableInboxFileKindTests
```

Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/CableInboxFileKind.swift IlumionateTests/CableInboxFileKindTests.swift
git commit -m "feat: classify cable inbox files by kind"
```

---

## Task 8: Admit one reader document

**Files:**
- Create: `Ilumionate/ReaderInboxAdmission.swift`
- Test: `IlumionateTests/ReaderInboxAdmissionTests.swift`

The rule this encodes: a **content** problem is a rejection (needs a human, move it to `_Needs Review`); an **I/O or store** problem is a failure (leave the file, retry next scan).

- [ ] **Step 1: Write the failing test**

Create `IlumionateTests/ReaderInboxAdmissionTests.swift`:

```swift
//  ReaderInboxAdmissionTests.swift
//  IlumionateTests

import Foundation
import Testing
@testable import Ilumionate

private struct StubStoreError: Error {}

@MainActor
struct ReaderInboxAdmissionTests {

    private func document(_ name: String) -> ReadingDocument {
        ReadingDocument(
            id: UUID().uuidString,
            title: name,
            kind: .text,
            originalFilename: "\(name).txt",
            importedAt: .now,
            wordCount: 12,
            characterCount: 60,
            contentHash: "hash-\(name)",
            textFilename: "\(name).txt"
        )
    }

    @Test func reportsAFreshImport() async {
        let expected = document("Evening")
        let admission = ReaderInboxAdmission { _, _ in
            ReadingDocumentImportOutcome(document: expected, replacedExisting: false)
        }

        let outcome = await admission.admit(URL(filePath: "/tmp/Evening.txt"))

        #expect(outcome == .imported(expected))
    }

    @Test func reportsAReplacementAsADuplicate() async {
        let admission = ReaderInboxAdmission { _, _ in
            ReadingDocumentImportOutcome(document: self.document("Evening"), replacedExisting: true)
        }

        let outcome = await admission.admit(URL(filePath: "/tmp/Evening.txt"))

        #expect(outcome == .duplicate)
    }

    /// A content problem needs a human, so it is filed rather than retried.
    @Test func reportsAContentProblemAsARejection() async {
        let admission = ReaderInboxAdmission { _, _ in
            throw ReadingDocumentImportError.noReadableText
        }

        let outcome = await admission.admit(URL(filePath: "/tmp/Empty.txt"))

        #expect(outcome == .rejected)
    }

    /// A store or disk problem may well succeed next time, so the file stays.
    @Test func reportsAStoreProblemAsAFailure() async {
        let admission = ReaderInboxAdmission { _, _ in
            throw StubStoreError()
        }

        let outcome = await admission.admit(URL(filePath: "/tmp/Evening.txt"))

        guard case .failed = outcome else {
            Issue.record("Expected a failure, got \(outcome)")
            return
        }
    }

    @Test func passesTheOriginalFilenameThrough() async {
        let captured = Capture()
        let admission = ReaderInboxAdmission { url, originalFilename in
            captured.filename = originalFilename
            return ReadingDocumentImportOutcome(
                document: self.document("Evening"),
                replacedExisting: false
            )
        }

        _ = await admission.admit(URL(filePath: "/tmp/Evening Script.txt"))

        #expect(captured.filename == "Evening Script.txt")
    }

    @MainActor
    private final class Capture {
        var filename: String?
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReaderInboxAdmissionTests
```

Expected: FAIL — "cannot find 'ReaderInboxAdmission' in scope".

- [ ] **Step 3: Write the admission**

Create `Ilumionate/ReaderInboxAdmission.swift`:

```swift
//
//  ReaderInboxAdmission.swift
//  Ilumionate
//

import Foundation

/// The result of offering one inbox file to the reader library.
nonisolated enum ReaderInboxOutcome: Sendable, Equatable {
    case imported(ReadingDocument)
    /// The document was already in the library, matched by content or filename.
    case duplicate
    /// The file cannot be read as a document. Retrying would produce the same
    /// answer, so it belongs in `_Needs Review` rather than in the inbox.
    case rejected
    /// The store or the disk failed. This may succeed on the next scan, so the
    /// file is left where it was found.
    case failed(String)
}

/// Admits a single reader document, isolating the main-actor hop to
/// `ReadingDocumentStore` behind an injectable closure so the cable service can
/// be tested without a real store.
nonisolated struct ReaderInboxAdmission: Sendable {
    typealias Importer = @MainActor @Sendable (URL, String?) async throws -> ReadingDocumentImportOutcome

    private let importDocument: Importer

    init(importDocument: @escaping Importer = { url, originalFilename in
        try await ReadingDocumentStore.shared.importDocumentReportingReplacement(
            from: url,
            originalFilename: originalFilename
        )
    }) {
        self.importDocument = importDocument
    }

    func admit(_ url: URL) async -> ReaderInboxOutcome {
        do {
            let outcome = try await importDocument(url, url.lastPathComponent)
            return outcome.replacedExisting ? .duplicate : .imported(outcome.document)
        } catch is ReadingDocumentImportError {
            // Every case of this error describes the file's *content*. None of
            // them get better by trying again.
            return .rejected
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/ReaderInboxAdmissionTests
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Ilumionate/ReaderInboxAdmission.swift IlumionateTests/ReaderInboxAdmissionTests.swift
git commit -m "feat: admit reader documents from the cable inbox"
```

---

## Task 9: The result carries imported documents

**Files:**
- Modify: `Ilumionate/CableFileImportResult.swift`
- Modify: `Ilumionate/CableFileImportModel.swift`
- Test: `IlumionateTests/CableFileImportModelTests.swift`

- [ ] **Step 1: Write the failing test**

In `CableFileImportModelTests.swift`, add to `CableFileImportTitleTests`:

```swift
    @Test("A mixed transfer names both kinds")
    func mixedTransferNamesBothKinds() {
        var result = CableFileImportResult()
        result.imported = [
            AudioFile(filename: "One.mp3", duration: 1, fileSize: 1),
            AudioFile(filename: "Two.mp3", duration: 1, fileSize: 1)
        ]
        result.importedDocuments = [makeDocument("Script")]

        #expect(result.title == "2 Audio Files, 1 Document Added")
        #expect(result.message.contains("1 document is ready in your Reader."))
    }

    @Test("A documents-only transfer never mentions audio")
    func documentOnlyTransferNeverMentionsAudio() {
        var result = CableFileImportResult()
        result.importedDocuments = [makeDocument("One"), makeDocument("Two")]

        #expect(result.title == "2 Documents Added")
        #expect(result.message.contains("Audio") == false)
    }

    /// An earlier scan cannot be asked which kind it admitted, so the
    /// prior-import wording generalises.
    @Test("An empty scan after imports is titled as success, not absence")
    func emptyResultAfterImportsIsTitledAsSuccess() {
        var result = CableFileImportResult()
        result.priorImportCount = 5

        #expect(result.title == "5 Files Added")
    }

    private func makeDocument(_ name: String) -> ReadingDocument {
        ReadingDocument(
            id: UUID().uuidString,
            title: name,
            kind: .text,
            originalFilename: "\(name).txt",
            importedAt: .now,
            wordCount: 12,
            characterCount: 60,
            contentHash: "hash-\(name)",
            textFilename: "\(name).txt"
        )
    }
```

Then update the three existing assertions whose copy generalises:

- `emptyResultAfterImportsIsTitledAsSuccess` — replaced by the version above; delete the old one.
- `singleEarlierImportIsSingular`: `"1 Audio File Added"` → `"1 File Added"`.
- `trulyEmptyResultKeepsTheAbsenceTitle`: `"No New Audio Found"` → `"No New Files Found"`.
- In `CableFileImportModelTests` line ~53: `"No New Audio Found"` → `"No New Files Found"`.

`freshImportsAreCountedInTheTitle` keeps `"2 Audio Files Added"` unchanged — an audio-only scan must still read exactly as it does today.

- [ ] **Step 2: Run it to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableFileImportModelTests
```

Expected: FAIL — no `importedDocuments` member.

- [ ] **Step 3: Extend the result**

In `CableFileImportResult.swift`, add the property and merge it:

```swift
    var importedDocuments: [ReadingDocument] = []
```

```swift
        importedDocuments.append(contentsOf: other.importedDocuments)
```

Extend `hasActivity`:

```swift
    var hasActivity: Bool {
        imported.isEmpty == false
            || importedDocuments.isEmpty == false
            || duplicates.isEmpty == false
            || rejected.isEmpty == false
            || pending.isEmpty == false
            || failures.isEmpty == false
    }
```

Replace `addedCount` and `title`:

```swift
    private var addedCount: Int {
        imported.count + importedDocuments.count + priorImportCount
    }

    var title: String {
        // The title is what a user acts on. "No New Files Found" above a body
        // explaining that five files just landed reads as failure.
        if addedCount > 0, failures.isEmpty {
            var parts: [String] = []
            if imported.isEmpty == false {
                let subject = noun(imported.count, singular: "Audio File", plural: "Audio Files")
                parts.append("\(imported.count) \(subject)")
            }
            if importedDocuments.isEmpty == false {
                let subject = noun(importedDocuments.count, singular: "Document", plural: "Documents")
                parts.append("\(importedDocuments.count) \(subject)")
            }
            // Only an earlier scan contributed, and it cannot be asked which
            // kind it admitted — so the wording generalises rather than guesses.
            if parts.isEmpty {
                let subject = noun(priorImportCount, singular: "File", plural: "Files")
                parts.append("\(priorImportCount) \(subject)")
            }
            return "\(parts.joined(separator: ", ")) Added"
        }
        if failures.isEmpty == false {
            return "File Transfer Failed"
        }
        if duplicates.isEmpty == false || rejected.isEmpty == false {
            return "File Transfer Needs Review"
        }
        if pending.isEmpty == false {
            return "File Transfer in Progress"
        }
        return "No New Files Found"
    }
```

In `message`, add the document line directly after the audio line:

```swift
        if importedDocuments.isEmpty == false {
            let subject = noun(
                importedDocuments.count,
                singular: "document is",
                plural: "documents are"
            )
            lines.append("\(importedDocuments.count) \(subject) ready in your Reader.")
        }
```

And update the empty-inbox guidance, which currently names only audio:

```swift
                lines.append("Connect your iPhone, open Finder, select it, and drag audio or documents onto LumeSync in the Files tab. Then check again.")
```

- [ ] **Step 4: Count documents in the session total**

In `CableFileImportModel.scan(manual:)`, replace the session accounting so a document import also counts:

```swift
        importsThisSession += aggregate.imported.count + aggregate.importedDocuments.count
        aggregate.priorImportCount = importsThisSession
            - aggregate.imported.count
            - aggregate.importedDocuments.count

        if aggregate.imported.isEmpty == false {
            await refreshLibrary()
        }
```

`refreshLibrary` stays gated on audio only — it refreshes `AudioLibraryCache`, and `ReadingDocumentStore` is `@Observable` and already mutated, so the Read tab updates itself.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableFileImportModelTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Ilumionate/CableFileImportResult.swift Ilumionate/CableFileImportModel.swift IlumionateTests/CableFileImportModelTests.swift
git commit -m "feat: cable import result reports imported documents"
```

---

## Task 10: Route reader documents through the scan

The task everything else was building toward.

**Files:**
- Modify: `Ilumionate/CableFileImportService.swift`
- Test: `IlumionateTests/CableFileImportTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `CableFileImportTests`:

```swift
    @Test("A dropped text file is admitted to the reader and its source archived")
    func importsTextDropIntoTheReader() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.inboxURL.appending(path: "Evening Script.txt")
        try Data("Let your shoulders drop and your breathing slow right down now.".utf8)
            .write(to: sourceURL)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.importedDocuments.count == 1)
        #expect(result.imported.isEmpty)
        #expect(result.failures.isEmpty)
        #expect(result.importedDocuments.first?.originalFilename == "Evening Script.txt")
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
        #expect(FileManager.default.fileExists(
            atPath: fixture.importedURL.appending(path: "Evening Script.txt").path
        ))
    }

    @Test("Audio and text in one drop are admitted in a single scan")
    func importsMixedDropInOnePass() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        try fixture.validMP3Data.write(to: fixture.inboxURL.appending(path: "Session.mp3"))
        try Data("Let your shoulders drop and your breathing slow right down now.".utf8)
            .write(to: fixture.inboxURL.appending(path: "Script.txt"))

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.count == 1)
        #expect(result.importedDocuments.count == 1)
        #expect(result.failures.isEmpty)
    }

    /// Both dedicated inboxes accept either kind — classification is by file,
    /// not by folder — so a misfiled drop still imports.
    @Test("Text dropped in the audio inbox still imports")
    func admitsTextFromTheAudioInbox() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        try Data("Let your shoulders drop and your breathing slow right down now.".utf8)
            .write(to: fixture.inboxURL.appending(path: "Misfiled.txt"))

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.importedDocuments.count == 1)
        #expect(result.rejected.isEmpty)
    }

    @Test("Audio dropped in the text inbox still imports")
    func admitsAudioFromTheTextInbox() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        try fixture.validMP3Data.write(to: fixture.textInboxURL.appending(path: "Misfiled.mp3"))

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.imported.count == 1)
        #expect(result.rejected.isEmpty)
    }

    @Test("A re-dropped document is filed as a duplicate, not announced again")
    func filesRedroppedDocumentAsDuplicate() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        let text = Data("Let your shoulders drop and your breathing slow right down now.".utf8)
        let sourceURL = fixture.inboxURL.appending(path: "Script.txt")
        try text.write(to: sourceURL)
        let service = fixture.makeService()
        _ = await service.importAvailableFiles()

        try text.write(to: sourceURL)
        let second = await service.importAvailableFiles()

        #expect(second.importedDocuments.isEmpty)
        #expect(second.duplicates == ["Script.txt"])
        #expect(FileManager.default.fileExists(
            atPath: fixture.inboxURL.appending(path: "_Needs Review/Duplicates/Script.txt").path
        ))
    }

    @Test("A text file with nothing readable in it is filed as invalid")
    func filesUnreadableDocumentAsInvalid() async throws {
        let fixture = try CableImportFixture()
        defer { fixture.remove() }

        try Data("Too short.".utf8).write(to: fixture.inboxURL.appending(path: "Stub.txt"))

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.importedDocuments.isEmpty)
        #expect(result.rejected == ["Stub.txt"])
        #expect(FileManager.default.fileExists(
            atPath: fixture.inboxURL.appending(path: "_Needs Review/Invalid Documents/Stub.txt").path
        ))
    }
```

The fixture needs a real reader store rather than the shared singleton. Add to `CableImportFixture`:

```swift
    let documentStore: ReadingDocumentStore
    let importedURL: URL
```

initialised on the main actor — mark the fixture `init` `@MainActor` and add:

```swift
        documentStore = ReadingDocumentStore(
            directoryURL: rootURL.appending(path: "Reader", directoryHint: .isDirectory)
        )
```

and pass an admission into `makeService()`:

```swift
            readerAdmission: ReaderInboxAdmission { [documentStore] url, originalFilename in
                try await documentStore.importDocumentReportingReplacement(
                    from: url,
                    originalFilename: originalFilename
                )
            },
```

Because the fixture is now `@MainActor`, mark each new test `@MainActor` too, or mark the whole `CableFileImportTests` struct `@MainActor`. Prefer the struct-level annotation so existing tests are not individually edited.

- [ ] **Step 2: Run it to verify it fails**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableFileImportTests
```

Expected: FAIL — no `readerAdmission` parameter, no `importedDocuments`.

- [ ] **Step 3: Add the admission and the archive move**

In `CableFileImportService`, add the stored property, the init parameter (default `ReaderInboxAdmission()`), and these two methods:

```swift
    /// Moves a successfully imported document's source out of the inbox and
    /// into the visible archive. Called *after* the store has the text, so a
    /// failure here leaves a file the next scan re-imports idempotently rather
    /// than one that is lost.
    private func archiveImported(_ sourceURL: URL) throws {
        try FileManager.default.createDirectory(
            at: importedURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(
            at: sourceURL,
            to: uniqueURL(for: sourceURL.lastPathComponent, in: importedURL)
        )
    }

    private func admitReaderDocument(
        at sourceURL: URL
    ) async -> (document: ReadingDocument?, failure: CableFileImportFailure?, rejected: Bool, duplicate: Bool) {
        switch await readerAdmission.admit(sourceURL) {
        case .imported(let document):
            do {
                try archiveImported(sourceURL)
                return (document, nil, false, false)
            } catch {
                return (document, CableFileImportFailure(
                    filename: sourceURL.lastPathComponent,
                    message: "Imported, but the file could not be moved to _Imported: \(error.localizedDescription)"
                ), false, false)
            }
        case .duplicate:
            return (nil, nil, false, true)
        case .rejected:
            return (nil, nil, true, false)
        case .failed(let message):
            return (nil, CableFileImportFailure(
                filename: sourceURL.lastPathComponent,
                message: message
            ), false, false)
        }
    }
```

- [ ] **Step 4: Replace the audio-only gate with kind routing**

In `importAvailableFiles()`, replace the `guard AudioDownloadValidation.audioExtensions.contains(...)` block (and only that block — leave the `looksLikeAudio` guard and the audio `do` block below it exactly as they are) with:

```swift
                switch CableInboxFileKind(url: snapshot.url) {
                case .unrecognized:
                    // At the root this is somebody else's file, not a failed
                    // import. Moving it would be the bug.
                    if snapshot.source == .dedicated {
                        recordRejection(
                            snapshot.url,
                            category: "Unsupported Files",
                            result: &result
                        )
                    }
                    continue

                case .readerDocument:
                    let outcome = await admitReaderDocument(at: snapshot.url)
                    if let document = outcome.document {
                        result.importedDocuments.append(document)
                    }
                    if let failure = outcome.failure {
                        result.failures.append(failure)
                    }
                    if outcome.rejected {
                        recordRejection(
                            snapshot.url,
                            category: "Invalid Documents",
                            result: &result
                        )
                    }
                    if outcome.duplicate {
                        do {
                            try preserveForReview(snapshot.url, category: "Duplicates")
                            result.duplicates.append(snapshot.url.lastPathComponent)
                        } catch {
                            result.failures.append(CableFileImportFailure(
                                filename: snapshot.url.lastPathComponent,
                                message: error.localizedDescription
                            ))
                        }
                    }
                    continue

                case .audio:
                    break
                }
```

`continue` inside a `switch` inside the `for` loop continues the loop, which is what is wanted here.

- [ ] **Step 5: Cover the Documents root and the text inbox's rejection policy**

The tests above all drop into a dedicated inbox. The root is the transport Finder
actually uses, and it has a different policy for unrecognised files, so it needs
its own coverage. Append to `CableFileRootInboxTests`:

```swift
    @Test("A text file dropped at the Documents root reaches the reader")
    func admitsTextFromTheDocumentsRoot() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.rootInboxURL.appending(path: "Root Script.txt")
        try Data("Let your shoulders drop and your breathing slow right down now.".utf8)
            .write(to: sourceURL)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.importedDocuments.count == 1)
        #expect(result.rejected.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path) == false)
        #expect(FileManager.default.fileExists(
            atPath: fixture.importedURL.appending(path: "Root Script.txt").path
        ))
    }

    /// At the root an unrecognised file belongs to somebody else. Moving it
    /// would be the bug.
    @Test("An unrecognised file at the root is left alone, documents or not")
    func leavesUnrecognisedRootFilesAlone() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.rootInboxURL.appending(path: "notes.rtf")
        try Data("Some other app's file.".utf8).write(to: sourceURL)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.rejected.isEmpty)
        #expect(result.importedDocuments.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    /// The same file in a dedicated inbox genuinely is a failed import.
    @Test("An unrecognised file in the text inbox is filed for review")
    func filesUnrecognisedTextInboxFiles() async throws {
        let fixture = try RootInboxFixture()
        defer { fixture.remove() }

        let sourceURL = fixture.textInboxURL.appending(path: "notes.rtf")
        try Data("Not a supported document.".utf8).write(to: sourceURL)

        let result = await fixture.makeService().importAvailableFiles()

        #expect(result.rejected == ["notes.rtf"])
        #expect(FileManager.default.fileExists(
            atPath: fixture.reviewURL.appending(path: "Unsupported Files/notes.rtf").path
        ))
    }
```

`RootInboxFixture` needs the same reader store and admission as `CableImportFixture`. Mark its `init` `@MainActor`, add:

```swift
    let documentStore: ReadingDocumentStore
```

```swift
        documentStore = ReadingDocumentStore(
            directoryURL: containerURL.appending(path: "Reader", directoryHint: .isDirectory)
        )
```

and pass an admission into `makeService(minimumSettleAge:)`:

```swift
            readerAdmission: ReaderInboxAdmission { [documentStore] url, originalFilename in
                try await documentStore.importDocumentReportingReplacement(
                    from: url,
                    originalFilename: originalFilename
                )
            },
```

**The store must be fixture-scoped, not `ReadingDocumentStore.shared`** — the default admission writes into the real Application Support directory, so a test using it would pollute the developer's own reader library and leak state between runs.

Mark `CableFileRootInboxTests` `@MainActor` at the struct level, as in Task 10 Step 1.

- [ ] **Step 6: Run the cable suites to verify they pass**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests/CableFileImportTests -only-testing:IlumionateTests/CableFileRootInboxTests
```

Expected: PASS, with every pre-existing audio assertion still green.

- [ ] **Step 7: Commit**

```bash
git add Ilumionate/CableFileImportService.swift IlumionateTests/CableFileImportTests.swift IlumionateTests/CableFileRootInboxTests.swift
git commit -m "feat: route dropped documents into the reader library"
```

---

## Task 11: The alert offers to open the reader

**Files:**
- Modify: `Ilumionate/ContentView.swift:155-173`
- Modify: `Ilumionate/LibraryAddMenu.swift:21,55-65`
- Modify: `Ilumionate/LibraryView.swift:33,277`

- [ ] **Step 1: Update the alert**

In `ContentView.swift`, replace the cable alert's button block:

```swift
        .alert(
            cableImportAlertTitle,
            isPresented: showingCableImportResult
        ) {
            if cableImport.presentedResult?.imported.isEmpty == false {
                Button("Not Now", role: .cancel) {
                    cableImport.dismissResult()
                }
                Button("Analyze All") {
                    analyzeCableImports()
                }
            } else if cableImport.presentedResult?.importedDocuments.isEmpty == false {
                Button("Not Now", role: .cancel) {
                    cableImport.dismissResult()
                }
                Button("Open Reader") {
                    cableImport.dismissResult()
                    selectedTab = .read
                }
            } else {
                Button("OK", role: .cancel) {
                    cableImport.dismissResult()
                }
            }
        } message: {
            Text(cableImport.presentedResult?.message ?? "")
        }
```

A mixed drop offers **Analyze All**, because queueing analysis is the time-sensitive action; the documents are already in the reader and the message says so.

Update the fallback title on the same file:

```swift
    private var cableImportAlertTitle: String {
        cableImport.presentedResult?.title ?? "File Transfer"
    }
```

- [ ] **Step 2: Update the menu wording**

In `LibraryAddMenu.swift`, rename the property and its uses:

```swift
    let isCheckingIncomingFiles: Bool
```

```swift
        #if os(iOS) && !targetEnvironment(macCatalyst)
        Section("Cable Transfer") {
            Button(
                isCheckingIncomingFiles ? "Checking Incoming Files…" : "Check Incoming Files",
                systemImage: isCheckingIncomingFiles ? "hourglass" : "arrow.down.doc"
            ) {
                TranceHaptics.shared.light()
                onCheckIncomingFiles()
            }
            .disabled(isCheckingIncomingFiles)
        }
        #endif
```

Rename `onCheckIncomingAudio` to `onCheckIncomingFiles` in the same file, then update `LibraryView.swift:33` and `LibraryView.swift:277` and `ContentView.swift:244-247` to match:

```bash
grep -rn "isCheckingIncomingAudio\|onCheckIncomingAudio" Ilumionate --include="*.swift"
```

- [ ] **Step 3: Build both platforms**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,arch=arm64' build
```

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: BUILD SUCCEEDED for both.

- [ ] **Step 4: Commit**

```bash
git add Ilumionate/ContentView.swift Ilumionate/LibraryAddMenu.swift Ilumionate/LibraryView.swift
git commit -m "feat: cable transfer alert offers to open the reader"
```

---

## Task 12: Log the unbounded ePub read

Task 3 capped plain text. The ePub path has the same unbounded read and is **not** fixed here — capping it is a separate behavioral decision about which books to refuse.

**Files:**
- Modify: `ERRORS.md`

- [ ] **Step 1: Append the entry**

Follow the existing entry format in the file. Content:

```markdown
## ERR-0XX: ePub import reads the entire file into memory with no size cap

- **Date discovered:** 2026-08-28
- **Status:** identified

**Symptom:** Importing a very large ePub can spike memory enough to be jetsammed
on device. Not yet observed in the wild; found while adding a size cap to the
plain-text import path.

**Location:** `Ilumionate/TextTrance/ReadingDocumentImporter.swift`,
`extractEPUB(from:)` — `EPUBArchive(data: Data(contentsOf: url))`. `EPUBArchive`
then inflates each entry into memory in `data(forPath:)`.

**Reproduction:** Import an ePub of several hundred MB through the reader's file
importer, the share sheet, or the cable inbox.

**Root cause:** `Data(contentsOf:)` with no options reads the whole file. There is
no size check before the read and no streaming path.

**Proposed fix:** Check `URLResourceValues.fileSize` before reading, as
`extractPlainText` now does with `ReadingDocumentImporter.maximumPlainTextByteCount`,
and add an equivalent ePub cap. `Data(contentsOf:options: .mappedIfSafe)` would
reduce resident size for the archive read, though inflation still allocates.

**Risks:** Any cap refuses books that currently import successfully. The right
threshold needs a real measurement of memory against archive size rather than a
guessed number, which is why it is not being set here.

**Related:** Plain text is capped at 8 MB as of the reader file-drop ingestion
work; see `docs/superpowers/specs/2026-08-28-reader-file-drop-ingestion-design.md`.
```

Use the next free `ERR-0XX` number — check the file first:

```bash
grep -n "^## ERR-" ERRORS.md | tail -3
```

- [ ] **Step 2: Commit**

```bash
git add ERRORS.md
git commit -m "docs: log the unbounded epub read"
```

---

## Task 13: Full verification

- [ ] **Step 1: Run the whole shared suite on macOS**

```bash
Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' -only-testing:IlumionateTests
```

Expected: PASS. Note the total test count.

- [ ] **Step 2: Run the whole shared suite on the iOS Simulator**

```bash
Scripts/run-tests.sh -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:IlumionateTests
```

Expected: PASS, same count as Step 1.

- [ ] **Step 3: Build against the iOS 18 runtime**

A too-new SF Symbol renders blank with no build error, and `doc.text.fill` is the one symbol this work introduces. Build, then check it on device or simulator rather than trusting the compiler.

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Keep Mac Catalyst compiling**

```bash
xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Manual check on a real device**

The cable path is `#if os(iOS) && !targetEnvironment(macCatalyst)` and cannot be exercised by the simulator's Finder integration. On a physical iPhone:

1. Connect the device, open Finder, select it, open the Files tab.
2. Drag a folder containing one `.mp3`, one `.txt`, one `.md`, and one `.pdf` onto LumeSync.
3. Confirm the alert names both kinds, and that `doc.text.fill` renders in the reader library rather than showing blank.
4. Confirm the four source files are in `_Imported/` (documents) and gone (audio) via the Files app.
5. Tap Check Incoming Files again and confirm it reports nothing new rather than re-importing from `_Imported/`.

- [ ] **Step 6: Update plan.md**

Mark the feature done in `plan.md` only after Step 5 passes on device. "Compiles" is not done.

---

## Notes for the implementer

**If a step's code does not apply cleanly,** the file has drifted since this plan was written. Read the surrounding code, keep the plan's *intent*, and say in your report what differed.

**Do not touch the settle heuristic** in `importAvailableFiles()` — the two-snapshot comparison and the `minimumSettleAge` batch check. It is the reason large Finder drags succeed.

**Do not add a `registeredURLs` guard to the reader path.** That guard exists for audio because `AudioLibraryStore` rows address files by URL. Reader documents copy their text into Application Support and address nothing in the inbox.
