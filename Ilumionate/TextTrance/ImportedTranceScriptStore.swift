//  ImportedTranceScriptStore.swift
//  Ilumionate
//
//  Durable storage for user-imported Text Trance scripts.

import Foundation
import os

@MainActor
@Observable
final class ImportedTranceScriptStore {
    static let shared = ImportedTranceScriptStore()

    private(set) var importedScripts: [TranceScript] = []

    private let directoryURL: URL
    private let fileURL: URL

    init(directoryURL: URL = URL.applicationSupportDirectory.appending(path: "TextTrance", directoryHint: .isDirectory),
         filename: String = "imported-scripts.json") {
        self.directoryURL = directoryURL
        self.fileURL = directoryURL.appending(path: filename)
        load()
    }

    func save(_ script: TranceScript) throws {
        try TranceScriptLibrary.validate(script)

        var updatedScripts = importedScripts
        updatedScripts.removeAll { existing in
            existing.id == script.id || hasSameImportedSource(existing, script)
        }
        updatedScripts.insert(script, at: 0)
        try persist(updatedScripts)
        importedScripts = updatedScripts
    }

    func delete(scriptID: String) throws {
        let updatedScripts = importedScripts.filter { $0.id != scriptID }
        try persist(updatedScripts)
        importedScripts = updatedScripts
    }

    func reset() throws {
        try persist([])
        importedScripts = []
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranceScript].self, from: data) else {
            importedScripts = []
            return
        }

        importedScripts = decoded.filter { script in
            do {
                try TranceScriptLibrary.validate(script)
                return true
            } catch {
                Log.audio.info("[ImportedTranceScriptStore] Skipping \(script.id): \(error.localizedDescription)")
                return false
            }
        }
    }

    private func persist(_ scripts: [TranceScript]) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(scripts)
        try data.write(to: fileURL, options: .atomic)
    }

    private func hasSameImportedSource(_ lhs: TranceScript, _ rhs: TranceScript) -> Bool {
        guard lhs.source.kind == .importedWeb,
              rhs.source.kind == .importedWeb,
              let lhsGenerator = lhs.source.generator,
              let rhsGenerator = rhs.source.generator else {
            return false
        }
        return lhsGenerator == rhsGenerator
    }
}
