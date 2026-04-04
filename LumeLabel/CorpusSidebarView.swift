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
                Button("Import Audio", systemImage: "plus") {
                    isImporting = true
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
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            Task { await importURLs(urls) }
            return true
        }
        .alert("Corpus Error", isPresented: Binding(
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
                alertMessage = error.localizedDescription
                return
            }
        }
    }

    private func delete(_ file: LabeledFile) async {
        do {
            if selectedFileID == file.id {
                selectedFileID = nil
            }
            try await corpus.delete(file)
        } catch {
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
                    Text("·")
                    Text(file.expectedContentType.rawValue.capitalized)
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
