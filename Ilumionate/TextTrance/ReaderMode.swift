//  ReaderMode.swift
//  Ilumionate
//
//  Which of the reader's two jobs a script is being opened for. Plain reading is
//  an RSVP speed reader; trance is a scripted hypnosis experience. The mode
//  decides which settings groups exist (see ReaderSettingsCatalog) — it never
//  changes how the reading surface renders.

import Foundation

enum ReaderMode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Word-by-word speed reading. Words per minute is the point.
    case reading
    /// Scripted hypnosis. Pacing, arc, and the optional layers are the point.
    case trance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reading: "Reading"
        case .trance:  "Trance"
        }
    }

    var detail: String {
        switch self {
        case .reading: "Word-by-word speed reading"
        case .trance:  "Guided hypnotic session"
        }
    }

    /// The mode a script defaults to, from how its content arrived.
    ///
    /// Imported articles and documents are things the user wants to *read*;
    /// bundled and generated scripts are written trance. Every import currently
    /// borrows the trance script shape (`theme: .focus`, `phase: .induction`),
    /// so the source kind — not the script's own metadata — is the honest signal.
    static func derived(from source: ScriptSource) -> ReaderMode {
        switch source.kind {
        case .importedWeb, .importedDocument: .reading
        case .bundled, .generated:            .trance
        }
    }
}
