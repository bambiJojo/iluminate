//
//  AnalyzerConfigLoader.swift
//  Ilumionate
//
//  Loads AnalyzerConfig from Documents (trained) or Bundle (default).
//

import Foundation
import os

nonisolated enum AnalyzerConfigLoader {

    static let documentsConfigURL: URL =
        URL.documentsDirectory.appending(path: "AnalyzerConfig.json")
    static let minimumPublishedConfigFitness = 0.30

    private static let baseConfigCache = AnalyzerConfigCache()

    /// Loads the best available config: trained version from Documents,
    /// falling back to the bundled default.
    static func load() -> AnalyzerConfig {
        applyRuntimePreferences(to: baseConfigCache.value(load: loadBaseConfigFromDisk))
    }

    private static func loadBaseConfigFromDisk() -> AnalyzerConfig {
        // 1. Try trained config in Documents
        if let data = try? Data(contentsOf: documentsConfigURL),
           let config = try? JSONDecoder().decode(AnalyzerConfig.self, from: data) {
            if isUsablePublishedConfig(config) {
                Log.analysis.info("📐 Loaded trained AnalyzerConfig (gen \(config.generation), fitness \(config.fitness))")
                return config
            }
            Log.analysis.warning("Ignoring trained AnalyzerConfig at \(documentsConfigURL.path(), privacy: .public); fitness \(config.fitness, privacy: .public) is below minimum \(minimumPublishedConfigFitness, privacy: .public)")
        }

        // 2. Fall back to bundled default
        if let url = Bundle.main.url(forResource: "AnalyzerConfig_default", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(AnalyzerConfig.self, from: data) {
            Log.analysis.info("📐 Loaded default AnalyzerConfig from bundle")
            return config
        }

        // 3. Last resort — should never happen in production
        fatalError("No AnalyzerConfig found in Documents or Bundle — app cannot start")
    }

    static func isUsablePublishedConfig(_ config: AnalyzerConfig) -> Bool {
        config.fitness.isFinite && config.fitness >= minimumPublishedConfigFitness
    }

    /// Saves a trained config to Documents for the app to pick up.
    static func save(_ config: AnalyzerConfig) throws {
        try save(config, to: documentsConfigURL)
    }

    /// Saves a trained config to an explicit location for tooling/export workflows.
    static func save(_ config: AnalyzerConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
        if url.standardizedFileURL == documentsConfigURL.standardizedFileURL {
            baseConfigCache.update(config)
        }
        Log.analysis.info("💾 Saved AnalyzerConfig (gen \(config.generation)) to \(url.path())")
    }

    private static func applyRuntimePreferences(to config: AnalyzerConfig) -> AnalyzerConfig {
        var config = config
        if let sourceProfile = CorpusSourceProfile.storedSelection() {
            config.corpusLearning.sourceProfile = sourceProfile
        }
        return config
    }
}

private nonisolated final class AnalyzerConfigCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedConfig: AnalyzerConfig?

    func value(load: () -> AnalyzerConfig) -> AnalyzerConfig {
        lock.lock()
        if let cachedConfig {
            lock.unlock()
            return cachedConfig
        }
        lock.unlock()

        let loadedConfig = load()

        lock.lock()
        defer { lock.unlock() }
        if let cachedConfig {
            return cachedConfig
        }
        cachedConfig = loadedConfig
        return loadedConfig
    }

    func update(_ config: AnalyzerConfig) {
        lock.lock()
        cachedConfig = config
        lock.unlock()
    }
}
