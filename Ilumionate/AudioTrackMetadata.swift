//
//  AudioTrackMetadata.swift
//  Ilumionate
//

import Foundation

/// Metadata discovered from embedded audio tags and content analysis.
nonisolated struct AudioTrackMetadata: Codable, Equatable, Sendable {
    var embeddedTitle: String?
    var generatedTitle: String?
    var creator: String?
    var album: String?
    var genre: String?
    var themes: [String]
    var confidence: Double?
    var verificationSource: String?
    var verificationURL: URL?

    init(
        embeddedTitle: String? = nil,
        generatedTitle: String? = nil,
        creator: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        themes: [String] = [],
        confidence: Double? = nil,
        verificationSource: String? = nil,
        verificationURL: URL? = nil
    ) {
        self.embeddedTitle = Self.cleaned(embeddedTitle)
        self.generatedTitle = Self.cleaned(generatedTitle)
        self.creator = Self.cleaned(creator)
        self.album = Self.cleaned(album)
        self.genre = Self.cleaned(genre)
        self.themes = Self.cleanedThemes(themes)
        self.confidence = confidence.map { max(0, min(1, $0)) }
        self.verificationSource = Self.cleaned(verificationSource)
        self.verificationURL = verificationURL
    }

    var preferredTitle: String? {
        Self.cleaned(embeddedTitle) ?? Self.cleaned(generatedTitle)
    }

    var isEmpty: Bool {
        preferredTitle == nil && creator == nil && album == nil && genre == nil && themes.isEmpty
    }

    /// Keeps authoritative embedded tags while filling missing fields from analysis.
    func mergingAnalyzed(_ analyzed: AudioTrackMetadata?) -> AudioTrackMetadata {
        guard let analyzed else { return self }

        return AudioTrackMetadata(
            embeddedTitle: embeddedTitle,
            generatedTitle: analyzed.generatedTitle ?? generatedTitle,
            creator: creator ?? analyzed.creator,
            album: album ?? analyzed.album,
            genre: genre ?? analyzed.genre,
            themes: themes.isEmpty ? analyzed.themes : themes,
            confidence: analyzed.confidence ?? confidence,
            verificationSource: analyzed.verificationSource ?? verificationSource,
            verificationURL: analyzed.verificationURL ?? verificationURL
        )
    }

    /// Gives explicit spoken introductions priority over broader AI inference.
    func mergingIntroduction(_ introduction: AudioTrackMetadata?) -> AudioTrackMetadata {
        guard let introduction else { return self }
        return AudioTrackMetadata(
            embeddedTitle: embeddedTitle,
            generatedTitle: introduction.generatedTitle ?? generatedTitle,
            creator: introduction.creator ?? creator,
            album: album,
            genre: genre,
            themes: themes,
            confidence: max(confidence ?? 0, introduction.confidence ?? 0),
            verificationSource: verificationSource,
            verificationURL: verificationURL
        )
    }

    /// Replaces inferred fields with a high-confidence external catalog match.
    func mergingVerified(_ verified: AudioTrackMetadata?) -> AudioTrackMetadata {
        guard let verified, verified.verificationSource != nil else { return self }
        return AudioTrackMetadata(
            embeddedTitle: embeddedTitle,
            generatedTitle: verified.generatedTitle ?? generatedTitle,
            creator: verified.creator ?? creator,
            album: verified.album ?? album,
            genre: verified.genre ?? genre,
            themes: themes,
            confidence: verified.confidence ?? confidence,
            verificationSource: verified.verificationSource,
            verificationURL: verified.verificationURL
        )
    }

    static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func cleanedThemes(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let cleaned = cleaned(value) else { return nil }
            let key = cleaned.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return cleaned
        }
    }
}
