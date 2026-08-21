//
//  FractionationSignatureTests.swift
//  IlumionateTests
//
//  Does "counts alternating direction in quick succession" actually pick out
//  fractionation?
//
//  Fractionation is induction applied repeatedly — down, up, down, each pass
//  landing deeper — so the signature follows from the technique rather than from
//  where it sits in a file. Naming from it was withdrawn in 43a06d4 because it
//  fired on DFTC.mp3, which is not labelled fractionation, and cost seven points
//  of light accuracy there. This measures whether that was the rule over-firing
//  or DFTC being under-labelled, by running it across every corpus file whose
//  label says what it is.
//
//  Runs only when TEST_RUNNER_LUMESYNC_CORPUS is set. Reports as an attachment.
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

private struct Candidate {
    let name: String
    let duration: TimeInterval
    let labelledPhases: Set<String>
    let words: [WordTimestamp]
}

struct FractionationSignatureTests {

    @Test(
        "Measure whether alternating counts separate fractionation from everything else",
        .enabled(if: corpusRoot() != nil)
    )
    func alternatingCountsDiscriminate() throws {
        let root = try #require(corpusRoot())
        let manager = FileManager.default

        var wordsBySHA: [String: [WordTimestamp]] = [:]
        for file in (try? manager.contentsOfDirectory(
            at: root.appending(path: "AnalyzerDataset/cache/transcripts"),
            includingPropertiesForKeys: nil
        )) ?? [] {
            guard file.pathExtension == "json",
                  let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sha = object["audioSHA256"] as? String,
                  let prepared = object["prepared"] as? [String: Any],
                  let raw = prepared["wordTimestamps"] as? [[String: Any]] else { continue }

            wordsBySHA[sha] = raw.compactMap { entry in
                guard let word = entry["word"] as? String,
                      let start = entry["startTime"] as? Double,
                      let duration = entry["duration"] as? Double,
                      word.contains("<|") == false else { return nil }
                return WordTimestamp(word: word, startTime: start, duration: duration)
            }
        }

        var candidates: [Candidate] = []
        for file in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard file.pathExtension == "json",
                  let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sha = object["audioSHA256"] as? String,
                  let phases = object["phases"] as? [[String: Any]],
                  phases.isEmpty == false,
                  let words = wordsBySHA[sha], words.isEmpty == false else { continue }

            candidates.append(
                Candidate(
                    name: (object["audioFilename"] as? String) ?? sha,
                    duration: (object["audioDuration"] as? Double) ?? 0,
                    labelledPhases: Set(phases.compactMap { $0["phase"] as? String }),
                    words: words
                )
            )
        }
        try #require(candidates.isEmpty == false)

        struct Row { let name: String; let isFractionation: Bool; let runs: Int; let windows: Int; let covered: Double }
        var rows: [Row] = []

        for candidate in candidates {
            let runs = CountingRunDetector.runs(in: candidate.words)
            let windows = CountingRunDetector.fractionationWindows(in: runs)
            let coveredSeconds = windows.reduce(0.0) { $0 + ($1.end - $1.start) }
            rows.append(
                Row(
                    name: candidate.name,
                    isFractionation: candidate.labelledPhases.contains("fractionation"),
                    runs: runs.count,
                    windows: windows.count,
                    covered: candidate.duration > 0 ? coveredSeconds / candidate.duration * 100 : 0
                )
            )
        }

        let positives = rows.filter(\.isFractionation)
        let negatives = rows.filter { $0.isFractionation == false }
        let firedPositive = positives.filter { $0.windows > 0 }.count
        let firedNegative = negatives.filter { $0.windows > 0 }.count

        var lines = [
            "Alternating-count signature against labelled fractionation",
            "",
            "labelled fractionation: \(firedPositive) of \(positives.count) fire",
            "everything else:        \(firedNegative) of \(negatives.count) fire",
            ""
        ]
        for row in rows.sorted(by: { ($0.isFractionation ? 0 : 1, $0.name) < ($1.isFractionation ? 0 : 1, $1.name) }) {
            lines.append(
                "  \(row.isFractionation ? "FRACT" : "     ")  "
                    + "\(row.windows) window(s), \(row.runs) run(s), "
                    + "\(Int(row.covered))% covered  \(row.name.prefix(46))"
            )
        }

        Attachment.record(lines.joined(separator: "\n"), named: "fractionation-signature.txt")
        #expect(rows.isEmpty == false)
    }
}
