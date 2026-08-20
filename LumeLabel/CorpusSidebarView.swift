//
//  CorpusSidebarView.swift
//  LumeLabel
//
//  Sidebar listing all labeled files with status badges and drag-drop import.
//

import SwiftUI
import UniformTypeIdentifiers

struct CorpusSidebarView: View {
    private enum ImportRequest {
        case audio
        case folder(TrancePhase)

        var allowedContentTypes: [UTType] {
            switch self {
            case .audio: [.audio]
            case .folder: [.folder]
            }
        }

        var allowsMultipleSelection: Bool {
            switch self {
            case .audio: true
            case .folder: false
            }
        }
    }

    @Environment(TrainingCorpusManager.self) private var corpus
    @Binding var selectedFileID: LabeledFile.ID?
    @State private var isFileImporterPresented = false
    @State private var importRequest: ImportRequest = .audio
    @State private var alertTitle = "Corpus Error"
    @State private var alertMessage: String?
    @State private var workflow = TrainingWorkflowController()
    @State private var bulkTranscription = BulkTranscriptionController()
    @State private var sortOrder: CorpusSortOrder = .name

    /// Recomputed rather than observed: the cache is written by a background run
    /// and by the detail editor, so the filesystem is the only source that is
    /// always right. Refreshed when the corpus changes or a bulk run advances.
    @State private var transcribedHashes: Set<String> = []

    private var sortedFiles: [LabeledFile] {
        TranscriptInventory.sorted(corpus.labeledFiles, by: sortOrder, transcribed: transcribedHashes)
    }

    var body: some View {
        VStack(spacing: 0) {
            CorpusTrainingWorkflowPanel(
                totalFileCount: corpus.labeledFiles.count,
                labeledFileCount: corpus.labeledFiles.filter { $0.status != .unlabeled }.count,
                workflow: workflow
            )

            if bulkTranscription.isRunning || bulkTranscription.statusMessage != nil {
                BulkTranscriptionBanner(controller: bulkTranscription)
            }

            List(sortedFiles, selection: $selectedFileID) { file in
                CorpusFileRow(
                    file: file,
                    hasTranscript: transcribedHashes.contains(file.audioSHA256)
                )
                    .tag(file.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            Task { await delete(file) }
                        }
                    }
            }
        }
        .task(id: corpus.labeledFiles.count) { refreshTranscribedHashes() }
        .onChange(of: bulkTranscription.completed) { refreshTranscribedHashes() }
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

            ToolbarItem(placement: .automatic) {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(CorpusSortOrder.allCases, id: \.rawValue) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }

            ToolbarItem(placement: .automatic) {
                if bulkTranscription.isRunning {
                    Button("Stop", systemImage: "stop.fill") {
                        bulkTranscription.cancel()
                        refreshTranscribedHashes()
                    }
                } else {
                    Button("Transcribe All", systemImage: "waveform.badge.plus") {
                        bulkTranscription.start(corpus: corpus)
                    }
                    .disabled(corpus.labeledFiles.isEmpty)
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Menu("Import", systemImage: "plus") {
                    Button("Import Audio", systemImage: "waveform") {
                        importRequest = .audio
                        isFileImporterPresented = true
                    }

                    Menu("Batch Label Folder", systemImage: "folder.badge.plus") {
                        ForEach(TrancePhase.orderedHypnosisPhases, id: \.rawValue) { phase in
                            Button(phase.displayName) {
                                importRequest = .folder(phase)
                                isFileImporterPresented = true
                            }
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: importRequest.allowedContentTypes,
            allowsMultipleSelection: importRequest.allowsMultipleSelection
        ) { result in
            handleImport(result, request: importRequest)
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

    private func refreshTranscribedHashes() {
        transcribedHashes = TranscriptInventory.availableHashes(in: corpus.analyzerDatasetDirectory)
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

    private func handleImport(
        _ result: Result<[URL], Error>,
        request: ImportRequest
    ) {
        switch result {
        case .success(let urls):
            switch request {
            case .audio:
                Task { await importURLs(urls) }
            case .folder(let phase):
                guard let folderURL = urls.first else { return }
                Task { await importFolder(folderURL, phase: phase) }
            }
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

struct BulkTranscriptionBanner: View {
    let controller: BulkTranscriptionController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if controller.isRunning {
                ProgressView(value: controller.progress)
                Text(controller.currentFilename ?? "Starting…")
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(controller.completed) of \(controller.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let statusMessage = controller.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(controller.failures.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
            }

            // Named rather than counted: after an unattended run the useful
            // question is which files still have no transcript.
            ForEach(controller.failures.prefix(3), id: \.filename) { failure in
                Text("\(failure.filename): \(failure.reason)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

struct CorpusFileRow: View {
    let file: LabeledFile
    let hasTranscript: Bool

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
            Spacer()
            // Filled versus outline, not two shades of the same glyph: the list
            // is scanned to find what still needs work.
            Image(systemName: hasTranscript ? "text.bubble.fill" : "text.bubble")
                .foregroundStyle(hasTranscript ? Color.accentColor : Color.secondary.opacity(0.4))
                .help(hasTranscript ? "Transcript cached" : "No transcript yet")
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
