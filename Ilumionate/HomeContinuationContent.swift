//
//  HomeContinuationContent.swift
//  Ilumionate
//
//  Pure derivation of the "Continue" section's contents from stored progress.
//
//  Both halves of this are decisions rather than layout, and both were
//  previously buried inside LibraryView: a saved playback position must not be
//  offered once its audio file or session is gone, and a saved reading position
//  can be backed by an imported script, a bundled script, or an imported
//  document. Continue now lives on home, so keeping the rules here — the way
//  LibraryShelfContent already keeps the shelf derivations — means the next
//  screen that wants them reuses them instead of copying them.
//

import Foundation

enum HomeContinuationContent {

    /// Saved playback positions whose content still exists.
    ///
    /// A snapshot outlives the thing it points at — files get deleted and
    /// bundled sessions come and go between releases — so the store is filtered
    /// against what is actually loadable rather than trusted outright.
    static func listening(
        snapshots: [PlaybackProgressSnapshot],
        audioFiles: [AudioFile],
        sessions: [LightSession]
    ) -> [PlaybackProgressSnapshot] {
        snapshots.filter { snapshot in
            switch snapshot.kind {
            case .audio:   audioFiles.contains { $0.id.uuidString == snapshot.contentID }
            case .session: sessions.contains { $0.id.uuidString == snapshot.contentID }
            }
        }
    }

    /// Resolves a saved reading position to something displayable.
    ///
    /// An imported script shadows a bundled one with the same id — importing is
    /// how a reader replaces bundled copy — and imported PDF/ePub documents are
    /// the last place to look. A position whose source is gone resolves to
    /// `nil` so Continue simply omits the reading row.
    static func reading(
        state: ReaderResumeState?,
        importedScripts: [TranceScript],
        bundledScripts: [TranceScript],
        documents: [ReadingDocument]
    ) -> LibraryReadingContinuation? {
        guard let state else { return nil }

        let scripts = importedScripts + bundledScripts.filter { candidate in
            importedScripts.contains { $0.id == candidate.id } == false
        }

        if let script = scripts.first(where: { $0.id == state.scriptId }) {
            return LibraryReadingContinuation(title: script.title, wordIndex: state.wordIndex)
        }

        if let document = documents.first(where: { $0.scriptID == state.scriptId }) {
            return LibraryReadingContinuation(title: document.title, wordIndex: state.wordIndex)
        }

        return nil
    }
}
