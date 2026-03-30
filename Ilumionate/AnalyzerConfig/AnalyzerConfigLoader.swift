//
//  AnalyzerConfigLoader.swift
//  Ilumionate
//
//  Loads AnalyzerConfig from Documents (trained) or Bundle (default).
//

import Foundation

enum AnalyzerConfigLoader {

    private static let documentsConfigURL: URL =
        URL.documentsDirectory.appending(path: "AnalyzerConfig.json")

    /// Loads the best available config: trained version from Documents,
    /// falling back to the bundled default.
    static func load() -> AnalyzerConfig {
        // 1. Try trained config in Documents
        if let data = try? Data(contentsOf: documentsConfigURL),
           let config = try? JSONDecoder().decode(AnalyzerConfig.self, from: data) {
            print("📐 Loaded trained AnalyzerConfig (gen \(config.generation), fitness \(config.fitness))")
            return config
        }

        // 2. Fall back to bundled default
        if let url = Bundle.main.url(forResource: "AnalyzerConfig_default", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(AnalyzerConfig.self, from: data) {
            print("📐 Loaded default AnalyzerConfig from bundle")
            return config
        }

        // 3. Last resort — should never happen in production
        fatalError("No AnalyzerConfig found in Documents or Bundle — app cannot start")
    }

    /// Saves a trained config to Documents for the app to pick up.
    static func save(_ config: AnalyzerConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: documentsConfigURL, options: .atomic)
        print("💾 Saved AnalyzerConfig (gen \(config.generation)) to Documents")
    }
}
