//
//  CableAudioImportResult.swift
//  Ilumionate
//

import Foundation

nonisolated struct CableAudioImportFailure: Sendable, Equatable {
    let filename: String
    let message: String
}

nonisolated struct CableAudioImportResult: Sendable {
    var imported: [AudioFile] = []
    var duplicates: [String] = []
    var rejected: [String] = []
    var pending: [String] = []
    var failures: [CableAudioImportFailure] = []
    /// Files admitted by an earlier scan in this session. The watcher imports
    /// automatically, so a later manual check often finds nothing *new* — and
    /// saying "connect Finder" then reads as failure when the transfer in fact
    /// succeeded moments earlier.
    var priorImportCount = 0

    /// Folds a recheck pass into the running total. Outcomes accumulate, but
    /// `pending` is replaced rather than appended: it describes what is *still*
    /// copying, so a file that has since landed must stop being listed.
    mutating func merge(_ other: CableAudioImportResult) {
        imported.append(contentsOf: other.imported)
        duplicates.append(contentsOf: other.duplicates)
        rejected.append(contentsOf: other.rejected)
        failures.append(contentsOf: other.failures)
        pending = other.pending
    }

    var hasActivity: Bool {
        imported.isEmpty == false
            || duplicates.isEmpty == false
            || rejected.isEmpty == false
            || pending.isEmpty == false
            || failures.isEmpty == false
    }

    /// Counts what this transfer produced, whether admitted by this scan or by
    /// an earlier one in the same session. The watcher usually gets there
    /// first, so a user who taps Check afterwards is asking about the same
    /// batch and should be told it succeeded.
    private var addedCount: Int { imported.count + priorImportCount }

    var title: String {
        // The title is what a user acts on. "No New Audio Found" above a body
        // explaining that five files just landed reads as failure.
        if addedCount > 0, failures.isEmpty {
            let subject = noun(addedCount, singular: "Audio File", plural: "Audio Files")
            return "\(addedCount) \(subject) Added"
        }
        if failures.isEmpty == false {
            return "Audio Transfer Failed"
        }
        if duplicates.isEmpty == false || rejected.isEmpty == false {
            return "Audio Transfer Needs Review"
        }
        if pending.isEmpty == false {
            return "Audio Transfer in Progress"
        }
        return "No New Audio Found"
    }

    var message: String {
        var lines: [String] = []

        if imported.isEmpty == false {
            let subject = noun(imported.count, singular: "file is", plural: "files are")
            lines.append("\(imported.count) \(subject) ready in your Library.")
        }
        if duplicates.isEmpty == false {
            let subject = noun(
                duplicates.count,
                singular: "duplicate was",
                plural: "duplicates were"
            )
            lines.append("\(duplicates.count) \(subject) moved to _Needs Review/Duplicates.")
        }
        if rejected.isEmpty == false {
            let subject = noun(rejected.count, singular: "file was", plural: "files were")
            lines.append("\(rejected.count) unsupported or invalid \(subject) moved to _Needs Review.")
        }
        if pending.isEmpty == false {
            let subject = noun(pending.count, singular: "file is", plural: "files are")
            lines.append("\(pending.count) \(subject) still copying and will be checked again later.")
        }
        if failures.isEmpty == false {
            let first = failures[0]
            lines.append("\(first.filename): \(first.message)")
            if failures.count > 1 {
                let remaining = failures.count - 1
                let subject = noun(remaining, singular: "file needs", plural: "files need")
                lines.append("\(remaining) more \(subject) attention.")
            }
        }
        if lines.isEmpty {
            if priorImportCount > 0 {
                let subject = noun(priorImportCount, singular: "file is", plural: "files are")
                lines.append(
                    "Nothing new to import. \(priorImportCount) transferred \(subject) already in your Library."
                )
            } else {
                lines.append("Connect your iPhone, open Finder, select it, and drag audio onto LumeSync in the Files tab. Then check again.")
            }
        }

        return lines.joined(separator: "\n\n")
    }

    private func noun(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? singular : plural
    }
}
