//  ReadingSourceDirectoryView.swift
//  Ilumionate
//
//  Curated directory for reading sources and user-initiated script imports.

import SwiftUI

struct ReadingSourceDirectoryView: View {
    private let onImported: ((TranceScript) -> Void)?

    @State private var store: ReadingSourceStore
    @State private var directoryMode: ReadingDirectoryMode = .scripts
    @State private var searchText = ""
    @State private var showingAddSource = false
    @State private var browserDestination: BrowserDestination?
    @State private var importingScriptID: String?
    @State private var importErrorText: String?
    @State private var importedScriptTitle: String?

    // When off (default) all adult (18+) sources and scripts are hidden. The
    // Settings toggle is the one-time 18+ acknowledgment, so visible adult
    // sources open directly without a per-tap prompt.
    @AppStorage("nsfwSourcesEnabled") private var nsfwEnabled = false

    init(store: ReadingSourceStore,
         onImported: ((TranceScript) -> Void)? = nil) {
        self.onImported = onImported
        _store = State(initialValue: store)
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: TranceSpacing.card) {
                modePicker
                    .padding(.horizontal, TranceSpacing.screen)
                    .padding(.top, TranceSpacing.inner)

                // The two sections are full-width pages: tapping the picker
                // slides between them, and swiping horizontally does the same.
                TabView(selection: animatedModeSelection) {
                    scriptsContent.tag(ReadingDirectoryMode.scripts)
                    sitesContent.tag(ReadingDirectoryMode.sites)
                }
                .platformPagedTabViewStyle()
            }
        }
        .navigationTitle("Reading Sources")
        // Keep search attached to the navigation bar; the default bottom
        // placement puts the field underneath the app's floating tab bar.
        .platformSearchable(text: $searchText, prompt: searchPrompt)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add custom source", systemImage: "plus") {
                    TranceHaptics.shared.light()
                    showingAddSource = true
                }
                .tint(.roseGold)
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddReadingSourceSheet(store: store)
        }
        .platformFullScreenCover(item: $browserDestination) { destination in
            SafariBrowserView(
                url: destination.url,
                suggestedTitle: destination.suggestedTitle,
                theme: destination.theme,
                allowsImport: destination.allowsImport,
                onImported: handleImportedScript
            )
        }
    }

    private func isAllowed(_ rating: ReadingSourceContentRating) -> Bool {
        nsfwEnabled || rating != .adultOnly
    }

    /// Animate the page slide when the segmented picker changes the mode.
    private var animatedModeSelection: Binding<ReadingDirectoryMode> {
        Binding(
            get: { directoryMode },
            set: { newMode in
                withAnimation(.easeInOut(duration: 0.25)) { directoryMode = newMode }
            }
        )
    }

    private var filteredSources: [ReadingSource] {
        let allowed = store.sources(in: nil)
            .filter { isAllowed($0.contentRating) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allowed }
        return allowed.filter { source in
            source.title.localizedCaseInsensitiveContains(query)
                || source.summary.localizedCaseInsensitiveContains(query)
                || source.url.host(percentEncoded: false)?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private var filteredScripts: [ReadingScriptCatalogEntry] {
        ReadingScriptCatalog.entries(
            kind: nil,
            theme: nil,
            query: searchText
        )
        .filter { isAllowed($0.contentRating) }
    }

    /// One shelf per script kind that has entries, in canonical kind order.
    private var scriptShelves: [(kind: ReadingScriptKind, entries: [ReadingScriptCatalogEntry])] {
        ReadingScriptKind.allCases.compactMap { kind in
            let entries = filteredScripts.filter { $0.kind == kind }
            return entries.isEmpty ? nil : (kind, entries)
        }
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

    /// Scripts page: vertically scrolling shelves, one per script kind.
    private var scriptsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                if let importedScriptTitle {
                    ImportResultMessage(
                        title: "Script imported",
                        message: "\(importedScriptTitle) is now available in Text Trance."
                    )
                    .padding(.horizontal, TranceSpacing.screen)
                }
                if let importErrorText {
                    EmptyDirectoryMessage(
                        title: "Import failed",
                        message: importErrorText
                    )
                    .padding(.horizontal, TranceSpacing.screen)
                }
                if scriptShelves.isEmpty {
                    EmptyDirectoryMessage(
                        title: "No scripts found",
                        message: "Try a different search."
                    )
                    .padding(.horizontal, TranceSpacing.screen)
                } else {
                    ForEach(scriptShelves, id: \.kind) { shelf in
                        Text(shelf.kind.displayName)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(.textPrimary)
                            .padding(.horizontal, TranceSpacing.screen)

                        CarouselRow(items: shelf.entries) { entry in
                            ScriptCatalogCard(
                                entry: entry,
                                isImporting: importingScriptID == entry.id,
                                onImport: importScript,
                                onOpen: openScript
                            )
                        }
                    }

                    // One shared notice instead of the same caption on every card.
                    Text("Review each script page and site terms before use.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textLight)
                        .padding(.horizontal, TranceSpacing.screen)
                }

                Color.clear.frame(height: TranceSpacing.tabBarClearance)
            }
        }
        .scrollIndicators(.hidden)
    }

    /// Sites page: vertically scrolling shelves, one per source category.
    private var sitesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                if groupedSources.isEmpty {
                    EmptyDirectoryMessage(
                        title: "No sources found",
                        message: "Try a different search."
                    )
                    .padding(.horizontal, TranceSpacing.screen)
                } else {
                    ForEach(groupedSources) { group in
                        Text(group.category.displayName)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(.textPrimary)
                            .padding(.horizontal, TranceSpacing.screen)

                        CarouselRow(items: group.sources) { source in
                            ReadingSourceCard(source: source, onOpen: openSource)
                                .contextMenu {
                                    Button("Open", systemImage: "safari") {
                                        openSource(source)
                                    }
                                    if !source.isCurated {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            deleteSource(source)
                                        }
                                    }
                                }
                        }
                    }
                }

                Color.clear.frame(height: TranceSpacing.tabBarClearance)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func openSource(_ source: ReadingSource) {
        TranceHaptics.shared.light()
        // Adult sources are only visible (and thus tappable) once the NSFW
        // toggle is on, which is itself the 18+ acknowledgment — open directly.
        browserDestination = BrowserDestination(
            url: source.url,
            suggestedTitle: source.title,
            allowsImport: source.canImport
        )
    }

    private func openScript(_ entry: ReadingScriptCatalogEntry) {
        TranceHaptics.shared.light()
        browserDestination = BrowserDestination(
            url: entry.url,
            suggestedTitle: entry.title,
            theme: entry.theme,
            allowsImport: entry.canImport
        )
    }

    private func importScript(_ entry: ReadingScriptCatalogEntry) {
        guard importingScriptID == nil else { return }

        guard entry.canImport else {
            importErrorText = "This source can only be opened as a website."
            importedScriptTitle = nil
            return
        }

        importingScriptID = entry.id
        importErrorText = nil
        importedScriptTitle = nil
        Task {
            do {
                let script = try await WebReadableTextImporter().importScript(
                    from: entry.url,
                    title: entry.title,
                    theme: entry.theme
                )
                await MainActor.run {
                    importingScriptID = nil
                    handleImportedScript(script)
                }
            } catch {
                await MainActor.run {
                    importingScriptID = nil
                    importErrorText = error.localizedDescription
                }
            }
        }
    }

    private func deleteSource(_ source: ReadingSource) {
        store.deleteCustomSource(id: source.id)
    }

    private func handleImportedScript(_ script: TranceScript) {
        if let onImported {
            onImported(script)
            return
        }

        do {
            try ImportedTranceScriptStore.shared.save(script)
            importErrorText = nil
            importedScriptTitle = script.title
        } catch {
            importErrorText = error.localizedDescription
            importedScriptTitle = nil
        }
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
    let allowsImport: Bool

    init(url: URL,
         suggestedTitle: String? = nil,
         theme: ScriptTheme = .focus,
         allowsImport: Bool = true) {
        self.url = url
        self.suggestedTitle = suggestedTitle
        self.theme = theme
        self.allowsImport = allowsImport
    }
}

private struct SourceGroup: Identifiable {
    let category: ReadingSourceCategory
    let sources: [ReadingSource]

    var id: ReadingSourceCategory { category }
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
                    // No import-policy badge here: the Import button below
                    // already communicates whether the entry is importable.
                }

                Text(entry.summary)
                    .font(TranceTypography.body)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    TagPill(text: entry.theme.displayName)
                    TagPill(text: entry.length.displayName)
                }

                HStack(spacing: TranceSpacing.inner) {
                    Button {
                        onImport(entry)
                    } label: {
                        HStack(spacing: TranceSpacing.icon) {
                            if isImporting {
                                ProgressView()
                                    .tint(Color.bgDeep)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                            }
                            Text(isImporting ? "Importing" : "Import")
                        }
                        .font(.headline)
                        .foregroundStyle(Color.bgDeep)
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
                        .opacity(isImporting || entry.canImport == false ? 0.48 : 1)
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
            // Uniform card height across the shelf, actions pinned to the
            // bottom edge.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 268)
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

                    if source.contentRating == .adultOnly {
                        AdultBadge()
                    }
                    ImportPolicyBadge(policy: source.importPolicy)
                }

                if !source.summary.isEmpty {
                    Text(source.summary)
                        .font(TranceTypography.body)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(source.licenseNote)
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(2)
                    Text(source.contentNote)
                        .font(TranceTypography.caption)
                        .foregroundStyle(.textLight)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                GlowButton(title: "Open", systemImage: "safari.fill", kind: .primary) {
                    onOpen(source)
                }
                .accessibilityLabel("Open \(source.title)")
            }
            // Uniform card height across the shelf, Open pinned to the bottom.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 300)
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
            .font(TranceTypography.cardLabel)
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

private struct ImportResultMessage: View {
    let title: String
    let message: String

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: TranceSpacing.list) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.roseGold)
                    .font(.system(size: 20, weight: .semibold))
                    .accessibilityHidden(true)

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
}

private struct ImportPolicyBadge: View {
    let policy: ReadingSourceImportPolicy

    var body: some View {
        Text(title)
            .font(TranceTypography.cardLabel)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var title: String {
        switch policy {
        case .linkOnly:            return "Link"
        case .userInitiatedImport: return "Import"
        case .catalogPlanned:      return "Catalog"
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
            .font(.system(.caption2, weight: .bold))
            .foregroundStyle(.warmAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.warmAccent.opacity(0.16), in: Capsule())
            .accessibilityLabel("Adult content")
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
                        .platformWordsAutocapitalized()
                    TextField("Website", text: $urlString)
                        .platformURLKeyboard()
                        .platformNeverAutocapitalized()
                        .platformAutocorrectionDisabled()
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
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
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
