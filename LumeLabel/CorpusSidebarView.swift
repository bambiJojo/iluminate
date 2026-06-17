//
//  CorpusSidebarView.swift
//  LumeLabel
//
//  Sidebar listing all labeled files with status badges and drag-drop import.
//

import SwiftUI
import UniformTypeIdentifiers

struct CorpusSidebarView: View {
    @Environment(TrainingCorpusManager.self) private var corpus
    @Binding var selectedFileID: LabeledFile.ID?
    @State private var isImporting = false
    @State private var isBatchImporting = false
    @State private var batchImportPhase: TrancePhase = .induction
    @State private var alertTitle = "Corpus Error"
    @State private var alertMessage: String?
    @State private var workflow = TrainingWorkflowController()

    var body: some View {
        VStack(spacing: 0) {
            CorpusTrainingWorkflowPanel(
                totalFileCount: corpus.labeledFiles.count,
                labeledFileCount: corpus.labeledFiles.filter { $0.status != .unlabeled }.count,
                workflow: workflow
            )

            List(corpus.labeledFiles, selection: $selectedFileID) { file in
                CorpusFileRow(file: file)
                    .tag(file.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            Task { await delete(file) }
                        }
                    }
            }
        }
        .navigationTitle("Corpus")
        .navigationSubtitle(subtitleText)
        .toolbar {
            ToolbarItemGroup(placement: .secondaryAction) {
                Button("Measure", systemImage: TrainingWorkflowAction.measure.systemImage) {
                    workflow.startMeasure()
                }
                .disabled(workflow.isRunning || workflow.datasetSnapshot.validExampleCount == 0)

                Button("Optimize", systemImage: TrainingWorkflowAction.optimize.systemImage) {
                    workflow.startOptimize()
                }
                .disabled(workflow.isRunning || workflow.datasetSnapshot.validExampleCount == 0)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu("Import", systemImage: "plus") {
                    Button("Import Audio", systemImage: "waveform") {
                        isImporting = true
                    }

                    Menu("Batch Label Folder", systemImage: "folder.badge.plus") {
                        ForEach(TrancePhase.orderedHypnosisPhases, id: \.rawValue) { phase in
                            Button(phase.displayName) {
                                batchImportPhase = phase
                                isBatchImporting = true
                            }
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .fileImporter(
            isPresented: $isBatchImporting,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleBatchImport(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            Task { await importURLs(urls) }
            return true
        }
        .alert(alertTitle, isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { workflow.isSheetPresented },
            set: { workflow.isSheetPresented = $0 }
        )) {
            TrainingWorkflowSheet(workflow: workflow)
        }
        .task(id: workflowRefreshKey) {
            await workflow.refreshSnapshot()
        }
    }

    private var subtitleText: String {
        let total = corpus.labeledFiles.count
        let labeled = corpus.labeledFiles.filter { $0.status != .unlabeled }.count
        return "\(labeled)/\(total) labeled"
    }

    private var workflowRefreshKey: String {
        corpus.labeledFiles
            .map { "\($0.id.uuidString)-\($0.labeledAt.timeIntervalSince1970)" }
            .joined(separator: "|")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await importURLs(urls) }
        case .failure(let error):
            alertTitle = "Corpus Error"
            alertMessage = error.localizedDescription
        }
    }

    private func handleBatchImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folderURL = urls.first else { return }
            Task { await importFolder(folderURL, phase: batchImportPhase) }
        case .failure(let error):
            alertTitle = "Corpus Error"
            alertMessage = error.localizedDescription
        }
    }

    private func importURLs(_ urls: [URL]) async {
        for url in urls {
            do {
                let imported = try await withSecurityScopedAccess(to: url) {
                    try await corpus.importAudio(from: url)
                }
                selectedFileID = imported.id
            } catch {
                alertTitle = "Corpus Error"
                alertMessage = error.localizedDescription
                return
            }
        }
    }

    private func importFolder(_ folderURL: URL, phase: TrancePhase) async {
        do {
            let result = try await withSecurityScopedAccess(to: folderURL) {
                try await corpus.importAudioFolder(from: folderURL, labeledAs: phase)
            }
            selectedFileID = result.importedFiles.first?.id
            alertTitle = "Batch Import Complete"
            alertMessage = batchImportSummary(for: result, phase: phase)
        } catch {
            alertTitle = "Corpus Error"
            alertMessage = error.localizedDescription
        }
    }

    private func batchImportSummary(for result: BatchPhaseImportResult, phase: TrancePhase) -> String {
        var summary = "Imported \(result.importedFiles.count) file\(result.importedFiles.count == 1 ? "" : "s") as \(phase.displayName)."
        if !result.skippedFilenames.isEmpty {
            let preview = result.skippedFilenames.prefix(5).joined(separator: ", ")
            let suffix = result.skippedFilenames.count > 5 ? ", …" : ""
            summary += "\nSkipped \(result.skippedFilenames.count): \(preview)\(suffix)"
        }
        return summary
    }

    private func delete(_ file: LabeledFile) async {
        do {
            if selectedFileID == file.id {
                selectedFileID = nil
            }
            try await corpus.delete(file)
        } catch {
            alertTitle = "Corpus Error"
            alertMessage = error.localizedDescription
        }
    }

    private func withSecurityScopedAccess<T>(
        to url: URL,
        operation: () async throws -> T
    ) async throws -> T {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try await operation()
    }
}

// MARK: - File Row

struct CorpusFileRow: View {
    let file: LabeledFile

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(file.audioFilename)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(Duration.seconds(file.audioDuration).formatted(.time(pattern: .minuteSecond)))
                    Text("·")
                    Text("\(file.phases.count) phase\(file.phases.count == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        let (icon, color): (String, Color) = switch file.status {
        case .unlabeled: ("circle.dashed", .secondary)
        case .rough:     ("circle.lefthalf.filled", .orange)
        case .refined:   ("checkmark.circle.fill", .green)
        }
        return Image(systemName: icon)
            .foregroundStyle(color)
    }
}
