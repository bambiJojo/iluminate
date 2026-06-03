//  CorpusWriter.swift
//  CorpusGenKit
//
//  Serializes a CorpusCase to <outDir>/<id>.json, creating the directory.
//
import Foundation
import CorpusKit

public enum CorpusWriter {
    public static func write(_ kase: CorpusCase, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = directory.appending(path: "\(kase.id).json")
        try encoder.encode(kase).write(to: url, options: .atomic)
        return url
    }
}
