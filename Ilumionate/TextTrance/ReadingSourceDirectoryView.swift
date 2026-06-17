//  ReadingSourceDirectoryView.swift
//  Ilumionate
//
//  Curated directory for reading sources and user-initiated script imports.

import SwiftUI

struct ReadingSourceDirectoryView: View {
    private let onImported: ((TranceScript) -> Void)?

    @State private var store: ReadingSourceStore
    @State private var directoryMode: ReadingDirectoryMode = .scripts
    @State private var selectedCategory: ReadingSourceCategory?
    @State private var selectedScriptKind: ReadingScriptKind?
    @State private var selectedScriptTheme: ScriptTheme?
    @State private var searchText = ""
    @State private var showingAddSource = false
    @State private var browserDestination: BrowserDestination?
    @State private var pendingAdultURL: URL?
    @State private var importingScriptID: String?
    @State private var importErrorText: String?

    @AppStorage("readingSourceAdultConfirmed") private var adultConfirmed = false

    init(store: ReadingSourceStore,
         onImported: ((TranceScript) -> Void)? = nil) {
        self.onImported = onImported
        _store = State(initialValue: store)
    }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: TranceSpacing.card) {
                    modePicker
                    directoryContent

                    Color.clear.frame(height: TranceSpacing.tabBarClearance)
                }
                .padding(.horizontal, TranceSpacing.screen)
                .padding(.top, TranceSpacing.content)
            }
        }
        .navigationTitle("Reading Sources")
        .searchable(text: $searchText, prompt: searchPrompt)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    TranceHaptics.shared.light()
                    showingAddSource = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 28))
                        .foregroundStyle(.roseGold)
                }
                .accessibilityLabel("Add custom source")
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddReadingSourceSheet(store: store)
        }
        .fullScreenCover(item: $browserDestination) { destination in
            SafariBrowserView(
                url: destination.url,
                suggestedTitle: destination.suggestedTitle,
                theme: destination.theme,
                onImported: onImported
            )
        }
        .alert("Adult content", isPresented: adultGatePresented, presenting: pendingAdultURL) { url in
            Button("Continue", role: .destructive) {
                adultConfirmed = true
                pendingAdultURL = nil
                browserDestination = BrowserDestination(url: url)
            }
            Button("Cancel", role: .cancel) {
                pendingAdultURL = nil
            }
        } message: { _ in
            Text("This source links to adult (18+) material. Continue?")
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

    private var filteredScripts: [ReadingScriptCatalogEntry] {
        ReadingScriptCatalog.entries(
            kind: selectedScriptKind,
            theme: selectedScriptTheme,
            query: searchText
        )
    }

    private var groupedSources: [SourceGroup] {
        ReadingSourceCategory.allCases.compactMap { category in
            let sources = filteredSources.filter { $0.category == category }
            return sources.isEmpty ? nil : SourceGroup(category: category, sources: sources)
        }
    }

    private var searchPrompt: String {
        switch directoryMode {
        case .scripts: return "Search scripts"
        case .sites:   return "Search sources"
        }
    }

    private var modePicker: some View {
        Picker("Directory mode", selection: $directoryMode) {
            ForEach(ReadingDirectoryMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var directoryContent: some View {
        switch directoryMode {
        case .scripts:
            scriptsContent
        case .sites:
            sitesContent
        }
    }

    private var scriptsContent: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.card) {
            scriptFilters
            if let importErrorText {
                EmptyDirectoryMessage(
                    title: "Import failed",
                    message: importErrorText
                )
            }
            if filteredScripts.isEmpty {
                EmptyDirectoryMessage(
                    title: "No scripts found",
                    message: "Try a different search or filter."
                )
            } else {
                ScriptCatalogSection(
                    entries: filteredScripts,
                    importingScriptID: importingScriptID,
                    onImport: importScript,
                    onOpen: openScript
                )
            }
        }
    }

    private var sitesContent: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.card) {
            categoryFilter
            if groupedSources.isEmpty {
                EmptyDirectoryMessage(
                    title: "No sources found",
                    message: "Try a different search or category."
                )
            } else {
                ForEach(groupedSources) { group in
                    SourceSection(
                        category: group.category,
                        sources: group.sources,
                        onOpen: openSource,
                        onDelete: deleteSource
                    )
                }
            }
        }
    }

    private var scriptFilters: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.inner) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.inner) {
                    CategoryChip(
                        title: "All Types",
                        isSelected: selectedScriptKind == nil,
                        action: { selectedScriptKind = nil }
                    )

                    ForEach(ReadingScriptKind.allCases) { kind in
                        CategoryChip(
                            title: kind.displayName,
                            isSelected: selectedScriptKind == kind,
                            action: { selectedScriptKind = kind }
                        )
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TranceSpacing.inner) {
                    CategoryChip(
                        title: "All Themes",
                        isSelected: selectedScriptTheme == nil,
                        action: { selectedScriptTheme = nil }
                    )

                    ForEach(ScriptTheme.allCases) { theme in
                        CategoryChip(
                            title: theme.displayName,
                            isSelected: selectedScriptTheme == theme,
                            action: { selectedScriptTheme = theme }
                        )
                    }
                }
            }
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
        switch openAction(for: source, adultConfirmed: adultConfirmed) {
        case .browse(let url):
            browserDestination = BrowserDestination(url: url, suggestedTitle: source.title)
        case .confirmAdult(let url):
            pendingAdultURL = url
        }
    }

    private func openScript(_ entry: ReadingScriptCatalogEntry) {
        TranceHaptics.shared.light()
        switch openAction(for: entry, adultConfirmed: adultConfirmed) {
        case .browse(let url):
            browserDestination = BrowserDestination(url: url, suggestedTitle: entry.title, theme: entry.theme)
        case .confirmAdult(let url):
            pendingAdultURL = url
        }
    }

    private func importScript(_ entry: ReadingScriptCatalogEntry) {
        guard importingScriptID == nil else { return }

        if entry.contentRating == .adultOnly && adultConfirmed == false {
            pendingAdultURL = entry.url
            return
        }

        guard entry.canImport else {
            importErrorText = "This source can only be opened as a website."
            return
        }

        importingScriptID = entry.id
        importErrorText = nil
        Task {
            do {
                let script = try await WebReadableTextImporter().importScript(
                    from: entry.url,
                    title: entry.title,
                    theme: entry.theme
                )
                await MainActor.run {
                    importingScriptID = nil
                    onImported?(script)
                }
            } catch {
                await MainActor.run {
                    importingScriptID = nil
                    importErrorText = error.localizedDescription
                }
            }
        }
    }

    private var adultGatePresented: Binding<Bool> {
        Binding(
            get: { pendingAdultURL != nil },
            set: { if !$0 { pendingAdultURL = nil } }
        )
    }

    private func deleteSource(_ source: ReadingSource) {
        store.deleteCustomSource(id: source.id)
    }
}

private enum ReadingDirectoryMode: String, CaseIterable, Identifiable {
    case scripts
    case sites

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scripts: return "Scripts"
        case .sites:   return "Sites"
        }
    }
}

private struct BrowserDestination: Identifiable {
    let id = UUID()
    let url: URL
    let suggestedTitle: String?
    let theme: ScriptTheme

    init(url: URL, suggestedTitle: String? = nil, theme: ScriptTheme = .focus) {
        self.url = url
        self.suggestedTitle = suggestedTitle
        self.theme = theme
    }
}

private struct SourceGroup: Identifiable {
    let category: ReadingSourceCategory
    let sources: [ReadingSource]

    var id: ReadingSourceCategory { category }
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

private struct ScriptCatalogSection: View {
    let entries: [ReadingScriptCatalogEntry]
    let importingScriptID: String?
    let onImport: (ReadingScriptCatalogEntry) -> Void
    let onOpen: (ReadingScriptCatalogEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.inner) {
            Text("Scripts")
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(.textPrimary)

            VStack(spacing: TranceSpacing.inner) {
                ForEach(entries) { entry in
                    ScriptCatalogCard(
                        entry: entry,
                        isImporting: importingScriptID == entry.id,
                        onImport: onImport,
                        onOpen: onOpen
                    )
                }
            }
        }
    }
}

private struct ScriptCatalogCard: View {
    let entry: ReadingScriptCatalogEntry
    let isImporting: Bool
    let onImport: (ReadingScriptCatalogEntry) -> Void
    let onOpen: (ReadingScriptCatalogEntry) -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(alignment: .top, spacing: TranceSpacing.list) {
                    ScriptKindIcon(kind: entry.kind)

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(entry.title)
                            .font(TranceTypography.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.textPrimary)

                        Text(entry.sourceTitle)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.textLight)
                            .lineLimit(1)
                    }

                    Spacer()

                    if entry.contentRating == .adultOnly {
                        AdultBadge()
                    }
                    ImportPolicyBadge(policy: entry.importPolicy)
                }

                Text(entry.summary)
                    .font(TranceTypography.body)
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    TagPill(text: entry.kind.displayName)
                    TagPill(text: entry.theme.displayName)
                    TagPill(text: entry.length.displayName)
                }

                Text(entry.licenseNote)
                    .font(TranceTypography.caption)
                    .foregroundStyle(.textLight)

                HStack(spacing: TranceSpacing.inner) {
                    Button {
                        onImport(entry)
                    } label: {
                        HStack(spacing: TranceSpacing.icon) {
                            if isImporting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                            }
                            Text(isImporting ? "Importing" : "Import")
                        }
                        .font(TranceTypography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            LinearGradient(
                                colors: [.roseGold, .roseDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                    }
                    .disabled(isImporting || entry.canImport == false)
                    .accessibilityLabel("Import \(entry.title)")

                    Button {
                        onOpen(entry)
                    } label: {
                        Image(systemName: "safari")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Color.glassBorder.opacity(0.14), in: RoundedRectangle(cornerRadius: TranceRadius.button))
                            .overlay {
                                RoundedRectangle(cornerRadius: TranceRadius.button)
                                    .strokeBorder(Color.glassBorder.opacity(0.35), lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("Open \(entry.title) website")
                }
            }
        }
    }
}

private struct ReadingSourceCard: View {
    let source: ReadingSource
    let onOpen: (ReadingSource) -> Void

    var body: some View {
        GlassCard {
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

                    if source.contentRating == .adultOnly {
                        AdultBadge()
                    }
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

                Button {
                    onOpen(source)
                } label: {
                    HStack(spacing: TranceSpacing.icon) {
                        Image(systemName: "safari.fill")
                        Text("Open")
                    }
                    .font(TranceTypography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.roseGold, .roseDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: TranceRadius.button))
                }
                .accessibilityLabel("Open \(source.title)")
            }
        }
    }
}

private struct ScriptKindIcon: View {
    let kind: ReadingScriptKind

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
        switch kind {
        case .induction:    return "sparkles"
        case .deepening:    return "arrow.down.circle.fill"
        case .subject:      return "doc.text.fill"
        case .selfHypnosis: return "moon.zzz.fill"
        case .story:        return "book.closed.fill"
        case .book:         return "book.closed.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .induction:    return .bwTheta
        case .deepening:    return .bwGamma
        case .subject:      return .roseGold
        case .selfHypnosis: return .warmAccent
        case .story:        return .roseDeep
        case .book:         return .textSecondary
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

private struct TagPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.glassBorder.opacity(0.12), in: Capsule())
    }
}

private struct EmptyDirectoryMessage: View {
    let title: String
    let message: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                Text(title)
                    .font(TranceTypography.sectionTitle)
                    .foregroundStyle(.textPrimary)
                Text(message)
                    .font(TranceTypography.body)
                    .foregroundStyle(.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

private struct AdultBadge: View {
    var body: some View {
        Text("18+")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.warmAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.warmAccent.opacity(0.16), in: Capsule())
            .accessibilityLabel("Adult content")
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
                .background(isSelected ? Color.roseGold : Color.glassBorder.opacity(0.12), in: Capsule())
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
