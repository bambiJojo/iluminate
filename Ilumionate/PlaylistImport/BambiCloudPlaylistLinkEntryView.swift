//
//  BambiCloudPlaylistLinkEntryView.swift
//  Ilumionate
//

import SwiftUI

struct BambiCloudPlaylistLinkEntryView: View {
    @Bindable var model: BambiCloudPlaylistImportViewModel

    var body: some View {
        Form {
            Section {
                TextField(
                    "Shared playlist link",
                    text: $model.linkText,
                    prompt: Text("https://bambicloud.com/playlist/…")
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
                Text("The link is used only to read the playlist name and track order. Audio is never downloaded.")
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
