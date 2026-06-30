//  TranceScriptLibrary.swift
//  Ilumionate
//
//  Discovers, decodes, and validates bundled Text Trance scripts. Mirrors the
//  LightScoreReader posture: malformed files are skipped with a log, never
//  crashing the picker.

import Foundation
import os

enum TranceScriptLibrary {

    static let currentSchemaVersion = 1
    private static let bundledScriptsSubdirectory = "TextTrance/Scripts"

    enum LibraryError: LocalizedError {
        case unsupportedSchemaVersion(Int)
        case emptySegments
        case emptySupportedArcs
        case missingIdentifier
        case nonPositiveWPMHint

        var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let v):
                return "Unsupported script schema version: \(v)"
            case .emptySegments:      return "Script has no segments"
            case .emptySupportedArcs: return "Script supports no arcs"
            case .missingIdentifier:  return "Script id/title is empty"
            case .nonPositiveWPMHint: return "Script has a non-positive baseWPM pacing hint"
            }
        }
    }

    static func parse(_ data: Data) throws -> TranceScript {
        let script = try JSONDecoder().decode(TranceScript.self, from: data)
        try validate(script)
        return script
    }

    static func validate(_ script: TranceScript) throws {
        guard script.schemaVersion == currentSchemaVersion else {
            throw LibraryError.unsupportedSchemaVersion(script.schemaVersion)
        }
        guard !script.id.isEmpty, !script.title.isEmpty else {
            throw LibraryError.missingIdentifier
        }
        guard !script.supportedArcs.isEmpty else {
            throw LibraryError.emptySupportedArcs
        }
        guard !script.segments.isEmpty else {
            throw LibraryError.emptySegments
        }
        // Every segment that provides a pacing hint must have a positive WPM;
        // segments without a hint use the engine's depth-derived default.
        guard script.segments.compactMap(\.pacing).allSatisfy({ $0.baseWPM > 0 }) else {
            throw LibraryError.nonPositiveWPMHint
        }
    }

    /// Load every valid `.json` script in a directory, skipping invalid ones.
    static func loadAll(inDirectory dir: URL) -> [TranceScript] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }

        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                do {
                    return try parse(Data(contentsOf: url))
                } catch {
                    Log.audio.info("[TranceScriptLibrary] Skipping \(url.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }
    }

    /// Discover bundled scripts shipped in the app bundle. Non-script JSON
    /// (e.g. light-session files) simply fails decoding and is excluded.
    static func bundled(in bundle: Bundle = .main) -> [TranceScript] {
        let scripts = bundledJSONScripts(in: bundle, subdirectory: bundledScriptsSubdirectory)
        if scripts.isEmpty == false { return scripts }

        // Legacy fallback for older project layouts that copied JSON files to
        // the bundle root.
        return bundledJSONScripts(in: bundle, subdirectory: nil)
    }

    private static func bundledJSONScripts(
        in bundle: Bundle,
        subdirectory: String?
    ) -> [TranceScript] {
        guard let urls = bundle.urls(
            forResourcesWithExtension: "json", subdirectory: subdirectory
        ) else { return [] }

        return urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in try? parse(Data(contentsOf: url)) }
    }
}
