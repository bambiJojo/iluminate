//  TextTranceRootView.swift
//  Ilumionate
//
//  NavigationStack host for the Text Trance (Read) tab. Owns the stores and
//  the import/history/browse flows; TextTranceLibraryView presents them as
//  shelves and reports taps back through closures.

import SwiftUI
import os

struct TextTranceRootView: View {
    var sharedImportTrigger = 0
    var quickStartTrigger = 0

    @State private var importedStore = ImportedTranceScriptStore.shared
    @State private var documentStore = ReadingDocumentStore.shared
    @State private var progressStore = ReaderProgressStore.shared
    @State private var sourceStore = ReadingSourceStore.shared
    @State private var scripts: [TranceScript] = []
    @State private var showingWebImport = false
    @State private var showingDocumentImporter = false
    @State private var showingReadingSources = false
    @State private var showingHistory = false
    @State private var documentImportState: DocumentImportState = .idle
    @State private var importedSetupScript: TranceScript?
    @State private var pendingHistoryScript: TranceScript?
    @State private var browsingSource: BrowsingSource?
    @State private var activeQuickStartSession: TextTranceSession?
    @State private var quickStartIndex = 0
    @State private var handledQuickStartTrigger = 0

    private let presetStore = ReaderPresetStore.shared

    // Mirrors the Settings toggle that gates adult (18+) sources.
    @AppStorage("nsfwSourcesEnabled") private var nsfwEnabled = false

    private struct BrowsingSource: Identifiable {
        let id = UUID()
        let source: ReadingSource
    }

    var body: some View {
        NavigationStack {
            TextTranceLibraryView(
                scripts: scripts,
                documents: documentStore.documents,
                sources: visibleSources,
                historyItems: historyItems,
                quickStartPlan: quickStartPlan,
                importState: documentImportState,
                onImportFile: { showingDocumentImporter = true },
                onLoadWebsite: { showingWebImport = true },
                onResume: { script in importedSetupScript = script },
                onSeeAllHistory: { showingHistory = true },
                onOpenSource: { source in browsingSource = BrowsingSource(source: source) },
                onSeeAllSources: { showingReadingSources = true },
                onOpenDocument: openDocument,
                onDeleteDocument: deleteDocument,
                onQuickStart: launchQuickStart
            )
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
        .platformFullScreenCover(item: $browsingSource) { destination in
            SafariBrowserView(
                url: destination.source.url,
                suggestedTitle: destination.source.title,
                allowsImport: destination.source.canImport,
                onImported: { script in
                    insertImportedScript(script)
                    importedSetupScript = script
                }
            )
        }
        .platformFullScreenCover(
            item: $activeQuickStartSession,
            onDismiss: handleQuickStartDismiss
        ) { session in
            TextTrancePlayerView(session: session, startIndex: quickStartIndex)
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
        .task {
            if scripts.isEmpty { reloadScripts() }
            await drainSharedImports()
            handleQuickStartTriggerIfNeeded()
        }
        .onChange(of: sharedImportTrigger) { _, _ in
            Task { await drainSharedImports() }
        }
        .onChange(of: quickStartTrigger) { _, _ in
            handleQuickStartTriggerIfNeeded()
        }
    }

    /// Curated + custom sources, with adult sources hidden unless enabled.
    private var visibleSources: [ReadingSource] {
        sourceStore.sources(in: nil).filter { source in
            nsfwEnabled || source.contentRating != .adultOnly
        }
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

    private var quickStartPlan: ReaderQuickStartPlan? {
        ReaderQuickStartPlan.select(
            scripts: scripts,
            historyItems: historyItems,
            preset: { presetStore.preset(forScriptId: $0) }
        )
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
            Log.ui.info("[TextTranceRootView] Import was not persisted: \(error.localizedDescription)")
        }

        scripts.removeAll { $0.id == script.id }
        scripts.insert(script, at: 0)
    }

    private func launchQuickStart(_ plan: ReaderQuickStartPlan) {
        UsageAnalytics.shared.readerQuickStartSelected(plan.startType)
        quickStartIndex = plan.startIndex
        activeQuickStartSession = plan.makeSession(progressStore: progressStore)
    }

    private func handleQuickStartTriggerIfNeeded() {
        guard quickStartTrigger > handledQuickStartTrigger,
              let quickStartPlan else { return }
        handledQuickStartTrigger = quickStartTrigger
        launchQuickStart(quickStartPlan)
    }

    private func handleQuickStartDismiss() {
        if let activeQuickStartSession, !activeQuickStartSession.isComplete {
            activeQuickStartSession.end()
        }
        activeQuickStartSession = nil
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

#Preview { TextTranceRootView() }
