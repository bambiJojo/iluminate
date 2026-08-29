//
//  LibraryAddMenu.swift
//  Ilumionate
//
//  Everything Library's "+" can add, in one menu.
//
//  Sessions and playlists are both added from this point, and the two used to
//  be several taps apart behind different screens — audio behind the Audio
//  manager and an action sheet, playlists behind the Playlists sheet. Naming
//  all six destinations here makes the cost of each one tap.
//

import SwiftUI

struct LibraryAddMenu: View {
    let acquisition: AudioAcquisition

    let onNewPlaylist: () -> Void
    let onImportPlaylistLink: () -> Void
    let onBrowseForPlaylist: () -> Void
    let isCheckingIncomingFiles: Bool
    let onCheckIncomingFiles: () -> Void
    /// Select, rename, find duplicates — management, not adding. It lives at the
    /// bottom of this menu because the "+" is its only entry point in the app.
    let onManageAudio: () -> Void

    var body: some View {
        Section("Sessions") {
            Button("Import from Files", systemImage: "folder") {
                acquisition.importFromFiles()
            }
            Button("Import from URL", systemImage: "link") {
                acquisition.importFromURL()
            }
            Button("Browse the Web", systemImage: "globe") {
                acquisition.browseTheWeb()
            }
        }

        Section("Playlists") {
            Button("New Playlist", systemImage: "plus.rectangle.on.folder") {
                TranceHaptics.shared.light()
                onNewPlaylist()
            }
            Button("Import from Link", systemImage: "link.badge.plus") {
                TranceHaptics.shared.light()
                onImportPlaylistLink()
            }
            Button("Browse for a Playlist", systemImage: "safari") {
                TranceHaptics.shared.light()
                onBrowseForPlaylist()
            }
        }

        #if os(iOS) && !targetEnvironment(macCatalyst)
        Section("Cable Transfer") {
            Button(
                isCheckingIncomingFiles ? "Checking Incoming Files…" : "Check Incoming Files",
                systemImage: isCheckingIncomingFiles ? "hourglass" : "arrow.down.doc"
            ) {
                TranceHaptics.shared.light()
                onCheckIncomingFiles()
            }
            .disabled(isCheckingIncomingFiles)
        }
        #endif

        Section {
            Button("Manage Audio Files", systemImage: "slider.horizontal.3") {
                TranceHaptics.shared.light()
                onManageAudio()
            }
        }
    }
}
