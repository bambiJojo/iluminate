//  SeedLibrary.swift
//  CorpusGenKit
//
//  Reads LumeLabel TrainingCorpus files (label JSON + SHA-keyed transcript
//  cache) and slices each transcript by its labeled phase anchors, yielding
//  real per-phase excerpts for few-shot seeding. Optional: a missing or empty
//  directory yields no seeds (zero-shot fallback).
//
import Foundation
import CorpusKit

public enum SeedLibrary {

    // Minimal decoders for the on-disk LumeLabel shapes.
    private struct LabelFile: Decodable {
        let audioSHA256: String
        let phases: [LabelPhase]
    }
    private struct LabelPhase: Decodable {
        let phase: String
        let startTime: TimeInterval
        let endTime: TimeInterval
    }
    private struct TranscriptFile: Decodable {
        let transcription: Transcription
        struct Transcription: Decodable {
            let segments: [Segment]
        }
        struct Segment: Decodable {
            let text: String
            let timestamp: TimeInterval
            let duration: TimeInterval
        }
    }

    /// Max characters kept per phase excerpt (keeps the prompt prefix bounded).
    static let maxExcerptChars = 1200

    public static func load(from directory: URL) throws -> [PhaseSeed] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        let transcriptsDir = directory
            .appending(path: "AnalyzerDataset")
            .appending(path: "cache")
            .appending(path: "transcripts")

        let labelURLs = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        var byPhase: [TrancePhase: String] = [:]   // first excerpt wins per phase

        for labelURL in labelURLs {
            guard let label = try? decoder.decode(LabelFile.self, from: Data(contentsOf: labelURL)) else {
                continue   // not a label file (e.g. a manifest) — skip
            }
            let transcriptURL = transcriptsDir.appending(path: "\(label.audioSHA256).json")
            guard fm.fileExists(atPath: transcriptURL.path),
                  let transcript = try? decoder.decode(TranscriptFile.self, from: Data(contentsOf: transcriptURL))
            else { continue }

            for labelPhase in label.phases {
                guard let phase = TrancePhase(rawValue: labelPhase.phase), byPhase[phase] == nil else { continue }
                let excerpt = transcript.transcription.segments
                    .filter { $0.timestamp >= labelPhase.startTime && $0.timestamp < labelPhase.endTime }
                    .map(\.text)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !excerpt.isEmpty else { continue }
                byPhase[phase] = String(excerpt.prefix(maxExcerptChars))
            }
        }

        return byPhase
            .map { PhaseSeed(phase: $0.key, excerpt: $0.value) }
            .sorted { $0.phase.rawValue < $1.phase.rawValue }
    }
}
