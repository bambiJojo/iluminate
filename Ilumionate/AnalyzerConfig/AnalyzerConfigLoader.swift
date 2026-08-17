//
//  AnalyzerConfigLoader.swift
//  Ilumionate
//
//  Loads AnalyzerConfig from private app storage (trained) or Bundle (default).
//

import Foundation
import os

nonisolated enum AnalyzerConfigLoader {

    static let documentsConfigURL: URL =
        URL.documentsDirectory.appending(path: "AnalyzerConfig.json")
    private static var appConfigURL: URL {
        PrivateStorageMigration.migrateItemIfNeeded(
            from: documentsConfigURL,
            to: AppStoragePaths.analyzerConfig
        )
    }
    static let minimumPublishedConfigFitness = 0.30

    private static let baseConfigCache = AnalyzerConfigCache()

    /// Loads the best available config: trained version from Documents,
    /// falling back to the bundled default.
    static func load() -> AnalyzerConfig {
        applyRuntimePreferences(to: baseConfigCache.value(load: loadBaseConfigFromDisk))
    }

    private static func loadBaseConfigFromDisk() -> AnalyzerConfig {
        // 1. Try the trained config in private app storage.
        let configURL = appConfigURL
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(AnalyzerConfig.self, from: data) {
            if isUsablePublishedConfig(config) {
                Log.analysis.info("📐 Loaded trained AnalyzerConfig (gen \(config.generation), fitness \(config.fitness))")
                return config
            }
            Log.analysis.warning("Ignoring trained AnalyzerConfig at \(configURL.path(), privacy: .public); fitness \(config.fitness, privacy: .public) is below minimum \(minimumPublishedConfigFitness, privacy: .public)")
        }

        // 2. Fall back to bundled default
        if let url = Bundle.main.url(forResource: "AnalyzerConfig_default", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(AnalyzerConfig.self, from: data) {
            Log.analysis.info("📐 Loaded default AnalyzerConfig from bundle")
            return config
        }

        // 3. Last resort — should never happen in production
        fatalError("No AnalyzerConfig found in app storage or Bundle — app cannot start")
    }

    static func isUsablePublishedConfig(_ config: AnalyzerConfig) -> Bool {
        config.fitness.isFinite && config.fitness >= minimumPublishedConfigFitness
    }

    /// Saves a trained config to private app storage for the app to pick up.
    static func save(_ config: AnalyzerConfig) throws {
        try save(config, to: appConfigURL)
    }

    /// Saves a trained config to an explicit location for tooling/export workflows.
    static func save(_ config: AnalyzerConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        // Do not evaluate `appConfigURL` here: doing so would migrate a config
        // that an explicit tooling/export call intentionally wrote to
        // Documents. Only the app's private destination updates this cache.
        if url.standardizedFileURL == AppStoragePaths.analyzerConfig.standardizedFileURL {
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
