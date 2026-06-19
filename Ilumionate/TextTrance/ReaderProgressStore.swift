//  ReaderProgressStore.swift
//  Ilumionate
//
//  File-backed, per-script resume snapshots for the Text Trance reader.
//  Chosen over UserDefaults for testability (injectable directory) and to
//  avoid the write race seen with PlaylistStore. Entries expire after 30 days.

import Foundation

@MainActor
@Observable
final class ReaderProgressStore {
    static let shared = ReaderProgressStore()

    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60
    private let fileURL: URL
    private var entries: [String: ReaderResumeState] = [:]

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "TextTrance")) {
        self.fileURL = directory.appending(path: "reader-progress.json")
        load()
    }

    func resumeState(forScriptId id: String) -> ReaderResumeState? {
        entries[id]
    }

    func save(_ state: ReaderResumeState) {
        entries[state.scriptId] = state
        persist()
    }

    func clear(scriptId: String) {
        entries[scriptId] = nil
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: ReaderResumeState].self, from: data)
        else { return }
        let cutoff = Date.now.addingTimeInterval(-Self.maxAge)
        entries = decoded.filter { $0.value.savedAt >= cutoff }
        if entries.count != decoded.count { persist() }   // write back the pruned set
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Non-fatal: resume is a convenience, not core playback.
        }
    }
}
