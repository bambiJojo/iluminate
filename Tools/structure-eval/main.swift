import Foundation

// Measures the structural segmenter against hand-labelled boundaries from
// LumeLabel's training corpus, and sweeps the two parameters that were
// previously chosen by eye.
//
// usage: structure-eval <TrainingCorpus root> [tolerance seconds]

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: structure-eval <corpus root> [tolerance]\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1])
let tolerance = arguments.count > 2 ? Double(arguments[2]) ?? 30 : 30

// MARK: - Load transcripts

/// Whisper emits control tokens like `<|startoftranscript|>` into the word
/// stream. The app strips them (`AudioAnalyzer.sanitizedTranscriptText`) but the
/// corpus cache stores them raw, and left in they become high-frequency terms
/// that distort every similarity score.
func isControlToken(_ word: String) -> Bool { word.contains("<|") }

var wordsBySHA: [String: [WordTimestamp]] = [:]
let transcriptDirectory = root.appending(path: "AnalyzerDataset/cache/transcripts")
for file in (try? FileManager.default.contentsOfDirectory(at: transcriptDirectory, includingPropertiesForKeys: nil)) ?? [] {
    guard file.pathExtension == "json",
          let data = try? Data(contentsOf: file),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sha = object["audioSHA256"] as? String,
          let prepared = object["prepared"] as? [String: Any],
          let rawWords = prepared["wordTimestamps"] as? [[String: Any]] else { continue }

    wordsBySHA[sha] = rawWords.compactMap { entry in
        guard let word = entry["word"] as? String,
              let start = entry["startTime"] as? Double,
              let duration = entry["duration"] as? Double,
              isControlToken(word) == false else { return nil }
        return WordTimestamp(word: word, startTime: start, duration: duration)
    }
}

// MARK: - Load labelled boundaries

struct Truth { let name: String; let duration: Double; let boundaries: [Double] }
var truths: [String: Truth] = [:]

// The top-level label files are the richer source. `AnalyzerDataset/dataset.jsonl`
// carries a `denseTimeline` that has lost transitions — BF.mp3 has six phase
// changes in its `phases` array and only four in the dense export — so measuring
// against the dense copy scores the detector for missing boundaries the ground
// truth itself had already dropped.
for file in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
    guard file.pathExtension == "json",
          let data = try? Data(contentsOf: file),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sha = object["audioSHA256"] as? String,
          let phases = object["phases"] as? [[String: Any]],
          phases.count > 1 else { continue }

    let sorted = phases.compactMap { $0["startTime"] as? Double }.sorted()
    // The opening phase starts because the file does; it is not a transition.
    let boundaries = Array(sorted.dropFirst())
    guard boundaries.isEmpty == false else { continue }

    truths[sha] = Truth(
        name: (object["audioFilename"] as? String) ?? sha,
        duration: (object["audioDuration"] as? Double) ?? 0,
        boundaries: boundaries
    )
}

let evaluable = truths.filter { wordsBySHA[$0.key]?.isEmpty == false }
guard evaluable.isEmpty == false else {
    print("No file has both a transcript and labelled boundaries.")
    exit(1)
}

// MARK: - Matching

/// One-to-one nearest matching within the tolerance, so a single predicted
/// boundary cannot be credited with finding three different true ones.
func match(predicted: [Double], truth: [Double], tolerance: Double) -> (hits: Int, errors: [Double]) {
    var available = Array(predicted.indices)
    var hits = 0
    var errors: [Double] = []
    for boundary in truth {
        let best = available
            .map { (index: $0, distance: abs(predicted[$0] - boundary)) }
            .filter { $0.distance <= tolerance }
            .min { $0.distance < $1.distance }
        guard let best else { continue }
        hits += 1
        errors.append(best.distance)
        available.removeAll { $0 == best.index }
    }
    return (hits, errors)
}

// MARK: - Sweep

print("Evaluating \(evaluable.count) labelled file(s), tolerance ±\(Int(tolerance))s\n")
print("novelty  minSeg  kernel   recall   precision      F1   medianErr")
print(String(repeating: "─", count: 60))

var best: (score: Double, novelty: Double, segment: Double, kernel: Int)?

for novelty in [0.05, 0.10, 0.15, 0.20, 0.30] {
    for minimumSegment in [30.0, 60.0, 120.0] {
      for kernel in [10, 20, 30, 40, 60] {
        var totalHits = 0, totalTrue = 0, totalPredicted = 0
        var allErrors: [Double] = []

        for (sha, truth) in evaluable {
            let segmentation = StructuralSegmenter.segment(
                words: wordsBySHA[sha] ?? [],
                prosody: nil,
                duration: truth.duration,
                minimumSegmentDuration: minimumSegment,
                minimumNovelty: novelty,
                kernelSize: kernel
            )
            // The first segment opens because the file does, not at a boundary.
            let predicted = segmentation.segments.dropFirst().map(\.startTime)
            let result = match(predicted: predicted, truth: truth.boundaries, tolerance: tolerance)
            totalHits += result.hits
            totalTrue += truth.boundaries.count
            totalPredicted += predicted.count
            allErrors += result.errors
        }

        let recall = totalTrue > 0 ? Double(totalHits) / Double(totalTrue) : 0
        let precision = totalPredicted > 0 ? Double(totalHits) / Double(totalPredicted) : 0
        let f1 = (recall + precision) > 0 ? 2 * recall * precision / (recall + precision) : 0
        let median = allErrors.isEmpty ? Double.nan : allErrors.sorted()[allErrors.count / 2]

        if best == nil || f1 > best!.score { best = (f1, novelty, minimumSegment, kernel) }

        let medianText = median.isNaN ? "    –" : "\(Int(median))s"
        print("   \(novelty)     \(Int(minimumSegment))s     \(kernel)    \(Int(recall * 100))%        \(Int(precision * 100))%     \(Int(f1 * 100))%      \(medianText)")
      }
    }
}

if let best {
    print("\nBest F1 \(Int(best.score * 100))% at novelty \(best.novelty), minSegment \(Int(best.segment))s, kernel \(best.kernel)")
}

// MARK: - Per-file detail at the best setting

if let best {
    print("\nPer-file at that setting:")
    for (sha, truth) in evaluable.sorted(by: { $0.value.name < $1.value.name }) {
        let segmentation = StructuralSegmenter.segment(
            words: wordsBySHA[sha] ?? [],
            prosody: nil,
            duration: truth.duration,
            minimumSegmentDuration: best.segment,
            minimumNovelty: best.novelty,
            kernelSize: best.kernel
        )
        let predicted = segmentation.segments.dropFirst().map(\.startTime)
        let result = match(predicted: predicted, truth: truth.boundaries, tolerance: tolerance)
        print("  \(truth.name) — \(result.hits)/\(truth.boundaries.count) found, \(predicted.count) predicted")
        print("     true:      \(truth.boundaries.map { StructuralReport.clock($0) }.joined(separator: " "))")
        print("     predicted: \(predicted.map { StructuralReport.clock($0) }.joined(separator: " "))")
    }
}
