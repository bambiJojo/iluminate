//
//  PlaylistLinkEntryView.swift
//  Ilumionate
//

import SwiftUI

struct PlaylistLinkEntryView: View {
    @Bindable var model: PlaylistImportViewModel

    var body: some View {
        Form {
            Section {
                TextField(
                    "Playlist address",
                    text: $model.linkText,
                    prompt: Text("https://…")
                        .foregroundStyle(.textLight)
                )
                .labelsHidden()
                .platformURLKeyboard()
                .platformNeverAutocapitalized()
                .platformAutocorrectionDisabled()
                .platformGoSubmitLabel()
                .onSubmit(loadPlaylist)
                .font(TranceTypography.body)
                .foregroundStyle(.textPrimary)
                .listRowBackground(Color.bgCard)

                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first else { return }
                    model.linkText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .tint(.roseGold)
                .listRowBackground(Color.bgCard)
            } header: {
                Text("Shared playlist link")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textSecondary)
            } footer: {
                Text("The link first reads only the playlist name and track order. Audio is downloaded only when you explicitly choose a published track you have permission and source authorization to save.")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textLight)
            }

            if let errorMessage = model.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(TranceTypography.body)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Import error: \(errorMessage)")
                        .listRowBackground(Color.bgCard)
                }
            }

            Section {
                Button(action: loadPlaylist) {
                    Label("Find Playlist", systemImage: "arrow.down.circle")
                        .font(TranceTypography.body)
                        .foregroundStyle(model.canLoad ? Color.roseGold : Color.textLight)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!model.canLoad)
                .listRowBackground(Color.bgCard)
            }
        }
        .platformInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .background(Color.bgPrimary)
        .disabled(model.isLoading)
        .overlay {
            if model.isLoading {
                ProgressView("Reading playlist…")
                    .font(TranceTypography.body)
                    .tint(.roseGold)
                    .foregroundStyle(.textPrimary)
                    .padding(TranceSpacing.content)
                    .background(.regularMaterial, in: .rect(cornerRadius: TranceRadius.glassCard))
            }
        }
    }

    private func loadPlaylist() {
        Task {
            await model.loadPlaylist()
        }
    }
}
