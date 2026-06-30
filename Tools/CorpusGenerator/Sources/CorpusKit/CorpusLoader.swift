//  CorpusLoader.swift
//  CorpusKit
//
//  Loads corpus JSON from the repo-root `Corpus/<subdirectory>/` directory
//  using a source-file-relative path (no resource bundling). The harness and
//  the generator both resolve the same repo-root `Corpus/`.
//
import Foundation

public enum CorpusLoader {

    /// Repo-root `Corpus/` directory, resolved relative to this source file.
    /// This file lives at
    ///   <repo>/Tools/CorpusGenerator/Sources/CorpusKit/CorpusLoader.swift
    /// so the repo root is five parents up.
    public static var corpusRoot: URL {
        if let configuredRoot = ProcessInfo.processInfo.environment["ILUMIONATE_CORPUS_ROOT"],
           configuredRoot.isEmpty == false {
            return URL(filePath: configuredRoot, directoryHint: .isDirectory)
        }
        return URL(filePath: #filePath)     // .../Sources/CorpusKit/CorpusLoader.swift
            .deletingLastPathComponent()    // .../Sources/CorpusKit
            .deletingLastPathComponent()    // .../Sources
            .deletingLastPathComponent()    // .../CorpusGenerator
            .deletingLastPathComponent()    // .../Tools
            .deletingLastPathComponent()    // .../<repo root>
            .appending(path: "Corpus")
    }

    public static func load(subdirectory: String) throws -> [CorpusCase] {
        let dir = corpusRoot.appending(path: subdirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else {
            throw CorpusLoadError.directoryMissing(dir)
        }

        let urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let decoder = JSONDecoder()
        return try urls.map { url in
            let data = try Data(contentsOf: url)
            do {
                return try decoder.decode(CorpusCase.self, from: data)
            } catch {
                throw CorpusLoadError.decodeFailed(file: url.lastPathComponent, underlying: error)
            }
        }
    }

    public enum CorpusLoadError: Error, CustomStringConvertible {
        case directoryMissing(URL)
        case decodeFailed(file: String, underlying: Error)
        public var description: String {
            switch self {
            case let .directoryMissing(url):
                return "Corpus directory is missing: \(url.path())"
            case let .decodeFailed(file, underlying):
                return "Failed to decode corpus file \(file): \(underlying)"
            }
        }
    }
}
