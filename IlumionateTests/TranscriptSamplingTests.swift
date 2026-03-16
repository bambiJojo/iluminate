//
//  TranscriptSamplingTests.swift
//  IlumionateTests
//
//  Tests for Step 1.5: four-point transcript sampling.
//  Verifies chunk size (600), sample count (4 headers), and edge cases.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Helpers

/// Extracts the section headers present in the sampled output.
private func headers(in sample: String) -> [String] {
    sample.components(separatedBy: "\n")
          .filter { $0.contains("---") }
          .map { $0.trimmingCharacters(in: .whitespaces) }
}

// MARK: - Tests

struct TranscriptSamplingTests {

    // MARK: Short transcript — returned verbatim

    @Test func shortTranscriptReturnedVerbatim() {
        // Under 800 chars → no sampling applied
        let text = String(repeating: "word ", count: 100) // ≈500 chars
        let result = AIAnalysisManager.sampleTranscript(text)
        #expect(result == text,
            "Transcripts ≤800 chars must be returned verbatim")
    }

    @Test func exactlyAtBoundaryReturnedVerbatim() {
        // 800 chars exactly → verbatim (guard requires > 800)
        let text = String(repeating: "x", count: 800)
        let result = AIAnalysisManager.sampleTranscript(text)
        #expect(result == text,
            "800-char transcript must be returned verbatim (boundary condition)")
    }

    // MARK: Long transcript — four sample points

    @Test func longTranscriptHasFourHeaders() {
        let text = String(repeating: "word ", count: 1000) // 5000 chars
        let result = AIAnalysisManager.sampleTranscript(text)
        let found = headers(in: result)
        #expect(found.count == 4,
            "Expected 4 section headers, got \(found.count): \(found)")
    }

    @Test func longTranscriptContainsOpeningHeader() {
        let text = String(repeating: "a", count: 2000)
        let result = AIAnalysisManager.sampleTranscript(text)
        #expect(result.contains("--- Opening ---"),
            "Sample must contain an Opening header")
    }

    @Test func longTranscriptContainsMidpointHeader() {
        let text = String(repeating: "a", count: 2000)
        let result = AIAnalysisManager.sampleTranscript(text)
        #expect(result.contains("--- Middle (50%) ---"),
            "Sample must contain a Middle (50%) header")
    }

    @Test func longTranscriptContainsLateHeader() {
        let text = String(repeating: "a", count: 2000)
        let result = AIAnalysisManager.sampleTranscript(text)
        #expect(result.contains("--- Late (75%) ---"),
            "Sample must contain a Late (75%) header")
    }

    @Test func longTranscriptContainsEndHeader() {
        let text = String(repeating: "a", count: 2000)
        let result = AIAnalysisManager.sampleTranscript(text)
        #expect(result.contains("--- End ---"),
            "Sample must contain an End header")
    }

    // MARK: Chunk size cap

    @Test func openingChunkDoesNotExceedSixHundredChars() {
        let prefix = String(repeating: "A", count: 800)
        let rest   = String(repeating: "B", count: 3200)
        let text   = prefix + rest

        let result = AIAnalysisManager.sampleTranscript(text)

        // Extract the Opening section
        guard let openingRange = result.range(of: "--- Opening ---\n") else {
            Issue.record("Opening header not found in sample")
            return
        }
        let afterHeader = result[openingRange.upperBound...]
        let openingContent: String
        if let nextSep = afterHeader.range(of: "\n\n---") {
            openingContent = String(afterHeader[..<nextSep.lowerBound])
        } else {
            openingContent = String(afterHeader)
        }

        #expect(openingContent.count <= 600,
            "Opening section must not exceed 600 chars, got \(openingContent.count)")
    }

    @Test func endChunkDoesNotExceedSixHundredChars() {
        let text = String(repeating: "z", count: 5000)
        let result = AIAnalysisManager.sampleTranscript(text)

        guard let endRange = result.range(of: "--- End ---\n") else {
            Issue.record("End header not found in sample")
            return
        }
        let endContent = String(result[endRange.upperBound...])

        #expect(endContent.count <= 600,
            "End section must not exceed 600 chars, got \(endContent.count)")
    }

    // MARK: Distinct content at each position

    @Test func openingMarkersAppearInSample() {
        // Markers placed at start and end — both must survive into the sample
        let start = "STARTMARKER" + String(repeating: "s", count: 989)
        let fill  = String(repeating: "f", count: 2000)
        let end   = String(repeating: "e", count: 989) + "ENDMARKER"
        let text  = start + fill + end

        let result = AIAnalysisManager.sampleTranscript(text)

        #expect(result.contains("STARTMARKER"), "Opening sample must contain beginning marker")
        #expect(result.contains("ENDMARKER"), "End sample must contain closing marker")
    }

    @Test func veryLongTranscriptDoesNotCrash() {
        // 100k chars — must not crash or truncate to empty
        let text = String(repeating: "word ", count: 20_000)
        let result = AIAnalysisManager.sampleTranscript(text)
        #expect(!result.isEmpty, "Sampling a 100k-char transcript must not produce empty output")
    }
}
