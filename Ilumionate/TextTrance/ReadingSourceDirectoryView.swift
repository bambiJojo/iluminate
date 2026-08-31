//
//  ReadingSourceDirectoryView.swift
//  Ilumionate
//
//  Manager for websites the user explicitly adds to Reader.

import SwiftUI

struct ReadingSourceDirectoryView: View {
    @State private var store: ReadingSourceStore
    @State private var searchText = ""
    @State private var showingAddWebsite = false
    @State private var sourcePendingDeletion: ReadingSource?

    let onOpenSource: (ReadingSource) -> Void

    init(
        store: ReadingSourceStore = .shared,
        onOpenSource: @escaping (ReadingSource) -> Void = { _ in }
    ) {
        _store = State(initialValue: store)
        self.onOpenSource = onOpenSource
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                    if store.customSources.isEmpty {
                        emptyState
                    } else if filteredSources.isEmpty {
                        GlassCard {
                            Text("No custom sources match your search.")
                                .font(TranceTypography.body)
                                .foregroundStyle(.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ForEach(filteredSources) { source in
                            ReadingSourceCard(
                                source: source,
                                open: { onOpenSource(source) },
                                delete: { sourcePendingDeletion = source }
                            )
                        }
                    }

                    Color.clear.frame(height: TranceSpacing.tabBarClearance)
                }
                .padding(TranceSpacing.screen)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Custom Sources")
        .platformSearchable(text: $searchText, prompt: "Search custom sources")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Website", systemImage: "plus") {
                    showingAddWebsite = true
                }
            }
        }
        .sheet(isPresented: $showingAddWebsite) {
            AddReadingSourceView(store: store)
        }
        .confirmationDialog(
            "Delete this custom source?",
            isPresented: deleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Source", role: .destructive) {
                guard let sourcePendingDeletion else { return }
                store.deleteCustomSource(id: sourcePendingDeletion.id)
                self.sourcePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                sourcePendingDeletion = nil
            }
        } message: {
            Text("This removes the saved website only. Stories already imported into Reader are unchanged.")
        }
    }

    private var filteredSources: [ReadingSource] {
        ReadingSourceSearch.filter(store.customSources, query: searchText)
    }

    private var emptyState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                Image(systemName: "globe")
                    .font(.title)
                    .foregroundStyle(.roseGold)

                Text("Add your own websites")
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(.textPrimary)

                Text("LumeSync does not recommend or provide websites. Add a site you choose, browse to a story, then explicitly import the current page.")
                    .font(TranceTypography.body)
                    .foregroundStyle(.textSecondary)

                Text("Only import content you created or have permission to save.")
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textLight)

                GlowButton(
                    title: "Add Website",
                    systemImage: "plus",
                    kind: .primary
                ) {
                    showingAddWebsite = true
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { sourcePendingDeletion != nil },
            set: { if $0 == false { sourcePendingDeletion = nil } }
        )
    }
}

private struct ReadingSourceCard: View {
    let source: ReadingSource
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(source.title)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(.textPrimary)

                    Text(source.url.host(percentEncoded: false) ?? source.url.absoluteString)
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }

                if source.summary.isEmpty == false {
                    Text(source.summary)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textSecondary)
                }

                HStack(spacing: TranceSpacing.list) {
                    GlowButton(
                        title: "Open Website",
                        systemImage: "globe",
                        kind: .primary
                    ) {
                        TranceHaptics.shared.light()
                        open()
                    }

                    Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Delete \(source.title)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        ReadingSourceDirectoryView()
    }
}
