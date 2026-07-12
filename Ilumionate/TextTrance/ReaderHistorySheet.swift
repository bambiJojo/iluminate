//  ReaderHistorySheet.swift
//  Ilumionate
//
//  Reader-specific continuation list built from resumable progress snapshots.

import SwiftUI

struct ReaderHistoryItem: Identifiable {
    let script: TranceScript
    let state: ReaderResumeState

    var id: String { script.id }
}

struct ReaderHistorySheet: View {
    @Environment(\.dismiss) private var dismiss

    let items: [ReaderHistoryItem]
    let onOpen: (TranceScript) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing In Progress", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Saved progress appears here after you begin reading a script or document.")
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(TranceSpacing.screen)
                } else {
                    ScrollView {
                        LazyVStack(spacing: TranceSpacing.list) {
                            ForEach(items) { item in
                                Button {
                                    onOpen(item.script)
                                    dismiss()
                                } label: {
                                    ReaderHistoryRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(TranceSpacing.screen)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Continue Reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ReaderHistoryRow: View {
    let item: ReaderHistoryItem

    var body: some View {
        LiminalCard {
            HStack(spacing: TranceSpacing.list) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.script.theme.accent.opacity(0.18))
                    .frame(width: 42, height: 42)
                    .overlay {
                        Image(systemName: item.script.source.kind == .importedDocument
                              ? "doc.text.fill"
                              : item.script.theme.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(item.script.theme.accent)
                    }

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(item.script.title)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: TranceSpacing.inner) {
                        Label("Word \(item.state.wordIndex + 1)", systemImage: "textformat")
                        Text(item.state.savedAt.formatted(.relative(presentation: .named)))
                    }
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: TranceSpacing.inner)

                Image(systemName: "chevron.right")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
