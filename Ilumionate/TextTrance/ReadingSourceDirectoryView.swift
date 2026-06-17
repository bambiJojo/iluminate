//  ReadingSourceDirectoryView.swift
//  Ilumionate
//
//  Curated link directory for reading sources. It opens websites; text import
//  remains a future explicit user action.

import SwiftUI

struct ReadingSourceDirectoryView: View {
    @State private var store: ReadingSourceStore
    @State private var selectedCategory: ReadingSourceCategory?
    @State private var searchText = ""
    @State private var showingAddSource = false

    @Environment(\.openURL) private var openURL

    init(store: ReadingSourceStore = .shared) {
        _store = State(initialValue: store)
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: TranceSpacing.card) {
                    categoryFilter

                    ForEach(groupedSources, id: \.category) { group in
                        SourceSection(
                            category: group.category,
                            sources: group.sources,
                            onOpen: openSource,
                            onDelete: deleteSource
                        )
                    }

                    Color.clear.frame(height: TranceSpacing.tabBarClearance)
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.content)
            }
        }
        .navigationTitle("Reading Sources")
        .searchable(text: $searchText, prompt: "Search sources")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add custom source", systemImage: "plus") {
                    TranceHaptics.shared.light()
                    showingAddSource = true
                }
                .tint(.auroraTeal)
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddReadingSourceSheet(store: store)
        }
    }

    private var filteredSources: [ReadingSource] {
        let categoryFiltered = store.sources(in: selectedCategory)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categoryFiltered }
        return categoryFiltered.filter { source in
            source.title.localizedCaseInsensitiveContains(query)
                || source.summary.localizedCaseInsensitiveContains(query)
                || source.url.host(percentEncoded: false)?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var groupedSources: [(category: ReadingSourceCategory, sources: [ReadingSource])] {
        ReadingSourceCategory.allCases.compactMap { category in
            let sources = filteredSources.filter { $0.category == category }
            return sources.isEmpty ? nil : (category, sources)
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TranceSpacing.inner) {
                CategoryChip(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    action: { selectedCategory = nil }
                )

                ForEach(ReadingSourceCategory.allCases) { category in
                    CategoryChip(
                        title: category.displayName,
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
            .padding(.bottom, TranceSpacing.micro)
        }
    }

    private func openSource(_ source: ReadingSource) {
        TranceHaptics.shared.light()
        openURL(source.url)
    }

    private func deleteSource(_ source: ReadingSource) {
        store.deleteCustomSource(id: source.id)
    }
}

private struct SourceSection: View {
    let category: ReadingSourceCategory
    let sources: [ReadingSource]
    let onOpen: (ReadingSource) -> Void
    let onDelete: (ReadingSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.inner) {
            Text(category.displayName)
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(.textPrimary)

            VStack(spacing: TranceSpacing.inner) {
                ForEach(sources) { source in
                    ReadingSourceCard(source: source, onOpen: onOpen)
                        .contextMenu {
                            Button("Open", systemImage: "safari") {
                                onOpen(source)
                            }
                            if !source.isCurated {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    onDelete(source)
                                }
                            }
                        }
                }
            }
        }
    }
}

private struct ReadingSourceCard: View {
    let source: ReadingSource
    let onOpen: (ReadingSource) -> Void

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(alignment: .top, spacing: TranceSpacing.list) {
                    SourceIcon(category: source.category)

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(source.title)
                            .font(TranceTypography.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.textPrimary)

                        Text(source.url.host(percentEncoded: false) ?? source.url.absoluteString)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textLight)
                            .lineLimit(1)
                    }

                    Spacer()

                    ImportPolicyBadge(policy: source.importPolicy)
                }

                if !source.summary.isEmpty {
                    Text(source.summary)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(source.licenseNote)
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textSecondary)
                    Text(source.contentNote)
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textLight)
                }

                GlowButton(title: "Open", systemImage: "safari.fill", kind: .primary) {
                    onOpen(source)
                }
                .accessibilityLabel("Open \(source.title)")
            }
        }
    }
}

private struct SourceIcon: View {
    let category: ReadingSourceCategory

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color.opacity(0.18))
            .frame(width: 38, height: 38)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
    }

    private var symbol: String {
        switch category {
        case .publicDomain:    return "book.closed.fill"
        case .openLibrary:     return "building.columns.fill"
        case .scriptDirectory: return "doc.text.fill"
        case .userAdded:       return "link"
        }
    }

    private var color: Color {
        switch category {
        case .publicDomain:    return .bwGamma
        case .openLibrary:     return .bwTheta
        case .scriptDirectory: return .roseGold
        case .userAdded:       return .warmAccent
        }
    }
}

private struct ImportPolicyBadge: View {
    let policy: ReadingSourceImportPolicy

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch policy {
        case .linkOnly:            return "Link"
        case .userInitiatedImport: return "Import Later"
        case .catalogPlanned:      return "Catalog Later"
        }
    }

    private var color: Color {
        switch policy {
        case .linkOnly:            return .textSecondary
        case .userInitiatedImport: return .bwTheta
        case .catalogPlanned:      return .roseGold
        }
    }
}

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(TranceTypography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.auroraTeal : Color.glassBorder.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Color.glassBorder.opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct AddReadingSourceSheet: View {
    let store: ReadingSourceStore

    @State private var title = ""
    @State private var urlString = ""
    @State private var summary = ""
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    TextField("Name", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Website", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Note", text: $summary, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            try store.addCustomSource(title: title, urlString: urlString, summary: summary)
            dismiss()
        } catch let error as ReadingSourceStoreError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ReadingSourceDirectoryView(store: ReadingSourceStore(defaults: .standard, storageKey: "previewReadingSources"))
    }
}
