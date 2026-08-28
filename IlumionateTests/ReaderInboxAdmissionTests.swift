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
        let admission = ReaderInboxAdmission { _, originalFilename in
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
