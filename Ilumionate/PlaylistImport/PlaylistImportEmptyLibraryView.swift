//
//  PlaylistImportEmptyLibraryView.swift
//  Ilumionate
//

import SwiftUI

/// Shown when a shared playlist could be read but there is no local audio for
/// its tracks to match against, so importing could never produce a playlist.
struct PlaylistImportEmptyLibraryView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Local Audio", systemImage: "waveform.slash")
                .foregroundStyle(.textPrimary)
        } description: {
            Text("Importing a shared playlist only reorders audio you already have. Add audio to your library first, then import the link.")
                .font(TranceTypography.body)
                .foregroundStyle(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }
}
