//
//  StructuralHarnessTests.swift
//  IlumionateTests
//
//  Runs the structural segmenter over a real analysis cache and prints a report
//  per file. Not a pass/fail test — an inspection tool, because the detector's
//  thresholds are unvalidated and the fastest way to judge them is to read the
//  boundaries for files whose shape is already known.
//
//  Skipped unless `LUMESYNC_CACHE` points at an `AnalysisCache.json` exported
//  from a device container, so a normal test run is unaffected.
//
//      LUMESYNC_CACHE=/path/to/AnalysisCache.json \
//        Scripts/run-tests.sh -destination 'platform=macOS,arch=arm64' \
//          -only-testing:IlumionateTests/StructuralHarnessTests
//

import Testing
import Foundation
@testable import Ilumionate

/// A local mirror of the cache entry. The app persists with a plain
/// `JSONEncoder()` (AnalysisStateManager.swift:47), so the harness decodes with
/// a plain `JSONDecoder()` — an `.iso8601` date strategy here would fail on any
/// `Date` nested in the analysis.
/// `CachedAudioAnalysis` is private to
/// `AnalysisStateManager`, and widening it just for a harness would be the wrong
/// trade — this only needs two of its fields.
private struct HarnessCacheEntry: Decodable {
    let transcription: AudioTranscriptionResult?
    let analysis: AnalysisResult
}

private var cachePath: String? {
    ProcessInfo.processInfo.environment["LUMESYNC_CACHE"]
}

struct StructuralHarnessTests {

    @Test(
        "Report structure for every cached analysis",
        .enabled(if: cachePath != nil)
    )
    func reportEveryCachedFile() throws {
        let path = try #require(cachePath)
        let data = try Data(contentsOf: URL(filePath: path))
        let entries = try JSONDecoder().decode([String: HarnessCacheEntry].self, from: data)

        var reports: [(name: String, text: String, segments: Int)] = []

        for (key, entry) in entries {
            guard let transcription = entry.transcription, transcription.segments.isEmpty == false else {
                continue
            }
            let words = HypnosisPhaseAnalyzer.approximateWordTimestamps(from: transcription.segments)
            guard words.isEmpty == false else { continue }

            let segmentation = StructuralSegmenter.segment(
                words: words,
                prosody: entry.analysis.prosodicProfile,
                duration: transcription.duration
            )
            reports.append(
                (
                    key,
                    StructuralReport.text(for: segmentation, filename: key),
                    segmentation.segments.count
                )
            )
        }

        let distribution = Dictionary(grouping: reports, by: \.segments)
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "\($0.key) segment(s): \($0.value) file(s)" }
            .joined(separator: "  ·  ")

        print("""

        ══════════ STRUCTURAL SEGMENTATION ══════════
        \(reports.count) file(s) with usable transcripts
        \(distribution)
        ─────────────────────────────────────────────
        """)
        for report in reports.sorted(by: { $0.name < $1.name }) {
            print(report.text)
        }
        print("═════════════════════════════════════════════\n")

        // The harness exists to be read, not to assert. The one thing worth
        // failing on is producing nothing at all from a cache that has content.
        #expect(reports.isEmpty == false)
    }
}
