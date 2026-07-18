//  ReaderSectionNavigatorSheet.swift
//  Ilumionate
//
//  Searchable table of contents for an active Text Trance reader session.

import SwiftUI

struct ReaderSectionNavigatorSheet: View {
    @Bindable var session: TextTranceSession
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var visibleSections: [ReaderSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return session.sections }
        return session.sections.filter { section in
            section.title.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleSections.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "list.bullet.rectangle",
                        description: Text(emptyDescription)
                    )
                } else {
                    List {
                        ForEach(visibleSections) { section in
                            Button {
                                session.seek(toWordIndex: section.wordIndex, savingProgress: true)
                                dismiss()
                            } label: {
                                ReaderSectionRow(
                                    section: section,
                                    isCurrent: section.id == session.currentSection?.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Sections")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Find section")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var emptyTitle: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No Sections"
            : "No Matches"
    }

    private var emptyDescription: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "This reader item does not expose chapter or section breaks."
            : "Try a different chapter or section name."
    }
}

private struct ReaderSectionRow: View {
    let section: ReaderSection
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: TranceSpacing.list) {
            Image(systemName: isCurrent ? "location.fill" : "text.alignleft")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isCurrent ? Color.roseGold : Color.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(TranceTypography.body)
                    .foregroundStyle(isCurrent ? Color.roseGold : Color.textPrimary)
                    .lineLimit(2)

                Text("Word \(section.wordIndex + 1)")
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: TranceSpacing.small)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary.opacity(0.55))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), word \(section.wordIndex + 1)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
