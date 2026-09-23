//
//  PlaylistBrowserSettingsCard.swift
//  Ilumionate
//
//  Settings for "Browse for Playlists": which site the browser opens on.
//

import SwiftUI

struct PlaylistBrowserSettingsCard: View {
    @AppStorage(PlaylistBrowserHomePage.storageKey) private var homePage = ""

    var body: some View {
        GlassCard(label: "Playlist Browser") {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    Image(systemName: "safari")
                        .font(.body)
                        .foregroundStyle(Color.roseGold)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text("Start Page")
                            .font(TranceTypography.body)
                            .foregroundStyle(Color.textPrimary)
                        Text("Browse for Playlists opens this site. Leave it empty to start at Google.")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: TranceSpacing.list) {
                    TextField(
                        "Start page address",
                        text: $homePage,
                        prompt: Text("www.google.com")
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .platformURLKeyboard()
                    .platformNeverAutocapitalized()
                    .platformAutocorrectionDisabled()

                    if !homePage.isEmpty {
                        Button("Use Default", systemImage: "arrow.uturn.backward") {
                            TranceHaptics.shared.light()
                            homePage = ""
                        }
                        .labelStyle(.iconOnly)
                        .tint(.roseGold)
                    }
                }

                if !PlaylistBrowserHomePage.isUsable(homePage) {
                    Label(
                        "That isn't a web address LumeSync can open, so the browser will start at Google.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.warmAccent)
                }
            }
        }
    }
}
