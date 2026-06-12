//  ReadingSourceStore.swift
//  Ilumionate
//
//  Persists user-added reading source links. Curated sources are static so app
//  updates can revise them without migrating user data.

import Foundation

enum ReadingSourceStoreError: LocalizedError, Equatable {
    case emptyTitle
    case invalidURL
    case unsupportedScheme
    case duplicateURL

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Add a source name."
        case .invalidURL:
            return "Enter a valid website address."
        case .unsupportedScheme:
            return "Use an http or https link."
        case .duplicateURL:
            return "That source is already in your list."
        }
    }
}

@MainActor
@Observable
final class ReadingSourceStore {
    static let shared = ReadingSourceStore()

    private(set) var customSources: [ReadingSource] = []

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "readingSourceCustomLinks") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    var allSources: [ReadingSource] {
        ReadingSourceCatalog.curatedSources + customSources.sorted { lhs, rhs in
            (lhs.addedDate ?? .distantPast) > (rhs.addedDate ?? .distantPast)
        }
    }

    func sources(in category: ReadingSourceCategory?) -> [ReadingSource] {
        guard let category else { return allSources }
        return allSources.filter { $0.category == category }
    }

    @discardableResult
    func addCustomSource(title rawTitle: String,
                         urlString rawURL: String,
                         summary rawSummary: String = "") throws -> ReadingSource {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ReadingSourceStoreError.emptyTitle }

        let url = try Self.normalizedURL(from: rawURL)
        guard !containsURL(url) else { throw ReadingSourceStoreError.duplicateURL }

        let source = ReadingSource(
            id: "custom-\(UUID().uuidString)",
            title: title,
            url: url,
            category: .userAdded,
            summary: rawSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            licenseKind: .userProvided,
            licenseNote: "User-added link. Review site terms before importing or redistributing text.",
            contentNote: "Private custom source.",
            importPolicy: .linkOnly,
            contentRating: .mixed,
            isCurated: false,
            addedDate: Date()
        )
        customSources.append(source)
        persist()
        return source
    }

    func deleteCustomSource(id: String) {
        customSources.removeAll { $0.id == id && !$0.isCurated }
        persist()
    }

    func resetCustomSources() {
        customSources = []
        persist()
    }

    private func containsURL(_ url: URL) -> Bool {
        let normalized = Self.comparisonKey(for: url)
        return allSources.contains { Self.comparisonKey(for: $0.url) == normalized }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ReadingSource].self, from: data) else {
            return
        }
        customSources = decoded.filter { !$0.isCurated }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(customSources) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func normalizedURL(from rawValue: String) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ReadingSourceStoreError.invalidURL }

        // If the raw input already declares a scheme, reject anything that isn't
        // http(s) BEFORE the "no ://" heuristic can disguise it as a host.
        if let explicitScheme = URLComponents(string: value)?.scheme?.lowercased() {
            guard explicitScheme == "http" || explicitScheme == "https" else {
                throw ReadingSourceStoreError.unsupportedScheme
            }
        }

        let normalized = value.contains("://") ? value : "https://\(value)"

        guard var components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            throw ReadingSourceStoreError.invalidURL
        }

        components.scheme = scheme
        components.host = host
        guard let url = components.url else {
            throw ReadingSourceStoreError.invalidURL
        }
        return url
    }

    static func comparisonKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" {
            components.path = ""
        }
        return (components.url?.absoluteString ?? url.absoluteString).lowercased()
    }
}
