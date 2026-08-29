//
//  CableFileImportResult.swift
//  Ilumionate
//

import Foundation

nonisolated struct CableFileImportFailure: Sendable, Equatable {
    let filename: String
    let message: String
}

nonisolated struct CableFileImportResult: Sendable {
    var imported: [AudioFile] = []
    var importedDocuments: [ReadingDocument] = []
    var duplicates: [String] = []
    var rejected: [String] = []
    var pending: [String] = []
    var failures: [CableFileImportFailure] = []
    /// Files admitted by an earlier scan in this session. The watcher imports
    /// automatically, so a later manual check often finds nothing *new* — and
    /// saying "connect Finder" then reads as failure when the transfer in fact
    /// succeeded moments earlier.
    var priorImportCount = 0

    /// Folds a recheck pass into the running total. Outcomes accumulate, but
    /// `pending` is replaced rather than appended: it describes what is *still*
    /// copying, so a file that has since landed must stop being listed.
    mutating func merge(_ other: CableFileImportResult) {
        imported.append(contentsOf: other.imported)
        importedDocuments.append(contentsOf: other.importedDocuments)
        duplicates.append(contentsOf: other.duplicates)
        rejected.append(contentsOf: other.rejected)
        failures.append(contentsOf: other.failures)
        pending = other.pending
    }

    var hasActivity: Bool {
        imported.isEmpty == false
            || importedDocuments.isEmpty == false
            || duplicates.isEmpty == false
            || rejected.isEmpty == false
            || pending.isEmpty == false
            || failures.isEmpty == false
    }

    /// Counts only what this scan admitted. Earlier success must not mask new
    /// review work such as a duplicate or rejected file.
    private var importedCount: Int {
        imported.count + importedDocuments.count
    }

    var title: String {
        if hasActivity == false, priorImportCount > 0 {
            let subject = noun(priorImportCount, singular: "File", plural: "Files")
            return "\(priorImportCount) \(subject) Already Added"
        }

        // The title is what a user acts on. "No New Files Found" above a body
        // explaining that five files just landed reads as failure.
        if importedCount > 0, failures.isEmpty {
            var parts: [String] = []
            if imported.isEmpty == false {
                let subject = noun(
                    imported.count,
                    singular: "Audio File",
                    plural: "Audio Files"
                )
                parts.append("\(imported.count) \(subject)")
            }
            if importedDocuments.isEmpty == false {
                let subject = noun(
                    importedDocuments.count,
                    singular: "Document",
                    plural: "Documents"
                )
                parts.append("\(importedDocuments.count) \(subject)")
            }
            return "\(parts.joined(separator: ", ")) Added"
        }
        if failures.isEmpty == false {
            return "File Transfer Failed"
        }
        if duplicates.isEmpty == false || rejected.isEmpty == false {
            return "File Transfer Needs Review"
        }
        if pending.isEmpty == false {
            return "File Transfer in Progress"
        }
        return "No New Files Found"
    }

    var message: String {
        var lines: [String] = []

        if imported.isEmpty == false {
            let subject = noun(imported.count, singular: "file is", plural: "files are")
            lines.append("\(imported.count) \(subject) ready in your Library.")
        }
        if importedDocuments.isEmpty == false {
            let subject = noun(
                importedDocuments.count,
                singular: "document is",
                plural: "documents are"
            )
            lines.append("\(importedDocuments.count) \(subject) ready in your Reader.")
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
                    "Nothing new to import. \(priorImportCount) transferred \(subject) already in LumeSync."
                )
            } else {
                lines.append("Connect your iPhone, open Finder, select it, and drag audio or documents onto LumeSync in the Files tab. Then check again.")
            }
        }

        return lines.joined(separator: "\n\n")
    }

    private func noun(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? singular : plural
    }
}
