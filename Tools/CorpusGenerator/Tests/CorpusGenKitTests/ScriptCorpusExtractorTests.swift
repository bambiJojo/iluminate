import Foundation
import Testing
import CorpusKit
@testable import CorpusGenKit

struct ScriptCorpusExtractorTests {
    @Test("Extractor splits book-like text and removes model-facing noise")
    func extractorSplitsBlocksAndRemovesNoise() throws {
        let text = """
        INDUCTIONS
        - 12 -
        Slow Staircase
        By Example Author
        (Lower your voice)
        Take a slow breath and notice the room fading into the background.
        Each number can help your attention settle more comfortably.
        Enter script here for later suggestions.

        Ocean Awakening
        AWAKENING
        By Example Author
        Count up from one to five and let the body become alert.
        Eyes open, mind clear, fully awake and present.
        """

        let report = ScriptCorpusExtractor.extract(
            text: text,
            sourceFilename: "inductionsBook1.rtf",
            sourcePath: "inductionsBook1.rtf",
            fallbackPhase: .induction
        )

        #expect(report.blocks.count == 2)
        #expect(report.blocks[0].title == "Slow Staircase")
        #expect(report.blocks[0].phase == .induction)
        #expect(report.blocks[0].spokenText.contains("By Example") == false)
        #expect(report.blocks[0].spokenText.contains("Lower your voice") == false)
        #expect(report.blocks[0].spokenText.contains("Enter script") == false)
        #expect(report.blocks[0].stageDirections == ["Lower your voice"])
        #expect(report.blocks[0].qualityFlags.contains(.stageDirectionsRemoved))
        #expect(report.blocks[0].qualityFlags.contains(.mixedInstructionalText))
        #expect(report.blocks[1].title == "Ocean Awakening")
        #expect(report.blocks[1].phase == .emergence)
    }

    @Test("Materialized script corpus writes clean text and a manifest")
    func materializedExtractionWritesCleanCorpus() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let report = ScriptCorpusExtractionReport(
            blocks: [
                ExtractedScriptBlock(
                    id: "abcdef123456",
                    phase: .emergence,
                    title: "Clean Awakening",
                    sourceFilename: "awakeningBook1.rtf",
                    sourcePath: "awakeningBook1.rtf",
                    pageRange: nil,
                    spokenText: "Let the eyes open now, fully awake and clear, steady, present, refreshed, grounded. Notice the room around you, the support beneath you, and the easy return of ordinary awareness as you bring useful calm forward into the next thing you choose to do.",
                    stageDirections: [],
                    wordCount: 44,
                    qualityFlags: []
                )
            ],
            issues: []
        )

        let written = try ScriptCorpusExtractor.writeScriptCorpus(report, to: directory)
        #expect(written.contains { $0.lastPathComponent == "_extraction_manifest.json" })

        let textURL = directory
            .appending(path: TrancePhase.emergence.rawValue, directoryHint: .isDirectory)
            .appending(path: "clean-awakening-abcdef12.txt")
        let text = try String(contentsOf: textURL, encoding: .utf8)
        #expect(text == "Let the eyes open now, fully awake and clear, steady, present, refreshed, grounded. Notice the room around you, the support beneath you, and the easy return of ordinary awareness as you bring useful calm forward into the next thing you choose to do.")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ScriptCorpusExtractorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
