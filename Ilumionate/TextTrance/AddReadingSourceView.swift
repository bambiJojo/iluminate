//
//  AddReadingSourceView.swift
//  Ilumionate
//

import SwiftUI

struct AddReadingSourceView: View {
    let store: ReadingSourceStore

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var website = ""
    @State private var note = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Website") {
                    TextField("Name", text: $title)
                    TextField("Website address", text: $website)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                    TextField("Private note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel("Could not add website: \(validationMessage)")
                    }
                }

                Section {
                    Text("Your source list stays on this device. LumeSync does not recommend websites or send saved addresses to analytics.")
                    Text("Only import content you created or have permission to save.")
                }
                .font(TranceTypography.caption)
                .foregroundStyle(.textSecondary)
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground())
            .navigationTitle("Add Website")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addWebsite)
                }
            }
        }
    }

    private func addWebsite() {
        validationMessage = nil
        do {
            try store.addCustomSource(
                title: title,
                urlString: website,
                summary: note
            )
            dismiss()
        } catch let error as LocalizedError {
            validationMessage = error.errorDescription ?? "Check the website details and try again."
        } catch {
            validationMessage = "Check the website details and try again."
        }
    }
}
