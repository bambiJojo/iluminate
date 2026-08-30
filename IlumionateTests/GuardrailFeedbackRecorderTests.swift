//
//  GuardrailFeedbackRecorderTests.swift
//  IlumionateTests
//
//  Covers the half of the recorder that does not need a `LanguageModelSession`:
//  naming and writing. The `record` entry point is a thin wrapper that asks the
//  session for its attachment and calls `write`.
//

import Testing
import Foundation
@testable import Ilumionate

struct GuardrailFeedbackRecorderTests {

    private func temporaryDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "GuardrailFeedback-\(UUID().uuidString)")
    }

    @Test("The audio filename stays legible in the attachment name")
    func attachmentNameKeepsTheTrackRecognisable() {
        let name = GuardrailFeedbackRecorder.attachmentName(
            for: "Bambi Lobotomized 2 (Basic).mp3",
            at: Date(timeIntervalSince1970: 0)
        )

        #expect(name.hasPrefix("Bambi Lobotomized 2 _Basic_"))
        #expect(name.hasSuffix(".json"))
        // The extension is the attachment's, not the audio file's.
        #expect(name.contains(".mp3") == false)
    }

    @Test("Two refusals of one file do not overwrite each other")
    func repeatedRefusalsAreDistinctFiles() {
        let first = GuardrailFeedbackRecorder.attachmentName(
            for: "Umm....m4a",
            at: Date(timeIntervalSince1970: 0)
        )
        let second = GuardrailFeedbackRecorder.attachmentName(
            for: "Umm....m4a",
            at: Date(timeIntervalSince1970: 3600)
        )

        #expect(first != second)
    }

    @Test("The attachment is written into a directory that did not exist")
    func writeCreatesTheDirectory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("attachment".utf8)

        let written = try #require(
            GuardrailFeedbackRecorder.write(payload, filename: "Track.mp3", in: directory)
        )

        #expect(try Data(contentsOf: written) == payload)
    }

    /// A diagnostic must never be able to fail the analysis that produced it.
    /// The attachment embeds the prompt that was refused, which carries
    /// transcript excerpts. `UIFileSharingEnabled` exposes the Documents root to
    /// any USB-trusted host, so this must not live there. See ERRORS.md ERR-024.
    @Test("Attachments are stored outside the file-sharing-visible Documents root")
    func defaultDirectoryIsPrivate() {
        let directory = GuardrailFeedbackRecorder.directory.standardizedFileURL.path

        #expect(directory.hasPrefix(AppStoragePaths.supportRoot.standardizedFileURL.path))
        #expect(directory.hasPrefix(URL.documentsDirectory.standardizedFileURL.path) == false)
    }

    @Test("An unwritable destination reports nil rather than throwing")
    func writeFailureIsContained() {
        let blocked = URL(filePath: "/dev/null/cannot-exist")

        #expect(
            GuardrailFeedbackRecorder.write(Data("x".utf8), filename: "Track.mp3", in: blocked) == nil
        )
    }
}
