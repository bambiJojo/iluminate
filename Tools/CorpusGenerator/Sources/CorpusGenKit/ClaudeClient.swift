//  ClaudeClient.swift
//  CorpusGenKit
//
//  Builds Anthropic Messages API requests (seed excerpts live in a cacheable
//  system prefix per the claude-api skill) and performs them with URLSession.
//  ClaudeResponder conforms to BlockResponder for real generation.
//
import Foundation
import CorpusKit

public struct ClaudeRequestBuilder: Sendable {
    public let model: String
    public let maxTokens: Int
    public init(model: String, maxTokens: Int = 1024) {
        self.model = model; self.maxTokens = maxTokens
    }

    /// JSON body for one phase-block request. Seeds go in the system prefix
    /// with cache_control so the identical prefix is billed once across calls.
    public func body(for request: BlockRequest) -> [String: Any] {
        var system: [[String: Any]] = [[
            "type": "text",
            "text": Self.styleGuide,
        ]]
        if !request.seeds.isEmpty {
            let seedText = request.seeds
                .map { "## \($0.phase.displayName) — real example\n\($0.excerpt)" }
                .joined(separator: "\n\n")
            system.append([
                "type": "text",
                "text": "Use these real transcript excerpts as style references:\n\n\(seedText)",
                "cache_control": ["type": "ephemeral"],
            ])
        }

        let prior = request.priorPhases.map(\.displayName).joined(separator: " → ")
        let ambiguityHint = Self.ambiguityHint(request.ambiguity)
        let user = """
        Write the spoken transcript for ONE phase of a hypnosis session.
        Phase: \(request.phase.displayName).
        Approximate spoken length: \(Int(request.durationSec)) seconds (~\(Int(request.durationSec * 2.3)) words).
        Prior phases so far: \(prior.isEmpty ? "none" : prior).
        \(ambiguityHint)
        Output ONLY the spoken words for this phase — no headings, no stage directions, no quotation marks.
        """

        return [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
    }

    static func ambiguityHint(_ level: CorpusAmbiguityLevel) -> String {
        switch level {
        case .low:
            return "Use direct, recognizable language for this phase, with clear cues."
        case .medium:
            return "Paraphrase and use indirect, Ericksonian language; avoid obvious keywords."
        case .high:
            return "Use fuzzy, metaphor-heavy transitions that bleed into adjacent phases; make boundaries hard to place."
        case .unspecified:
            return ""
        }
    }

    static let styleGuide = """
    You are scripting authentic hypnosis/trance session transcripts for a research \
    corpus. Write natural spoken language as a hypnotist would actually speak it, \
    pacing it to the requested duration. Stay in the voice of a single narrator.
    """
}

public enum ClaudeClientError: Error, CustomStringConvertible {
    case missingAPIKey
    case httpError(status: Int, body: String)
    case malformedResponse
    public var description: String {
        switch self {
        case .missingAPIKey: return "ANTHROPIC_API_KEY is not set"
        case .httpError(let s, let b): return "Anthropic API HTTP \(s): \(b)"
        case .malformedResponse: return "Could not parse Anthropic API response"
        }
    }
}

public struct ClaudeResponder: BlockResponder {
    private let builder: ClaudeRequestBuilder
    private let apiKey: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session: URLSession

    public init(model: String, apiKey: String, session: URLSession = .shared) {
        self.builder = ClaudeRequestBuilder(model: model)
        self.apiKey = apiKey
        self.session = session
    }

    /// Reads ANTHROPIC_API_KEY from the environment; nil if unset.
    public static func fromEnvironment(model: String) -> ClaudeResponder? {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty else {
            return nil
        }
        return ClaudeResponder(model: model, apiKey: key)
    }

    public func text(for request: BlockRequest) async throws -> String {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: builder.body(for: request))

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.malformedResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClaudeClientError.httpError(status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let first = content.first(where: { ($0["type"] as? String) == "text" }),
            let text = first["text"] as? String
        else { throw ClaudeClientError.malformedResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
