//  PhaseDatasetExporter.swift
//  IlumionateTests
//
//  Offline dev harness: loops labeled CorpusCases and writes one CSV row per
//  labeled second via PhaseFeatureExtractor. Gray-zone seconds are skipped.
//
import Foundation
import CorpusKit
@testable import Ilumionate

@MainActor
struct PhaseDatasetExporter {

    /// Truth phase covering `time` (half-open spans), or nil in a gray zone.
    private func phase(at time: TimeInterval, in spans: [PhaseTruthSpan]) -> TrancePhase? {
        for span in spans where time >= span.start && time < span.end { return span.phase }
        return nil
    }

    /// Writes the CSV to `url`, returning the number of data rows emitted.
    @discardableResult
    func export(cases: [CorpusCase], to url: URL) throws -> Int {
        let header = "case_id,second," + PhaseFeatureExtractor.columnNames.joined(separator: ",") + ",label"
        var lines: [String] = [header]
        var rows = 0

        for kase in cases.sorted(by: { $0.id < $1.id }) where !kase.truth.isEmpty {
            let transcription = AudioTranscriptionResult(
                fullText: kase.transcriptText,
                segments: kase.transcriptionSegments,
                duration: kase.duration,
                detectedLanguage: "en"
            )
            let extractor = PhaseFeatureExtractor(transcription: transcription)
            let bucketCount = max(1, Int(ceil(kase.duration)))
            for second in 0..<bucketCount {
                guard let truth = phase(at: Double(second) + 0.5, in: kase.truth) else { continue }
                let values = extractor.featureVector(at: second).values
                    .map { String(format: "%.6f", $0) }
                    .joined(separator: ",")
                lines.append("\(kase.id),\(second),\(values),\(truth.rawValue)")
                rows += 1
            }
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return rows
    }
}
