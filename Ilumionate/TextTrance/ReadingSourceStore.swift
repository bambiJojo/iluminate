//
//  ReadingSourceStore.swift
//  Ilumionate
//
//  Local persistence for websites the user explicitly adds to Reader.

import Foundation
import Observation

enum ReadingSourceStoreError: LocalizedError, Equatable {
    case emptyTitle
    case invalidURL
    case unsupportedScheme
    case duplicateURL

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "Add a source name."
        case .invalidURL:
            "Enter a valid website address."
        case .unsupportedScheme:
            "Use an http or https website."
        case .duplicateURL:
            "That website is already in Custom Sources."
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

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "readingSourceCustomLinks"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    var allSources: [ReadingSource] {
        customSources
    }

    func sources(in category: ReadingSourceCategory?) -> [ReadingSource] {
        guard let category else { return customSources }
        return customSources.filter { $0.category == category }
    }

    @discardableResult
    func addCustomSource(
        title rawTitle: String,
        urlString rawURL: String,
        summary rawSummary: String = ""
    ) throws -> ReadingSource {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else {
            throw ReadingSourceStoreError.emptyTitle
        }

        let url = try Self.normalizedURL(from: rawURL)
        guard containsURL(url) == false else {
            throw ReadingSourceStoreError.duplicateURL
        }

        let source = ReadingSource(
            id: "custom-\(UUID().uuidString)",
            title: title,
            url: url,
            category: .userAdded,
            summary: rawSummary.trimmingCharacters(in: .whitespacesAndNewlines),
            licenseKind: .userProvided,
            licenseNote: "Only import content you created or have permission to save.",
            contentNote: "Private custom source.",
            importPolicy: .userInitiatedImport,
            contentRating: .mixed,
            isCurated: false,
            addedDate: .now
        )
        customSources.insert(source, at: 0)
        sortSources()
        persist()
        UsageAnalytics.shared.readingSourceImported()
        return source
    }

    func deleteCustomSource(id: ReadingSource.ID) {
        customSources.removeAll { $0.id == id }
        persist()
    }

    func resetCustomSources() {
        customSources = []
        persist()
    }

    static func normalizedURL(from rawValue: String) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            throw ReadingSourceStoreError.invalidURL
        }

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
              host.isEmpty == false,
              components.user == nil,
              components.password == nil else {
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
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url.absoluteString.lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        }
        return (components.url?.absoluteString ?? url.absoluteString).lowercased()
    }

    private func containsURL(_ url: URL) -> Bool {
        let key = Self.comparisonKey(for: url)
        return customSources.contains { Self.comparisonKey(for: $0.url) == key }
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ReadingSource].self, from: data) else {
            customSources = []
            return
        }

        var seenURLs: Set<String> = []
        customSources = decoded.compactMap { stored in
            guard stored.isCurated == false,
                  let url = try? Self.normalizedURL(from: stored.url.absoluteString) else {
                return nil
            }
            let key = Self.comparisonKey(for: url)
            guard seenURLs.insert(key).inserted else { return nil }

            var migrated = stored
            migrated.url = url
            migrated.category = .userAdded
            migrated.licenseKind = .userProvided
            migrated.licenseNote = "Only import content you created or have permission to save."
            migrated.contentNote = "Private custom source."
            migrated.importPolicy = .userInitiatedImport
            migrated.isCurated = false
            return migrated
        }
        sortSources()
        persist()
    }

    private func sortSources() {
        customSources.sort { lhs, rhs in
            (lhs.addedDate ?? .distantPast) > (rhs.addedDate ?? .distantPast)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(customSources) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
