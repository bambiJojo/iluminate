import Foundation

// Computes ProsodicProfiles for the labelled corpus files using the app's real
// ProsodyAnalyzer, so the structural detector can be measured with the signal
// its design actually rests on.
//
// The corpus transcript cache stores no prosody, and none of the labelled files
// appear in the production library, so there was no way to borrow one.
//
// usage: structure-prosody <TrainingCorpus root> <output directory>

let arguments = CommandLine.arguments
guard arguments.count > 2 else {
    FileHandle.standardError.write(Data("usage: structure-prosody <corpus root> <out dir>\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let manager = FileManager.default

// MARK: - Which files are worth the audio pass

struct Target { let sha: String; let name: String; let storedFilename: String }
var targets: [Target] = []

for file in (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
    guard file.pathExtension == "json",
          let data = try? Data(contentsOf: file),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sha = object["audioSHA256"] as? String,
          let phases = object["phases"] as? [[String: Any]],
          phases.count > 1,
          let stored = object["storedAudioFilename"] as? String else { continue }
    targets.append(
        Target(sha: sha, name: (object["audioFilename"] as? String) ?? sha, storedFilename: stored)
    )
}

// MARK: - Transcript segments, keyed by audio hash

var segmentsBySHA: [String: [AudioTranscriptionSegment]] = [:]
let transcriptDirectory = root.appending(path: "AnalyzerDataset/cache/transcripts")
for file in (try? manager.contentsOfDirectory(at: transcriptDirectory, includingPropertiesForKeys: nil)) ?? [] {
    guard file.pathExtension == "json",
          let data = try? Data(contentsOf: file),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sha = object["audioSHA256"] as? String,
          let transcription = object["transcription"] as? [String: Any],
          let rawSegments = transcription["segments"] as? [[String: Any]] else { continue }

    segmentsBySHA[sha] = rawSegments.compactMap { segment in
        guard let text = segment["text"] as? String,
              let timestamp = segment["timestamp"] as? Double,
              let duration = segment["duration"] as? Double else { return nil }
        return AudioTranscriptionSegment(
            text: text, timestamp: timestamp, duration: duration, confidence: 0
        )
    }
}

/// The corpus keeps audio in more than one place depending on how it was
/// imported, so look in each rather than assuming a layout.
func locateAudio(_ storedFilename: String) -> URL? {
    let candidates = [
        root.appending(path: "AnalyzerDataset/audio").appending(path: storedFilename),
        root.appending(path: storedFilename),
        root.appending(path: "audio").appending(path: storedFilename)
    ]
    return candidates.first { manager.fileExists(atPath: $0.path()) }
}

// MARK: - Run

let analyzer = ProsodyAnalyzer()
let encoder = JSONEncoder()

for target in targets.sorted(by: { $0.name < $1.name }) {
    guard let segments = segmentsBySHA[target.sha], segments.isEmpty == false else {
        print("skip \(target.name) — no transcript")
        continue
    }
    guard let audio = locateAudio(target.storedFilename) else {
        print("skip \(target.name) — audio not found (\(target.storedFilename))")
        continue
    }

    let started = Date()
    do {
        let profile = try analyzer.analyze(url: audio, segments: segments)
        let destination = outputDirectory.appending(path: "\(target.sha).json")
        try encoder.encode(profile).write(to: destination, options: .atomic)
        let speaking = profile.speechRateCurve.filter { $0 > 0 }
        let average = speaking.isEmpty ? 0 : speaking.reduce(0, +) / Double(speaking.count)
        print(
            "ok   \(target.name) — \(profile.speechRateCurve.count) windows, "
                + "\(profile.pauses.count) pauses, avg \(Int(average)) wpm, "
                + "\(Int(Date().timeIntervalSince(started)))s"
        )
    } catch {
        print("fail \(target.name) — \(error.localizedDescription)")
    }
}
