//
//  AudioTitleNormalizer.swift
//  Ilumionate
//
//  One normalisation, shared by playlist matching and duplicate detection.
//
//  These two used to normalise separately, and the extension-stripping half of
//  the job was open-coded in six or more places (see the note at
//  `IlumionateTests.swift:824`). Two callers disagreeing about what counts as
//  the same title is exactly how a duplicate slips through.
//

import Foundation

nonisolated enum AudioTitleNormalizer {

    /// Production noise that says nothing about which recording this is.
    private static let disposableSuffixes: Set<String> = [
        "audio", "final", "hq", "official", "remastered",
        "mp3", "m4a", "wav", "aac", "flac", "v2", "320kbps"
    ]

    /// Hoisted deliberately. A regex literal written inline is built where it
    /// appears, so it was recompiled on every call — and `DuplicateAudioIndex`
    /// calls this once per library file, which is ~100 compilations per import
    /// on a real library. A Time Profiler trace showed the Swift Regex parser
    /// (`Parser.parseCustomCharacterClass` and friends) running on the main
    /// thread here. It was a small share of the total, but it is pure waste.
    // Swift's Regex value is immutable here but does not conform to Sendable.
    // The unsafe annotation is limited to this read-only compiled cache.
    nonisolated(unsafe) private static let separators = /[^a-z0-9]+/

    /// A filename or title reduced to lowercase, unaccented, punctuation-free
    /// tokens.
    ///
    /// A leading track number is **kept**. Stripping it — which is what this
    /// code used to do — collapsed `01 Bambi Sleep` and `02 Bambi Sleep` onto
    /// the same key, so the importer could not tell one entry of a numbered
    /// series from another and downloaded a second copy of a track it had.
    static func normalize(_ value: String) -> String {
        tokens(in: value).joined(separator: " ")
    }

    /// The track position a name opens with, when it opens with one.
    ///
    /// Capped at three digits: four or more is a year or a catalogue number,
    /// not a position in a playlist.
    static func leadingTrackNumber(_ value: String) -> Int? {
        guard let first = tokens(in: value).first,
              first.count <= 3,
              first.allSatisfy(\.isNumber) else {
            return nil
        }
        return Int(first)
    }

    private static func tokens(in value: String) -> [String] {
        // `URL(filePath: "")` resolves against the current working directory,
        // so an empty name would tokenise to whatever that directory is called
        // — a real-looking token that could match an unrelated library entry.
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let base = URL(filePath: value)
            .deletingPathExtension()
            .lastPathComponent
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()

        var tokens = base
            .replacing(Self.separators, with: " ")
            .split(separator: " ")
            .map(String.init)

        while let last = tokens.last, disposableSuffixes.contains(last) {
            tokens.removeLast()
        }
        return tokens
    }
}
