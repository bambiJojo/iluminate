//
//  AudioLibraryCache.swift
//  Ilumionate
//
//  The last-loaded audio library, kept alive across view lifetimes.
//
//  `LibraryView` is torn down whenever the Library tab is left and rebuilt when
//  it is re-entered, so its `audioFiles` state starts empty every time. That was
//  invisible while the load blocked the main thread — the view could not paint
//  until the files existed. Now that the load runs on the global executor, the
//  empty state paints first and the shelves pop in a moment later.
//
//  Seeding from here means a return visit renders the previous contents
//  immediately and the refresh swaps in quietly behind it.
//

import Foundation
import Observation

@MainActor
@Observable
final class AudioLibraryCache {
    static let shared = AudioLibraryCache()

    private(set) var files: [AudioFile] = []
    /// False until the first load completes, so a genuinely empty library can be
    /// told apart from one that simply has not loaded yet.
    private(set) var hasLoaded = false

    private init() {}

    func store(_ files: [AudioFile]) {
        self.files = files
        hasLoaded = true
    }

    /// Loads off the main actor and publishes the result.
    func refresh() async {
        store(await AudioLibraryStore.loadRepairingStoredFiles())
    }
}
