//
//  TrainingCorpusManager.swift
//  Ilumionate
//
//  CRUD for ground-truth labeled audio files stored in Documents/TrainingCorpus/.
//

import Foundation
import Observation
import AVFoundation

@MainActor @Observable
final class TrainingCorpusManager {

    static let shared = TrainingCorpusManager()

    var labeledFiles: [LabeledFile] = []

    private let corpusDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus")
    private let audioDirectory: URL = URL.documentsDirectory.appending(path: "TrainingCorpus/Audio")

    private init() {
        ensureDirectories()
        loadAll()
    }

    // MARK: - Directory Setup

    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [corpusDirectory, audioDirectory] {
            if !fm.fileExists(atPath: dir.path()) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Load

    func loadAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: corpusDirectory, includingPropertiesForKeys: nil) else { return }
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        labeledFiles = jsonFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(LabeledFile.self, from: data)
        }.sorted { $0.labeledAt > $1.labeledAt }

        print("Loaded \(labeledFiles.count) labeled file(s)")
    }

    // MARK: - Save

    func save(_ file: LabeledFile) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(file)
        let url = corpusDirectory.appending(path: "\(file.id.uuidString).json")
        try data.write(to: url, options: .atomic)

        if let index = labeledFiles.firstIndex(where: { $0.id == file.id }) {
            labeledFiles[index] = file
        } else {
            labeledFiles.insert(file, at: 0)
        }
        print("Saved labeled file: \(file.audioFilename)")
    }

    // MARK: - Import Audio

    func importAudio(from sourceURL: URL) throws -> LabeledFile {
        let filename = sourceURL.lastPathComponent
        let destURL = audioDirectory.appending(path: filename)

        if !FileManager.default.fileExists(atPath: destURL.path()) {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        }

        let sha256 = LabeledFile.computeSHA256(url: destURL) ?? ""

        let file = LabeledFile(
            audioFilename: filename,
            audioDuration: 0,
            audioSHA256: sha256,
            expectedContentType: .hypnosis,
            expectedFrequencyBand: LabeledFile.FrequencyBand(lower: 0.5, upper: 10.0),
            phases: [],
            techniques: [],
            labeledAt: Date(),
            labelerNotes: ""
        )

        try save(file)
        return file
    }

    // MARK: - Delete

    func delete(_ file: LabeledFile) {
        let jsonURL = corpusDirectory.appending(path: "\(file.id.uuidString).json")
        try? FileManager.default.removeItem(at: jsonURL)

        let audioURL = audioDirectory.appending(path: file.audioFilename)
        try? FileManager.default.removeItem(at: audioURL)

        labeledFiles.removeAll { $0.id == file.id }
        print("Deleted labeled file: \(file.audioFilename)")
    }

    // MARK: - Audio URL

    func audioURL(for file: LabeledFile) -> URL {
        audioDirectory.appending(path: file.audioFilename)
    }
}
