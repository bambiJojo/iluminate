//  TextTranceLibraryView.swift
//  Ilumionate
//
//  Reader library shelves: Apple Music-style vertical scroll of horizontal
//  carousels. All actions and stores live in TextTranceRootView, which owns
//  the persistent quick-actions bar; this view just presents the content.

import SwiftUI

/// Typed navigation values for the Text Trance stack (avoids bare-String
/// destination collisions as more destinations join this stack).
enum TextTranceDestination: Hashable {
    case setup(scriptID: String)
}

enum DocumentImportState: Equatable {
    case idle
    case importing(String)
    case failed(String)
}

struct TextTranceLibraryView: View {
    let scripts: [TranceScript]
    let documents: [ReadingDocument]
    let sources: [ReadingSource]
    let historyItems: [ReaderHistoryItem]
    let quickStartPlan: ReaderQuickStartPlan?
    let importState: DocumentImportState
    let onImportFile: () -> Void
    let onLoadWebsite: () -> Void
    let onResume: (TranceScript) -> Void
    let onSeeAllHistory: () -> Void
    let onOpenSource: (ReadingSource) -> Void
    let onSeeAllSources: () -> Void
    let onOpenDocument: (ReadingDocument) -> Void
    let onDeleteDocument: (ReadingDocument) -> Void
    let onQuickStart: (ReaderQuickStartPlan) -> Void

    var body: some View {
        ZStack {
            AuroraBackground()
            // Apple Music-style shelves: a vertical scroll of horizontal
            // carousels, one shelf per content group. Imports live in the
            // header's + menu; history and sites are shelves of their own.
            ScrollView {
                VStack(alignment: .leading, spacing: TranceSpacing.cardMargin) {
                    LibraryHeader(
                        onImportFile: onImportFile,
                        onLoadWebsite: onLoadWebsite
                    )
                    .padding(.horizontal, TranceSpacing.screen)

                    if let quickStartPlan {
                        ReaderQuickStartCard(
                            plan: quickStartPlan,
                            onStart: onQuickStart
                        )
                        .padding(.horizontal, TranceSpacing.screen)
                    }

                    if importState != .idle {
                        DocumentImportStatusCard(state: importState)
                            .padding(.horizontal, TranceSpacing.screen)
                    }

                    if !historyItems.isEmpty {
                        SectionHeader(title: "Continue Reading", onSeeAll: onSeeAllHistory)
                            .padding(.horizontal, TranceSpacing.screen)
                        HistoryCarousel(items: historyItems, onResume: onResume)
                    }

                    if !documents.isEmpty {
                        SectionHeader(title: "Documents")
                            .padding(.horizontal, TranceSpacing.screen)
                        DocumentCarousel(
                            documents: documents,
                            onOpen: onOpenDocument,
                            onDelete: onDeleteDocument
                        )
                    }

                    if scripts.isEmpty {
                        EmptyScriptLibraryCard()
                            .padding(.horizontal, TranceSpacing.screen)
                    } else {
                        SectionHeader(title: "Scripts")
                            .padding(.horizontal, TranceSpacing.screen)
                        ScriptCarousel(scripts: scripts)
                    }

                    if !sources.isEmpty {
                        SectionHeader(title: "Sites", onSeeAll: onSeeAllSources)
                            .padding(.horizontal, TranceSpacing.screen)
                        SourceCarousel(sources: sources, onOpen: onOpenSource)
                    }
                    // Clear the app's floating tab bar so the last card isn't cut off.
                    Color.clear.frame(height: TranceSpacing.tabBarClearance)
                }
                .padding(.vertical, TranceSpacing.screen)
            }
            .scrollIndicators(.hidden)
        }
    }

}

/// "Reader" title with the + menu that gathers the import actions.
private struct LibraryHeader: View {
    let onImportFile: () -> Void
    let onLoadWebsite: () -> Void

    var body: some View {
        HStack {
            Text("Reader")
                .font(TranceTypography.navTitle)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Menu {
                Button("Import File", systemImage: "doc.badge.plus", action: onImportFile)
                Button("Load Website", systemImage: "square.and.arrow.down", action: onLoadWebsite)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.roseGold)
                    .frame(width: 36, height: 36)
                    .background(Color.glassBorder.opacity(0.14), in: .circle)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.glassBorder.opacity(0.35), lineWidth: 1)
                    }
            }
            .accessibilityLabel("Add reading material")
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var onSeeAll: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TranceTypography.sectionTitle)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if let onSeeAll {
                Button("See all", action: onSeeAll)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.roseGold)
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, TranceSpacing.micro)
    }
}

/// Horizontal shelf of resumable reads; tapping a card opens setup ready to
/// resume at the saved word.
private struct HistoryCarousel: View {
    let items: [ReaderHistoryItem]
    let onResume: (TranceScript) -> Void

    var body: some View {
        CarouselRow(items: items) { item in
            Button {
                onResume(item.script)
            } label: {
                HistoryCard(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct HistoryCard: View {
    let item: ReaderHistoryItem

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(spacing: TranceSpacing.list) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(item.script.theme.accent.opacity(0.18))
                        .frame(width: 40, height: 40)
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
                            .lineLimit(1)
                        Text("Word \(item.state.wordIndex + 1) · \(item.state.savedAt.formatted(.relative(presentation: .named)))")
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                Label("Resume", systemImage: "play.fill")
                    .font(TranceTypography.caption.weight(.semibold))
                    .foregroundStyle(Color.bgDeep)
                    .padding(.horizontal, TranceSpacing.list)
                    .padding(.vertical, TranceSpacing.icon)
                    .background(
                        LinearGradient(colors: [.roseGold, .roseDeep],
                                       startPoint: .leading, endPoint: .trailing),
                        in: .capsule
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 128)
    }
}

/// Horizontal shelf of curated reading sites; tapping opens the in-app browser.
private struct SourceCarousel: View {
    let sources: [ReadingSource]
    let onOpen: (ReadingSource) -> Void

    var body: some View {
        CarouselRow(items: sources) { source in
            Button {
                TranceHaptics.shared.light()
                onOpen(source)
            } label: {
                SourceShelfCard(source: source)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SourceShelfCard: View {
    let source: ReadingSource

    var body: some View {
        LiminalCard {
            VStack(alignment: .leading, spacing: TranceSpacing.list) {
                HStack(alignment: .top, spacing: TranceSpacing.list) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.bwTheta.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "globe")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.bwTheta)
                        }

                    VStack(alignment: .leading, spacing: TranceSpacing.micro) {
                        Text(source.title)
                            .font(TranceTypography.sectionTitle)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(source.url.host(percentEncoded: false) ?? source.url.absoluteString)
                            .font(TranceTypography.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "safari")
                        .font(TranceTypography.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Text(source.summary)
                    .font(TranceTypography.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 118)
    }
}

/// Horizontal shelf of script cards for one theme.
private struct ScriptCarousel: View {
    let scripts: [TranceScript]

    var body: some View {
        CarouselRow(items: scripts) { script in
            NavigationLink(value: TextTranceDestination.setup(scriptID: script.id)) {
                ScriptCard(script: script)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Horizontal shelf of imported documents.
private struct DocumentCarousel: View {
    let documents: [ReadingDocument]
    let onOpen: (ReadingDocument) -> Void
    let onDelete: (ReadingDocument) -> Void

    var body: some View {
        CarouselRow(items: documents) { document in
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

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    MetricPill(systemImage: "doc.text", text: document.kind.displayName)
                    MetricPill(systemImage: "textformat", text: document.wordCountSummary)
                    MetricPill(systemImage: "calendar", text: document.importedAt.formatted(.dateTime.month().day()))
                }
            }
            // Uniform card height across the documents carousel.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 132)
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
                            .lineLimit(1)
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
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    MetricPill(systemImage: "clock", text: script.durationSummary)
                    MetricPill(systemImage: "textformat", text: script.wordCountSummary)
                }

                HStack(spacing: 6) {
                    TagChip(text: script.arcSummary)
                    if script.source.kind == .importedWeb { TagChip(text: "Web") }
                    if script.source.kind == .importedDocument { TagChip(text: "Document") }
                    if script.source.reviewed { TagChip(text: "Reviewed") }
                }
            }
            // Fill the carousel's fixed card height so every page's glass
            // surface matches, with the tag row pinned to the bottom edge.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 228)
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
                        .tint(.roseGold)
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
            .background(Color.roseGold.opacity(0.18), in: .capsule)
            .foregroundStyle(Color.roseGold)
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

struct WebTextImportSheet: View {
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
                        .platformURLKeyboard()
                        .platformNeverAutocapitalized()
                        .platformAutocorrectionDisabled()
                    TextField("Title", text: $title)
                        .platformWordsAutocapitalized()
                }

                Section {
                    Button {
                        Task { await importPage() }
                    } label: {
                        HStack(spacing: TranceSpacing.icon) {
                            if importState.isImporting {
                                ProgressView()
                                    .tint(Color.bgDeep)
                            } else {
                                Image(systemName: "text.page.badge.magnifyingglass")
                            }
                            Text(importState.isImporting ? "Reading" : "Read")
                        }
                        .font(.headline)
                        .foregroundStyle(Color.bgDeep)
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

                if case .failed(let message) = importState {
                    Section {
                        Text(message)
                            .font(TranceTypography.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Webpage")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(importState.isImporting)
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
    NavigationStack {
        TextTranceLibraryView(
            scripts: TranceScriptLibrary.bundled(),
            documents: [],
            sources: [],
            historyItems: [],
            quickStartPlan: nil,
            importState: .idle,
            onImportFile: {},
            onLoadWebsite: {},
            onResume: { _ in },
            onSeeAllHistory: {},
            onOpenSource: { _ in },
            onSeeAllSources: {},
            onOpenDocument: { _ in },
            onDeleteDocument: { _ in },
            onQuickStart: { _ in }
        )
    }
}
