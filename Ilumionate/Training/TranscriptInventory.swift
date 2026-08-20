//
//  TranscriptInventory.swift
//  Ilumionate
//
//  Which corpus files already have a cached transcript, and what order to work
//  through them in.
//
//  Transcribing a corpus is a long unattended job — WhisperKit takes minutes per
//  file — so the decisions are kept separate from the doing. Deciding what still
//  needs transcribing, and how to order a list for someone labelling, is worth
//  testing; driving a speech recogniser is not.
//

import Foundation

nonisolated enum CorpusSortOrder: String, CaseIterable, Sendable {
    case name
    case transcribedFirst
    case untranscribedFirst

    var label: String {
        switch self {
        case .name: "Name"
        case .transcribedFirst: "Transcribed first"
        case .untranscribedFirst: "Needs transcript first"
        }
    }
}

nonisolated enum TranscriptInventory {

    /// Transcripts are cached per audio hash, beside the exported dataset.
    static func cacheDirectory(in analyzerDatasetDirectory: URL) -> URL {
        analyzerDatasetDirectory
            .appending(path: "cache", directoryHint: .isDirectory)
            .appending(path: "transcripts", directoryHint: .isDirectory)
    }

    static func cacheURL(forHash hash: String, in analyzerDatasetDirectory: URL) -> URL {
        cacheDirectory(in: analyzerDatasetDirectory).appending(path: "\(hash).json")
    }

    /// A missing cache directory is an empty inventory, not an error — it is the
    /// normal state of a corpus nobody has transcribed yet.
    static func availableHashes(in analyzerDatasetDirectory: URL) -> Set<String> {
        let directory = cacheDirectory(in: analyzerDatasetDirectory)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return Set(
            contents
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )
    }

    /// The files still needing a transcript, in the order they should be done.
    ///
    /// Two corpus entries can point at the same audio, and transcribing it twice
    /// would repeat the slowest step in the job for nothing — so the work is
    /// keyed by hash, not by entry. A file with no hash cannot be located in the
    /// cache at all and is left out rather than attempted repeatedly.
    static func pending(_ files: [LabeledFile], transcribed: Set<String>) -> [LabeledFile] {
        var seen = transcribed
        return files.filter { file in
            let hash = file.audioSHA256
            guard hash.isEmpty == false, seen.contains(hash) == false else { return false }
            seen.insert(hash)
            return true
        }
    }

    /// Grouped by whether a transcript exists, alphabetical within each group so
    /// the list stays findable rather than reshuffling as transcripts arrive.
    static func sorted(
        _ files: [LabeledFile],
        by order: CorpusSortOrder,
        transcribed: Set<String>
    ) -> [LabeledFile] {
        func hasTranscript(_ file: LabeledFile) -> Bool {
            file.audioSHA256.isEmpty == false && transcribed.contains(file.audioSHA256)
        }
        func byName(_ lhs: LabeledFile, _ rhs: LabeledFile) -> Bool {
            lhs.audioFilename.localizedStandardCompare(rhs.audioFilename) == .orderedAscending
        }

        switch order {
        case .name:
            return files.sorted(by: byName)
        case .transcribedFirst:
            return files.sorted {
                hasTranscript($0) == hasTranscript($1) ? byName($0, $1) : hasTranscript($0)
            }
        case .untranscribedFirst:
            return files.sorted {
                hasTranscript($0) == hasTranscript($1) ? byName($0, $1) : hasTranscript($1)
            }
        }
    }
}
