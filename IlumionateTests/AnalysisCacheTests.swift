//
//  AnalysisCacheTests.swift
//  IlumionateTests
//
//  Tests for Step 2.3: persistent analysis cache in AnalysisStateManager.
//

import Testing
import Foundation
@testable import Ilumionate

// MARK: - Helpers

private func makeAudioFile(id: UUID = UUID()) -> AudioFile {
    AudioFile(
        id: id,
        filename: "test_\(id.uuidString).m4a",
        duration: 300,
        fileSize: 1_024_000,
        createdDate: Date()
    )
}

// MARK: - Tests

struct AnalysisCacheTests {

    // MARK: Basic cache API (structural — no disk writes needed)

    @Test func newFileHasNoCachedResultIsBoolReturned() {
        // A brand-new UUID will rarely be cached; mainly checks API compiles and runs
        let file = makeAudioFile()
        let result: Bool = AnalysisStateManager.shared.hasCachedResult(for: file)
        _ = result // structural
    }

    @Test func cachedResultForUnknownFileReturnsOptional() {
        let file = makeAudioFile()
        let result: AnalysisResult? = AnalysisStateManager.shared.cachedResult(for: file)
        _ = result // structural — verifies type is Optional<AnalysisResult>
    }

    @Test func evictCachedResultDoesNotCrashForMissingKey() async {
        // Evicting a file that was never cached must not throw or crash
        let file = makeAudioFile()
        await AnalysisStateManager.shared.evictCachedResult(for: file)
        // If we get here without crashing, the test passes
    }

    @Test func reusableTranscriptionResultUsesSavedTranscript() {
        var file = makeAudioFile()
        file.transcription = "  <|startoftranscript|> breathe slowly and relax deeper now  "

        let result = AnalysisStateManager.reusableTranscriptionResult(for: file)

        #expect(result?.fullText == "breathe slowly and relax deeper now")
        #expect(result?.duration == file.duration)
        #expect(result?.segments.count == 1)
        #expect(result?.segments.first?.timestamp == 0)
        #expect(result?.segments.first?.duration == file.duration)
    }

    @Test func reusableTranscriptionResultSkipsEmptyTranscript() {
        var file = makeAudioFile()
        file.transcription = " <|nospeech|> "

        #expect(AnalysisStateManager.reusableTranscriptionResult(for: file) == nil)
    }

    // MARK: Cache URL shape

    @Test @MainActor func cacheURLIsInDocumentsDirectory() {
        let url = AnalysisStateManager.cacheURL
        let docsPath = URL.documentsDirectory.path
        #expect(url.path.hasPrefix(docsPath),
            "Cache URL must be inside Documents directory")
    }

    @Test @MainActor func cacheURLHasJSONExtension() {
        let url = AnalysisStateManager.cacheURL
        #expect(url.pathExtension == "json",
            "Cache file must have .json extension, got .\(url.pathExtension)")
    }

    @Test @MainActor func cacheURLContainsCacheInFilename() {
        let url = AnalysisStateManager.cacheURL
        #expect(url.lastPathComponent.localizedStandardContains("Cache"),
            "Cache filename must contain 'Cache', got: \(url.lastPathComponent)")
    }
}
