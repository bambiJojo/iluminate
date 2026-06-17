//
//  ScriptPhaseCorpusTests.swift
//  IlumionateTests
//

import Foundation
import Testing
@testable import Ilumionate

struct ScriptPhaseCorpusTests {

    @Test
    func loadsRTFScriptLibrariesAndInfersCanonicalPhases() throws {
        let directory = try makeTempDirectory()
        try writeRTF(
            "Close your eyes and focus on the candle. Focus on the candle point as you begin trance.",
            to: directory.appending(path: "inductionsBook1.rtf")
        )
        try writeRTF(
            "Go deeper and deeper now. Drift deeper with every breath and test that depth.",
            to: directory.appending(path: "depthTestsBook1.rtf")
        )
        try writeRTF(
            "Coming back now, fully awake and wide awake. Open your eyes feeling clear.",
            to: directory.appending(path: "awakeningBook1.rtf")
        )
        try "No phase hint here".write(
            to: directory.appending(path: "misc.txt"),
            atomically: true,
            encoding: .utf8
        )

        let corpus = ScriptPhaseCorpus.load(from: directory)

        #expect(corpus.examples.map(\.phase) == [.induction, .deepening, .emergence])
        #expect(corpus.examples.allSatisfy { $0.wordCount >= 12 })
        #expect(corpus.issues.contains { $0.filename == "misc.txt" && $0.severity == .warning })
    }

    @Test
    func defaultLoaderIgnoresRawScriptsDirectories() throws {
        let workingDirectory = try makeTempDirectory()
        let documentsDirectory = try makeTempDirectory()
        let rawDirectory = workingDirectory.appending(path: ".scripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try writeRTF(
            "Close your eyes and relax deeper than before. This raw file should not calibrate the model.",
            to: rawDirectory.appending(path: "inductionsBook1.rtf")
        )

        let corpus = ScriptPhaseCorpus.loadDefault(
            currentDirectory: workingDirectory,
            documentsDirectory: documentsDirectory,
            bundle: try makeEmptyBundle()
        )

        #expect(corpus.examples.isEmpty)
        #expect(corpus.directories.contains { $0.lastPathComponent == ".scripts" } == false)
    }

    @Test
    func extractorSplitsBlocksAndRemovesBookNoise() throws {
        let text = """
        INDUCTIONS
        - 42 -

        Active Muscular Relaxation
        By Rene A. Bastarache, CI, CHT
        Close your eyes and take a deep breath.
        (make sure they close their eyes)
        Let your shoulders relax and let your breathing become slow.
        Continue deeper with every breath as the induction begins.

        Garden Scenery
        By Barbara Carter, CHT
        Imagine a garden with warm sunlight.
        Feel the chair supporting you as every sound helps you relax.
        Enter script here.
        """

        let report = ScriptCorpusExtractor.extract(
            text: text,
            sourceFilename: "inductionsBook1.rtf",
            sourcePath: "inductionsBook1.rtf",
            fallbackPhase: .induction
        )

        #expect(report.blocks.count == 2)
        let first = try #require(report.blocks.first)
        #expect(first.title == "Active Muscular Relaxation")
        #expect(first.phase == .induction)
        #expect(first.spokenText.contains("- 42 -") == false)
        #expect(first.spokenText.contains("By Rene") == false)
        #expect(first.spokenText.contains("make sure") == false)
        #expect(first.stageDirections == ["make sure they close their eyes"])
        #expect(first.qualityFlags.contains(.stageDirectionsRemoved))

        let second = try #require(report.blocks.last)
        #expect(second.spokenText.contains("Enter script here") == false)
        #expect(second.qualityFlags.contains(.mixedInstructionalText))
    }

    @Test
    func materializedExtractionFeedsScriptPhaseCorpus() throws {
        let report = ScriptCorpusExtractionReport(
            blocks: [
                ExtractedScriptBlock(
                    id: "abc123",
                    phase: .emergence,
                    title: "Awakening I",
                    sourceFilename: "awakeningBook1.rtf",
                    sourcePath: "awakeningBook1.rtf",
                    pageRange: 553...554,
                    spokenText: "In a moment I will count from one up to five, and with each number your mind returns fully awake, alert, clear, and refreshed. Your breathing steadies, your body feels balanced, your eyes open comfortably, and you bring back only the calm usefulness of this experience.",
                    stageDirections: [],
                    wordCount: 45,
                    qualityFlags: []
                )
            ],
            issues: []
        )
        let directory = try makeTempDirectory()
        let written = try ScriptCorpusExtractor.writeScriptCorpus(report, to: directory)

        #expect(written.contains { $0.lastPathComponent == "_extraction_manifest.json" })

        let corpus = ScriptPhaseCorpus.load(from: directory)
        #expect(corpus.issues.isEmpty)
        let example = try #require(corpus.examples.first)
        #expect(corpus.examples.count == 1)
        #expect(example.phase == .emergence)
        #expect(example.text.contains("source:") == false)
        #expect(example.text.contains("fully awake"))
    }

    @Test
    func nestedCorpusFolderBecomesSourcePack() throws {
        let directory = try makeTempDirectory()
        let bambiDirectory = directory
            .appendingPathComponent("bambi", isDirectory: true)
            .appendingPathComponent("brainwashing", isDirectory: true)
        try FileManager.default.createDirectory(at: bambiDirectory, withIntermediateDirectories: true)
        let scriptURL = bambiDirectory.appendingPathComponent("mind-lock.txt")
        try """
        This script repeats a source specific phrase enough times to teach the analyzer.
        The mind lock phrase returns again and again as the conditioning language continues.
        """.write(
            to: scriptURL,
            atomically: true,
            encoding: .utf8
        )

        #expect(FileManager.default.fileExists(atPath: scriptURL.path))
        let corpus = ScriptPhaseCorpus.load(from: directory)
        #expect(corpus.issues.isEmpty)
        let example = try #require(corpus.examples.first)

        #expect(example.phase == .brainwashing)
        #expect(example.sourcePath == "bambi/brainwashing/mind-lock.txt")
        #expect(example.sourcePackID == "bambi")
        #expect(example.sourcePackLabel == "Bambi corpus")
    }

    @Test
    func scriptCorpusFeedsCorpusPhaseKnowledge() {
        let text = """
        Focus on the candle point. Focus on the candle point. Focus on the candle point.
        Close your eyes and keep focusing on that candle point as the induction begins.
        """
        let example = ScriptPhaseExample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            phase: .induction,
            title: "Candle Focus",
            sourceFilename: "inductionsBook1.rtf",
            sourcePath: "inductionsBook1.rtf",
            text: text,
            wordCount: ScriptPhaseTextAnalyzer.tokens(in: text).count
        )
        let scriptCorpus = ScriptPhaseCorpus(
            directories: [],
            examples: [example],
            issues: []
        )

        let knowledge = CorpusPhaseKnowledgeBuilder(
            dataset: nil,
            scriptCorpus: scriptCorpus
        ).build()

        #expect(knowledge.keywordWeights[.induction]?["candle"] != nil)
        #expect(knowledge.phraseWeights[.induction]?["focus on"] != nil)
        #expect(knowledge.fewShotExamples.contains { $0.correctPhase == TrancePhase.induction.rawValue })
    }

    @Test
    func scriptCorpusSourcePackFeedsPhraseAssociationMetadata() {
        let text = """
        Mind lock settles in. Mind lock repeats again. Mind lock becomes familiar.
        Mind lock keeps returning as the brainwashing language repeats.
        """
        let example = ScriptPhaseExample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            phase: .brainwashing,
            title: "Mind Lock",
            sourceFilename: "mind-lock.txt",
            sourcePath: "bambi/brainwashing/mind-lock.txt",
            sourcePackID: "bambi",
            sourcePackLabel: "Bambi corpus",
            text: text,
            wordCount: ScriptPhaseTextAnalyzer.tokens(in: text).count
        )
        let scriptCorpus = ScriptPhaseCorpus(
            directories: [],
            examples: [example],
            issues: []
        )

        let knowledge = CorpusPhaseKnowledgeBuilder(
            dataset: nil,
            scriptCorpus: scriptCorpus
        ).build()

        let association = knowledge.phraseAssociations[.brainwashing]?
            .first { $0.sourcePackIDs.contains("bambi") }
        #expect(association?.sourceLabel == "Bambi corpus")
        #expect(association?.sourcePackIDs == ["bambi"])
        #expect(knowledge.phraseSourcePacks[.brainwashing]?["mind lock"] == ["bambi"])
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "ScriptPhaseCorpusTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeEmptyBundle() throws -> Bundle {
        let bundleURL = try makeTempDirectory().appending(path: "Empty.bundle", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let plistURL = bundleURL.appending(path: "Info.plist")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.ilumionate.tests.empty</string>
            <key>CFBundleName</key>
            <string>Empty</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """.write(to: plistURL, atomically: true, encoding: .utf8)
        return try #require(Bundle(url: bundleURL))
    }

    private func writeRTF(_ text: String, to url: URL) throws {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
        try "{\\rtf1\\ansi \(escaped)}".write(to: url, atomically: true, encoding: .utf8)
    }
}
