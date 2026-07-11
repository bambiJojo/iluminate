//  TextTranceLibraryView.swift
//  Ilumionate
//
//  Script picker: theme filter + cards. Tapping a card pushes setup.

import SwiftUI
import os

/// Typed navigation values for the Text Trance stack (avoids bare-String
/// destination collisions as more destinations join this stack).
enum TextTranceDestination: Hashable {
    case setup(scriptID: String)
}

private enum DocumentImportState: Equatable {
    case idle
    case importing(String)
    case failed(String)
}

struct TextTranceLibraryView: View {
    var sharedImportTrigger = 0

    @State private var importedStore = ImportedTranceScriptStore.shared
    @State private var documentStore = ReadingDocumentStore.shared
    @State private var scripts: [TranceScript] = []
    @State private var themeFilter: ScriptTheme?
    @State private var progressStore = ReaderProgressStore.shared
    @State private var quickActionsCollapseProgress: CGFloat = 0
    @State private var showingWebImport = false
    @State private var showingDocumentImporter = false
    @State private var showingReadingSources = false
    @State private var showingHistory = false
    @State private var documentImportState: DocumentImportState = .idle
    @State private var importedSetupScript: TranceScript?
    @State private var pendingHistoryScript: TranceScript?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                LazyVStack(spacing: TranceSpacing.cardMargin) {
                    ReaderLibrarySummaryCard(
                        scripts: scripts,
                        documents: documentStore.documents
                    )

                    if documentImportState != .idle {
                        DocumentImportStatusCard(state: documentImportState)
                    }

                    ThemeChipsRow(selection: $themeFilter)

                    if !documentStore.documents.isEmpty {
                        DocumentLibrarySection(
                            documents: documentStore.documents,
                            onOpen: openDocument,
                            onDelete: deleteDocument
                        )
                    }

                    if filteredScripts.isEmpty {
                        EmptyScriptLibraryCard()
                    } else {
                        SectionHeader(title: "Scripts")
                        ForEach(filteredScripts) { script in
                            NavigationLink(value: TextTranceDestination.setup(scriptID: script.id)) {
                                ScriptCard(script: script)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // Clear the app's floating tab bar so the last card isn't cut off.
                    Color.clear.frame(height: TranceSpacing.tabBarClearance)
                }
                .padding(TranceSpacing.screen)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let offset = geometry.contentOffset.y + geometry.contentInsets.top
                return min(max((offset - 12) / 40, 0), 1)
            } action: { _, progress in
                quickActionsCollapseProgress = progress
            }
        }
        .navigationTitle("Text Trance")
        .safeAreaBar(edge: .top) {
            ReaderQuickActionsBar(
                collapseProgress: quickActionsCollapseProgress,
                onImportFile: { showingDocumentImporter = true },
                onLoadWebsite: { showingWebImport = true },
                onFindScripts: { showingReadingSources = true },
                onHistory: { showingHistory = true }
            )
            .padding(.horizontal, TranceSpacing.screen)
            .padding(.vertical, TranceSpacing.icon)
        }
        .sheet(isPresented: $showingWebImport) {
            WebTextImportSheet { script in
                insertImportedScript(script)
                importedSetupScript = script
            }
        }
        .sheet(isPresented: $showingHistory, onDismiss: openPendingHistoryScript) {
            ReaderHistorySheet(items: historyItems) { script in
                pendingHistoryScript = script
            }
        }
        .fileImporter(
            isPresented: $showingDocumentImporter,
            allowedContentTypes: ReadingDocumentImporter.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importDocument(from: url) }
            case .failure(let error):
                documentImportState = .failed(error.localizedDescription)
            }
        }
        .navigationDestination(for: TextTranceDestination.self) { destination in
            switch destination {
            case .setup(let id):
                if let script = scripts.first(where: { $0.id == id }) {
                    TextTranceSetupView(script: script)
                }
            }
        }
        .navigationDestination(isPresented: importedSetupPresented) {
            if let importedSetupScript {
                TextTranceSetupView(script: importedSetupScript)
            }
        }
        .navigationDestination(isPresented: $showingReadingSources) {
            ReadingSourceDirectoryView(store: .shared) { script in
                insertImportedScript(script)
                importedSetupScript = script
            }
        }
        .task {
            if scripts.isEmpty { reloadScripts() }
            await drainSharedImports()
        }
        .onChange(of: sharedImportTrigger) { _, _ in
            Task { await drainSharedImports() }
        }
    }

    private var filteredScripts: [TranceScript] {
        guard let themeFilter else { return scripts }
        return scripts.filter { $0.theme == themeFilter }
    }

    private var historyItems: [ReaderHistoryItem] {
        progressStore.recentStates.compactMap { state in
            if let script = scripts.first(where: { $0.id == state.scriptId }) {
                return ReaderHistoryItem(script: script, state: state)
            }

            guard let document = documentStore.documents.first(where: { $0.scriptID == state.scriptId }),
                  let script = try? documentStore.script(for: document) else {
                return nil
            }
            return ReaderHistoryItem(script: script, state: state)
        }
    }

    private var importedSetupPresented: Binding<Bool> {
        Binding(
            get: { importedSetupScript != nil },
            set: { if !$0 { importedSetupScript = nil } }
        )
    }

    private func insertImportedScript(_ script: TranceScript) {
        do {
            try importedStore.save(script)
            reloadScripts()
            return
        } catch {
            Log.ui.info("[TextTranceLibraryView] Import was not persisted: \(error.localizedDescription)")
        }

        scripts.removeAll { $0.id == script.id }
        scripts.insert(script, at: 0)
    }

    private func openPendingHistoryScript() {
        guard let pendingHistoryScript else { return }
        self.pendingHistoryScript = nil
        importedSetupScript = pendingHistoryScript
    }

    private func importDocument(from url: URL) async {
        documentImportState = .importing(url.lastPathComponent)
        do {
            let document = try await documentStore.importDocument(from: url)
            documentImportState = .idle
            importedSetupScript = try documentStore.script(for: document)
        } catch {
            documentImportState = .failed(error.localizedDescription)
        }
    }

    private func openDocument(_ document: ReadingDocument) {
        do {
            importedSetupScript = try documentStore.script(for: document)
        } catch {
            documentImportState = .failed(error.localizedDescription)
        }
    }

    private func deleteDocument(_ document: ReadingDocument) {
        do {
            try documentStore.delete(document)
            ReaderProgressStore.shared.clear(scriptId: document.scriptID)
        } catch {
            documentImportState = .failed(error.localizedDescription)
        }
    }

    private func reloadScripts() {
        let importedScripts = importedStore.importedScripts
        let importedIDs = Set(importedScripts.map(\.id))
        scripts = importedScripts + TranceScriptLibrary.bundled().filter { script in
            importedIDs.contains(script.id) == false
        }
    }

    private func drainSharedImports() async {
        guard !SharedReaderImportQueue.pendingItems().isEmpty else { return }
        documentImportState = .importing("Shared items")

        let result = await SharedReaderImportCoordinator(
            importedStore: importedStore,
            documentStore: documentStore
        ).drainPendingImports()

        reloadScripts()
        if result.failureMessages.isEmpty {
            documentImportState = .idle
        } else {
            documentImportState = .failed(result.failureMessages.joined(separator: "\n"))
        }
    }

}

private struct ThemeChipsRow: View {
    @Binding var selection: ScriptTheme?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: TranceSpacing.list) {
                FilterChip(title: "All", isOn: selection == nil) { selection = nil }
                ForEach(ScriptTheme.allCases) { theme in
                    FilterChip(title: theme.displayName, isOn: selection == theme) {
                        selection = theme
                    }
                }
            }
            .padding(.vertical, TranceSpacing.micro)
        }
        .scrollIndicators(.hidden)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(TranceTypography.sectionTitle)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, TranceSpacing.micro)
    }
}

private struct DocumentLibrarySection: View {
    let documents: [ReadingDocument]
    let onOpen: (ReadingDocument) -> Void
    let onDelete: (ReadingDocument) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TranceSpacing.list) {
            SectionHeader(title: "Documents")
            ForEach(documents) { document in
                Button {
                    onOpen(document)
                } label: {
                    DocumentCard(document: document)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Open", systemImage: "play.fill") {
                        onOpen(document)
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        onDelete(document)
                    }
                }
            }
        }
    }
}

private struct DocumentCard: View {
    let document: ReadingDocument

    var body: some View {
        LiminalCard(label: nil) {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(alignment: .top, spacing: TranceSpacing.list) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.bwBeta.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: document.kind.systemImage)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.bwBeta)
                        }

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(document.title)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(2)
                        Text(document.originalFilename)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                HStack(spacing: 6) {
                    MetricPill(systemImage: "doc.text", text: document.kind.displayName)
                    MetricPill(systemImage: "textformat", text: document.wordCountSummary)
                    MetricPill(systemImage: "calendar", text: document.importedAt.formatted(.dateTime.month().day()))
                }

                HStack(spacing: 6) {
                    TagChip(text: "Document")
                    TagChip(text: "Read-through")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ScriptCard: View {
    let script: TranceScript

    var body: some View {
        LiminalCard(label: nil) {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(alignment: .top, spacing: TranceSpacing.list) {
                    ScriptThemeIcon(theme: script.theme)

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(script.title)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                        Text(script.theme.displayName)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Text(script.librarySummary)
                    .font(TranceTypography.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    MetricPill(systemImage: "clock", text: script.durationSummary)
                    MetricPill(systemImage: "textformat", text: script.wordCountSummary)
                }

                Text(script.phaseSummary)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textLight)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    TagChip(text: script.arcSummary)
                    if script.source.kind == .importedWeb { TagChip(text: "Web") }
                    if script.source.kind == .importedDocument { TagChip(text: "Document") }
                    if script.source.reviewed { TagChip(text: "Reviewed") }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ReaderLibrarySummaryCard: View {
    let scripts: [TranceScript]
    let documents: [ReadingDocument]

    var body: some View {
        LiminalCard(label: "Reader library") {
            HStack(spacing: TranceSpacing.list) {
                SummaryValue(value: documents.count.formatted(.number), label: "documents")
                Divider()
                    .frame(height: 32)
                    .overlay(Color.glassBorder)
                SummaryValue(value: scripts.count.formatted(.number), label: "scripts")
                Divider()
                    .frame(height: 32)
                    .overlay(Color.glassBorder)
                SummaryValue(value: themeCount.formatted(.number), label: "themes")
                Divider()
                    .frame(height: 32)
                    .overlay(Color.glassBorder)
                SummaryValue(value: durationRange, label: "read time")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var themeCount: Int {
        Set(scripts.map(\.theme.rawValue)).count
    }

    private var durationRange: String {
        let scriptDurations = scripts.flatMap { script in
            script.supportedArcs.map { script.metrics(for: $0).estimatedDuration }
        }
        let documentDurations = documents.map { document in
            Double(document.wordCount) / TextPacingEngine.defaultBaseWPM * 60
        }
        let durations = scriptDurations + documentDurations
        let minutes = durations.map { max(1, Int(($0 / 60).rounded())) }
        guard let min = minutes.min(), let max = minutes.max() else { return "0 min" }
        if min == max { return min == 1 ? "1 min" : "\(min) min" }
        return "\(min)-\(max) min"
    }
}

private struct SummaryValue: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(TranceTypography.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyScriptLibraryCard: View {
    var body: some View {
        GlassCard(label: nil) {
            HStack(spacing: TranceSpacing.list) {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(Color.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No scripts here")
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text("Use the actions above to import or find one.")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DocumentImportStatusCard: View {
    let state: DocumentImportState

    var body: some View {
        GlassCard(label: nil) {
            HStack(alignment: .top, spacing: TranceSpacing.list) {
                switch state {
                case .idle:
                    EmptyView()
                case .importing:
                    ProgressView()
                        .tint(.auroraTeal)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.warmAccent)
                        .font(.system(size: 20, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                    Text(title)
                        .font(TranceTypography.sectionTitle)
                        .foregroundStyle(Color.textPrimary)
                    Text(message)
                        .font(TranceTypography.body)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var title: String {
        switch state {
        case .idle:
            return ""
        case .importing:
            return "Importing document"
        case .failed:
            return "Import failed"
        }
    }

    private var message: String {
        switch state {
        case .idle:
            return ""
        case .importing(let filename):
            return filename
        case .failed(let message):
            return message
        }
    }
}

private struct TagChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(TranceTypography.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.auroraTeal.opacity(0.18), in: .capsule)
            .foregroundStyle(Color.auroraTeal)
    }
}

private struct MetricPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(TranceTypography.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.glassBorder.opacity(0.28), in: .capsule)
            .foregroundStyle(Color.textSecondary)
    }
}

private struct ScriptThemeIcon: View {
    let theme: ScriptTheme

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.accent.opacity(0.18))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: theme.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(TranceTypography.caption)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(
                isOn ? Color.auroraTeal.opacity(0.22) : Color.glassBorder.opacity(0.4),
                in: .capsule
            )
            .foregroundStyle(isOn ? Color.auroraTeal : Color.textSecondary)
            .buttonStyle(.plain)
    }
}

private struct WebTextImportSheet: View {
    let importer: WebReadableTextImporter
    let onImported: (TranceScript) -> Void

    @State private var urlString = ""
    @State private var title = ""
    @State private var importState: ImportState = .idle

    @Environment(\.dismiss) private var dismiss

    init(importer: WebReadableTextImporter = WebReadableTextImporter(),
         onImported: @escaping (TranceScript) -> Void) {
        self.importer = importer
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Page") {
                    TextField("URL", text: $urlString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Button {
                        Task { await importPage() }
                    } label: {
                        HStack(spacing: TranceSpacing.icon) {
                            if importState.isImporting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "text.page.badge.magnifyingglass")
                            }
                            Text(importState.isImporting ? "Reading" : "Read")
                        }
                        .font(TranceTypography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            LinearGradient(
                                colors: [.roseGold, .roseDeep],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: TranceRadius.button)
                        )
                        .opacity(importDisabled ? 0.48 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(importDisabled)
                    .accessibilityLabel(importState.isImporting ? "Reading webpage" : "Read webpage")
                }

                if importState.isImporting {
                    Section {
                        ProgressView("Importing")
                    }
                }

                if case .failed(let message) = importState {
                    Section {
                        Text(message)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Webpage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(importState.isImporting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Read") {
                        Task { await importPage() }
                    }
                    .fontWeight(.semibold)
                    .disabled(importDisabled)
                }
            }
        }
    }

    private var importDisabled: Bool {
        importState.isImporting || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func importPage() async {
        importState = .importing
        do {
            let script = try await importer.importScript(from: urlString, title: title)
            onImported(script)
            dismiss()
        } catch {
            importState = .failed(error.localizedDescription)
        }
    }

    private enum ImportState: Equatable {
        case idle
        case importing
        case failed(String)

        var isImporting: Bool {
            if case .importing = self { return true }
            return false
        }
    }
}

#Preview {
    NavigationStack { TextTranceLibraryView() }
}
