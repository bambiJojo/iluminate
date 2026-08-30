//
//  BambiSafetyPolicy.swift
//  LumeLabel
//
//  Keeps audio the labeler has identified as unsafe to audition out of every
//  human-listening workflow.
//

import Foundation

nonisolated enum BambiSafetyPolicy {
    static let silverLabelPrefix = "Silver label: transcript-only Bambi derivation"

    static func requiresTranscriptOnlyLabeling(_ file: LabeledFile) -> Bool {
        requiresTranscriptOnlyLabeling(filename: file.audioFilename)
            || requiresTranscriptOnlyLabeling(filename: file.originalFilename)
    }

    static func requiresTranscriptOnlyLabeling(
        _ file: LabeledFile,
        bambiTranscriptHashes: Set<String>
    ) -> Bool {
        requiresTranscriptOnlyLabeling(file)
            || bambiTranscriptHashes.contains(file.audioSHA256)
    }

    static func requiresTranscriptOnlyLabeling(filename: String) -> Bool {
        containsBambi(filename)
    }

    static func transcriptHashesRequiringTranscriptOnlyLabeling(
        in files: [LabeledFile],
        datasetDirectory: URL
    ) -> Set<String> {
        var inspectedHashes: Set<String> = []
        var bambiHashes: Set<String> = []

        for file in files {
            let hash = file.audioSHA256
            guard hash.isEmpty == false, inspectedHashes.insert(hash).inserted else { continue }
            guard let transcription = try? TranscriptCacheStore.load(
                for: file,
                in: datasetDirectory
            ) else {
                continue
            }
            if requiresTranscriptOnlyLabeling(transcription: transcription) {
                bambiHashes.insert(hash)
            }
        }
        return bambiHashes
    }

    static func isTranscriptOnlySilver(_ file: LabeledFile) -> Bool {
        file.labelerNotes
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveHasPrefix(silverLabelPrefix)
    }

    private static func requiresTranscriptOnlyLabeling(
        transcription: AudioTranscriptionResult
    ) -> Bool {
        containsBambi(transcription.fullText)
            || transcription.segments.contains { containsBambi($0.text) }
    }

    private static func containsBambi(_ text: String) -> Bool {
        text.range(of: "bambi", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

private nonisolated extension String {
    func localizedCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        guard count >= prefix.count else { return false }
        return String(self.prefix(prefix.count)).localizedCaseInsensitiveCompare(prefix) == .orderedSame
    }
}
