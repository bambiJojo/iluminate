//
//  IncumbentBaselineTests.swift
//  IlumionateTests
//
//  Scores the shipping keyword phase analyser against the same hand-labelled
//  boundaries the structural detector is measured on.
//
//  Without this number "F1 35%" says nothing about whether the new approach is
//  worth shipping. Most files get this path in practice — device logs show the
//  on-device model refusing or being blocked far more often than it answers.
//
//  Runs only when TEST_RUNNER_LUMESYNC_CORPUS points at a LumeLabel training
//  corpus, so ordinary runs skip it. The report comes back as an attachment on
//  the .xcresult — the sandboxed test host cannot write a file anywhere useful
//  and xcodebuild does not surface test stdout.
//

import Testing
import Foundation
import CorpusKit
@testable import Ilumionate

private func corpusRoot() -> URL? {
    let environment = ProcessInfo.processInfo.environment
    let path = environment["LUMESYNC_CORPUS"] ?? environment["TEST_RUNNER_LUMESYNC_CORPUS"]
    return path.map { URL(filePath: $0) }
}

private struct LabelledFile {
    let name: String
    let duration: TimeInterval
    let boundaries: [TimeInterval]
    let segments: [AudioTranscriptionSegment]
}

/// Whisper control tokens (`<|startoftranscript|>`) are stored raw in the corpus
/// cache; the app strips them before analysis, so the baseline must too or it is
/// being handed input the shipping path never sees.
private func stripControlTokens(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines)
        .filter { $0.isEmpty == false && $0.contains("<|") == false }
        .joined(separator: " ")
}

private func loadLabelledFiles(from root: URL) -> [LabelledFile] {
    let manager = FileManager.default

    var segmentsBySHA: [String: [AudioTranscriptionSegment]] = [:]
    let transcripts = root.appending(path: "AnalyzerDataset/cache/transcripts")
    for file in (try? manager.contentsOfDirectory(at: transcripts, includingPropertiesForKeys: nil)) ?? [] {
        guard file.pathExtension == "json",
              let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = object["audioSHA256"] as? String,
              let transcription = object["transcription"] as? [String: Any],
              let raw = transcription["segments"] as? [[String: Any]] else { continue }

        segmentsBySHA[sha] = raw.compactMap { segment in
            guard let text = segment["text"] as? String,
                  let timestamp = segment["timestamp"] as? Double,
                  let duration = segment["duration"] as? Double else { return nil }
            let cleaned = stripControlTokens(text)
            guard cleaned.isEmpty == false else { return nil }
            return AudioTranscriptionSegment(
                text: cleaned, timestamp: timestamp, duration: duration, confidence: 0
            )
        }
    }

    var files: [LabelledFile] = []
    for file in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
        guard file.pathExtension == "json",
              let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = object["audioSHA256"] as? String,
              let phases = object["phases"] as? [[String: Any]],
              phases.count > 1,
              let segments = segmentsBySHA[sha], segments.isEmpty == false else { continue }

        let starts = phases.compactMap { $0["startTime"] as? Double }.sorted()
        files.append(
            LabelledFile(
                name: (object["audioFilename"] as? String) ?? sha,
                duration: (object["audioDuration"] as? Double) ?? 0,
                boundaries: Array(starts.dropFirst()),
                segments: segments
            )
        )
    }
    return files.sorted { $0.name < $1.name }
}

/// One-to-one nearest matching, so a single prediction cannot be credited with
/// finding several different labelled boundaries.
private func hits(predicted: [Double], truth: [Double], tolerance: Double) -> Int {
    var available = Array(predicted.indices)
    var found = 0
    for boundary in truth {
        guard let best = available
            .map({ (index: $0, distance: abs(predicted[$0] - boundary)) })
            .filter({ $0.distance <= tolerance })
            .min(by: { $0.distance < $1.distance }) else { continue }
        found += 1
        available.removeAll { $0 == best.index }
    }
    return found
}

struct IncumbentBaselineTests {

    @Test(
        "Score the shipping keyword analyser against the labelled corpus",
        .enabled(if: corpusRoot() != nil)
    )
    func scoreIncumbent() throws {
        let root = try #require(corpusRoot())
        let files = loadLabelledFiles(from: root)
        try #require(files.isEmpty == false, "no file has both a transcript and labelled boundaries")

        let tolerance: TimeInterval = 30
        let analyzer = HypnosisPhaseAnalyzer()
        var lines: [String] = ["Incumbent keyword analyser — tolerance ±\(Int(tolerance))s", ""]
        var totalHits = 0, totalTrue = 0, totalPredicted = 0

        for file in files {
            let phases = analyzer.analyze(segments: file.segments, duration: file.duration)
            let predicted = Array(phases.map(\.startTime).sorted().dropFirst())
            let found = hits(predicted: predicted, truth: file.boundaries, tolerance: tolerance)

            totalHits += found
            totalTrue += file.boundaries.count
            totalPredicted += predicted.count

            lines.append(
                "  \(file.name) — \(found)/\(file.boundaries.count) found, "
                    + "\(predicted.count) predicted, \(phases.count) phase(s)"
            )
            lines.append("     labels:    " + file.boundaries.map { Int($0).description }.joined(separator: " "))
            lines.append("     predicted: " + predicted.map { Int($0).description }.joined(separator: " "))
        }

        let recall = totalTrue > 0 ? Double(totalHits) / Double(totalTrue) : 0
        let precision = totalPredicted > 0 ? Double(totalHits) / Double(totalPredicted) : 0
        let f1 = (recall + precision) > 0 ? 2 * recall * precision / (recall + precision) : 0
        let headline = "INCUMBENT  recall \(Int(recall * 100))%  precision \(Int(precision * 100))%"
            + "  F1 \(Int(f1 * 100))%  (\(totalHits)/\(totalTrue) labelled, \(totalPredicted) predicted)"
        lines.append("")
        lines.append(headline)

        // Attached rather than printed or written to disk: `xcodebuild test` does
        // not surface test stdout, and the sandboxed macOS test host cannot write
        // to /tmp, ~/Downloads, or even its own Documents directory. The
        // attachment lands in the .xcresult, which is readable with
        // `xcrun xcresulttool get test-results summary`.
        Attachment.record(
            lines.joined(separator: "\n"),
            named: "incumbent-baseline.txt"
        )

        // A measurement, not a threshold — but a run that matched nothing at all
        // would mean the harness is misfeeding the analyser rather than that the
        // analyser is bad, and that should not read as a result.
        #expect(totalPredicted > 0, "the incumbent produced no phase boundaries at all")
    }
}
