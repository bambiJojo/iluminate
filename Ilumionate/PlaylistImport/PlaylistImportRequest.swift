//
//  PlaylistImportRequest.swift
//  Ilumionate
//

import Foundation

/// Carries the audio library snapshot into the playlist importer sheet.
///
/// The importer seeds `@State` from its initializer, so the files must travel
/// with the presentation item. Presenting with `isPresented` instead reads the
/// body snapshot from before the library finished loading and hands the
/// importer an empty library.
struct PlaylistImportRequest: Identifiable {
    let id = UUID()
    let audioFiles: [AudioFile]
    /// Set when the link came from the in-app browser, so the importer can skip
    /// link entry and go straight to matching.
    var initialLink: String?
}
