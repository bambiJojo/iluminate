//  PhaseDatasetExportTests.swift
//  IlumionateTests
//
//  TDD tests for PhaseDatasetExporter (Task 4 of phase-eval-harness plan).
//
import Testing
import Foundation
import CorpusKit
@testable import Ilumionate

@MainActor
struct PhaseDatasetExportTests {

    private func makeCase() -> CorpusCase {
        CorpusCase(
            id: "t1", source: .synthetic, boundaryMode: .exact, ambiguityLevel: .low,
            duration: 60,
            segments: [
                CorpusSegment(text: "close your eyes and relax", timestamp: 0, duration: 30, confidence: 1),
                CorpusSegment(text: "going deeper and deeper", timestamp: 30, duration: 30, confidence: 1),
            ],
            truth: [
                PhaseTruthSpan(phase: .induction, start: 0, end: 30),
                PhaseTruthSpan(phase: .deepening, start: 30, end: 60),
            ]
        )
    }

    @Test("Exports a header plus one row per labeled second")
    func exportsRowsForLabeledSeconds() throws {
        let url = URL.temporaryDirectory.appending(path: "ds-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }

        let count = try PhaseDatasetExporter().export(cases: [makeCase()], to: url)
        #expect(count == 60)

        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 61)
        #expect(lines.first?.hasPrefix("case_id,second,") == true)
        #expect(lines.first?.hasSuffix(",label") == true)
        for line in lines.dropFirst() {
            let label = line.split(separator: ",").last.map(String.init) ?? ""
            #expect(TrancePhase(rawValue: label) != nil, "bad label: \(label)")
        }
    }

    @Test("Gray-zone seconds are skipped")
    func skipsGrayZones() throws {
        let kase = CorpusCase(
            id: "g1", source: .real, boundaryMode: .anchored, ambiguityLevel: .unspecified,
            duration: 60, segments: makeCase().segments,
            truth: [PhaseTruthSpan(phase: .induction, start: 0, end: 20)]
        )
        let url = URL.temporaryDirectory.appending(path: "ds-\(UUID().uuidString).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        let count = try PhaseDatasetExporter().export(cases: [kase], to: url)
        #expect(count == 20)
    }

    /// Truth-bearing cases from the on-disk corpus, across every subdirectory.
    private func labeledCorpusCases() throws -> [CorpusCase] {
        try (CorpusLoader.load(subdirectory: "fixtures")
           + CorpusLoader.load(subdirectory: "synthetic")
           + CorpusLoader.load(subdirectory: "real"))
            .filter { !$0.truth.isEmpty }
    }

    @Test("Generates phase-features.csv from the on-disk labeled corpus")
    func generatesFromCorpus() throws {
        let cases = try labeledCorpusCases()
        try #require(!cases.isEmpty, "no truth-bearing corpus cases")

        // Export somewhere unique per run. Suites run in parallel, so writing the
        // real artifact path here let two workers interleave writes into the file
        // this test reads back, which broke the column-count check intermittently.
        // Regenerating the artifact is `exportsDatasetArtifact` below.
        let directory = URL.temporaryDirectory.appending(path: "phase-dataset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let out = directory.appending(path: "phase-features.csv")

        let rows = try PhaseDatasetExporter().export(cases: cases, to: out)
        #expect(rows > 0)

        let text = try String(contentsOf: out, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let expectedColumns = lines.first!.split(separator: ",", omittingEmptySubsequences: false).count
        for line in lines.dropFirst() {
            #expect(line.split(separator: ",", omittingEmptySubsequences: false).count == expectedColumns)
        }
    }

    /// Opt-in regeneration of the training dataset at `Corpus/dataset/phase-features.csv`
    /// (gitignored; regenerate, don't commit). Disabled by default so a normal suite
    /// run never writes into the shared corpus directory. Run it explicitly with:
    ///
    ///     PHASE_DATASET_EXPORT=1 xcodebuild -project Ilumionate.xcodeproj -scheme Ilumionate \
    ///       -destination 'platform=macOS,arch=arm64' test \
    ///       -only-testing:IlumionateTests/PhaseDatasetExportTests/exportsDatasetArtifact
    @Test(
        "Writes the training dataset artifact into the corpus directory",
        .enabled(if: ProcessInfo.processInfo.environment["PHASE_DATASET_EXPORT"] != nil)
    )
    func exportsDatasetArtifact() throws {
        let cases = try labeledCorpusCases()
        try #require(!cases.isEmpty, "no truth-bearing corpus cases")

        let out = CorpusLoader.corpusRoot.appending(path: "dataset").appending(path: "phase-features.csv")
        let rows = try PhaseDatasetExporter().export(cases: cases, to: out)
        #expect(rows > 0)
    }
}
