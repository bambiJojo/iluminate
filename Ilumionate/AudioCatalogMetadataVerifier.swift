//
//  AudioCatalogMetadataVerifier.swift
//  Ilumionate
//

import Foundation

/// Confirms spoken title and creator guesses against Apple's public audio catalog.
nonisolated enum AudioCatalogMetadataVerifier {
    struct Candidate: Equatable, Sendable {
        let title: String
        let creator: String
        let album: String?
        let genre: String?
        let duration: TimeInterval?
        let url: URL?
    }

    private struct SearchResponse: Decodable {
        let results: [SearchResult]
    }

    private struct SearchResult: Decodable {
        let trackName: String?
        let collectionName: String?
        let artistName: String?
        let primaryGenreName: String?
        let trackTimeMillis: Double?
        let trackViewUrl: URL?
        let collectionViewUrl: URL?
    }

    static func verifiedMetadata(
        for introduction: AudioTrackMetadata?,
        duration: TimeInterval,
        session: URLSession = .shared
    ) async -> AudioTrackMetadata? {
        guard let spokenTitle = introduction?.generatedTitle,
              let spokenCreator = introduction?.creator else {
            return nil
        }

        let mediaTypes = ["audiobook", "podcast", "music"]
        let candidates = await withTaskGroup(of: [Candidate].self) { group in
            for media in mediaTypes {
                group.addTask {
                    await search(
                        title: spokenTitle,
                        creator: spokenCreator,
                        media: media,
                        session: session
                    )
                }
            }

            var combined: [Candidate] = []
            for await results in group {
                combined.append(contentsOf: results)
            }
            return combined
        }

        guard let match = bestMatch(
            title: spokenTitle,
            creator: spokenCreator,
            duration: duration,
            candidates: candidates
        ) else {
            return nil
        }

        return AudioTrackMetadata(
            generatedTitle: match.title,
            creator: match.creator,
            album: match.album,
            genre: match.genre,
            confidence: 0.97,
            verificationSource: "Apple catalog",
            verificationURL: match.url
        )
    }

    static func bestMatch(
        title: String,
        creator: String,
        duration: TimeInterval,
        candidates: [Candidate]
    ) -> Candidate? {
        candidates.compactMap { candidate -> (Candidate, Double)? in
            let titleScore = titleSimilarity(title, candidate.title)
            let creatorScore = AudioIntroductionMetadataExtractor.similarity(
                creator, candidate.creator
            )
            guard titleScore >= 0.74, creatorScore >= 0.78 else { return nil }

            var score = titleScore * 0.58 + creatorScore * 0.42
            if duration > 0, let candidateDuration = candidate.duration, candidateDuration > 0 {
                let difference = abs(duration - candidateDuration) / max(duration, candidateDuration)
                score += max(0, 1 - difference) * 0.05
            }
            guard score >= 0.80 else { return nil }
            return (candidate, score)
        }
        .max { $0.1 < $1.1 }?
        .0
    }

    private static func search(
        title: String,
        creator: String,
        media: String,
        session: URLSession
    ) async -> [Candidate] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(creator) \(title)"),
            URLQueryItem(name: "media", value: media),
            URLQueryItem(name: "country", value: "US"),
            URLQueryItem(name: "limit", value: "20")
        ]
        guard let url = components?.url else { return [] }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return []
            }
            return try JSONDecoder().decode(SearchResponse.self, from: data).results.flatMap {
                candidates(from: $0)
            }
        } catch {
            return []
        }
    }

    private static func candidates(from result: SearchResult) -> [Candidate] {
        guard let creator = AudioTrackMetadata.cleaned(result.artistName) else { return [] }
        let collection = AudioTrackMetadata.cleaned(result.collectionName)
        let titles = [result.trackName, result.collectionName]
        let duration = result.trackTimeMillis.map { $0 / 1_000 }
        let url = result.trackViewUrl ?? result.collectionViewUrl

        var seen = Set<String>()
        return titles.compactMap { rawTitle in
            guard let title = AudioTrackMetadata.cleaned(rawTitle),
                  seen.insert(title.lowercased()).inserted else {
                return nil
            }
            return Candidate(
                title: title,
                creator: creator,
                album: collection == title ? nil : collection,
                genre: AudioTrackMetadata.cleaned(result.primaryGenreName),
                duration: duration,
                url: url
            )
        }
    }

    private static func titleSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let base = AudioIntroductionMetadataExtractor.similarity(lhs, rhs)
        let leftWords = normalizedWords(lhs)
        let rightWords = normalizedWords(rhs)
        guard leftWords.count >= 2, rightWords.count >= 2 else { return base }
        let coverage = Double(leftWords.intersection(rightWords).count)
            / Double(min(leftWords.count, rightWords.count))
        return max(base, coverage)
    }

    private static func normalizedWords(_ value: String) -> Set<String> {
        Set(value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
    }
}
