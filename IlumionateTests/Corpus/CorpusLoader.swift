//  CorpusLoader.swift
//  IlumionateTests
//
//  Loads corpus JSON from the repo-root `Corpus/<subdirectory>/` directory.
//  Uses a source-file-relative path so no Xcode resource bundling is needed;
//  tests run on the build machine where the checkout is present.
//
import Foundation

enum CorpusLoader {

    /// Repo-root `Corpus/` directory, resolved relative to this source file.
    /// This file lives at <repo>/IlumionateTests/Corpus/CorpusLoader.swift,
    /// so the repo root is three parents up.
    static var corpusRoot: URL {
        URL(filePath: #filePath)            // .../IlumionateTests/Corpus/CorpusLoader.swift
            .deletingLastPathComponent()    // .../IlumionateTests/Corpus
            .deletingLastPathComponent()    // .../IlumionateTests
            .deletingLastPathComponent()    // .../<repo root>
            .appending(path: "Corpus")
    }

    static func load(subdirectory: String) throws -> [CorpusCase] {
        let dir = corpusRoot.appending(path: subdirectory)
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }

        let urls = try fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )
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

    enum CorpusLoadError: Error, CustomStringConvertible {
        case decodeFailed(file: String, underlying: Error)
        var description: String {
            switch self {
            case let .decodeFailed(file, underlying):
                return "Failed to decode corpus file \(file): \(underlying)"
            }
        }
    }
}
