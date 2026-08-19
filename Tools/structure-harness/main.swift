import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: harness <AnalysisCache.json> [minimumNovelty]\n".utf8))
    exit(2)
}
let minimumNovelty = arguments.count > 2 ? Double(arguments[2]) ?? 0.08 : 0.08
let minimumSegment = arguments.count > 3 ? Double(arguments[3]) ?? 45 : 45

/// Cache keys are "<contentFingerprint>:<modelVersion>". library.json carries the
/// filename against the same fingerprint, so a report can name files the user
/// recognises instead of hashes.
var namesByFingerprint: [String: String] = [:]
if arguments.count > 4,
   let libraryData = try? Data(contentsOf: URL(fileURLWithPath: arguments[4])),
   let library = try? JSONSerialization.jsonObject(with: libraryData) as? [[String: Any]] {
    for file in library {
        if let fingerprint = file["contentFingerprint"] as? String,
           let filename = file["filename"] as? String {
            namesByFingerprint[fingerprint] = filename
        }
    }
}
func displayName(_ key: String) -> String {
    let fingerprint = key.split(separator: ":").first.map(String.init) ?? key
    return namesByFingerprint[fingerprint] ?? String(fingerprint.prefix(12))
}

let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    fatalError("cache is not a JSON object")
}

struct Row { let name: String; let text: String; let segments: Int; let hadProsody: Bool }
var rows: [Row] = []
var skipped: [String: Int] = [:]

for (key, value) in raw {
    guard let entry = value as? [String: Any],
          let transcription = entry["transcription"] as? [String: Any],
          let rawSegments = transcription["segments"] as? [[String: Any]],
          rawSegments.isEmpty == false else {
        skipped["no transcript segments", default: 0] += 1
        continue
    }
    let duration = (transcription["duration"] as? Double) ?? 0
    let segments = rawSegments.compactMap { segment -> (text: String, timestamp: Double, duration: Double)? in
        guard let text = segment["text"] as? String,
              let timestamp = segment["timestamp"] as? Double,
              let length = segment["duration"] as? Double else { return nil }
        return (text, timestamp, length)
    }
    let words = WordApproximation.words(fromSegments: segments)
    guard words.isEmpty == false else {
        skipped["no words", default: 0] += 1
        continue
    }

    var prosody: ProsodicProfile?
    if let analysis = entry["analysis"] as? [String: Any],
       let profile = analysis["prosodicProfile"],
       let profileData = try? JSONSerialization.data(withJSONObject: profile) {
        prosody = try? JSONDecoder().decode(ProsodicProfile.self, from: profileData)
    }

    let segmentation = StructuralSegmenter.segment(
        words: words,
        prosody: prosody,
        duration: duration,
        minimumSegmentDuration: minimumSegment,
        minimumNovelty: minimumNovelty
    )
    rows.append(
        Row(
            name: displayName(key),
            text: StructuralReport.text(for: segmentation, filename: displayName(key)),
            segments: segmentation.segments.count,
            hadProsody: prosody != nil
        )
    )
}

let distribution = Dictionary(grouping: rows, by: \.segments)
    .mapValues(\.count)
    .sorted { $0.key < $1.key }
    .map { "\($0.key): \($0.value)" }
    .joined(separator: "  ")

print("══════ STRUCTURAL SEGMENTATION (novelty \(minimumNovelty), minSegment \(Int(minimumSegment))s) ══════")
print("\(raw.count) entries · \(rows.count) analysed · \(rows.filter(\.hadProsody).count) with prosody")
print("skipped: \(skipped.isEmpty ? "none" : skipped.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))")
print("segments per file → \(distribution)")
print(String(repeating: "─", count: 60))
for row in rows.sorted(by: { $0.name < $1.name }) { print(row.text) }
