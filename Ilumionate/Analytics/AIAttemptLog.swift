//
//  AIAttemptLog.swift
//  Ilumionate
//
//  Durable because the experiment it serves can be interrupted by the very
//  thing being investigated: the app sits near 628 MB during analysis
//  (ERR-009) and an iOS jetsam kill mid-run would otherwise take the samples
//  with it.
//

import Foundation
import os

actor AIAttemptLog {

    static let shared = AIAttemptLog()

    /// Enough to compare two activation states without growing unbounded. The
    /// oldest entries fall off the front.
    private static let capacity = 200

    private let storeURL: URL
    private var records: [AIAttemptRecord]

    init(storeURL: URL = AppStoragePaths.analysisDirectory
        .appending(path: "AIAttempts.json")) {
        self.storeURL = storeURL
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([AIAttemptRecord].self, from: data) {
            records = decoded
        } else {
            records = []
        }
    }

    func record(_ attempt: AIAttemptRecord) {
        records.append(attempt)
        if records.count > Self.capacity {
            records.removeFirst(records.count - Self.capacity)
        }
        persist()

        let summary = AIAttemptSummary(records: records)
        Log.analysis.info("""
        🎛 \(attempt.activationState.rawValue, privacy: .public) · \
        \(attempt.usedAI ? "used AI" : "fell back (\(attempt.diagnosis?.rawValue ?? "unknown"))", privacy: .public) \
        — \(summary.description, privacy: .public)
        """)
    }

    func summary() -> AIAttemptSummary {
        AIAttemptSummary(records: records)
    }

    func reset() {
        records = []
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(records).write(to: storeURL, options: .atomic)
        } catch {
            // A diagnostic that cannot save is not worth failing an analysis
            // over, but silence is how ERR-005 and ERR-013 happened.
            Log.analysis.error("❌ Could not save AI attempt log: \(error.localizedDescription)")
        }
    }
}
