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
    @Environment(LabelingSprintController.self) private var labelingSprint
    @Binding var selectedFileID: LabeledFile.ID?
    @State private var isFileImporterPresented = false
    @State private var importRequest: ImportRequest = .audio
    @State private var alertTitle = "Corpus Error"
    @State private var alertMessage: String?
    @State private var workflow = TrainingWorkflowController()
    @State private var bulkTranscription = BulkTranscriptionController()
    @State private var bambiDerivation = BambiDerivedLabelingController.shared
    @State private var sortOrder: CorpusSortOrder = .name

    /// Recomputed rather than observed: the cache is written by a background run
    /// and by the detail editor, so the filesystem is the only source that is
    /// always right. Refreshed when the corpus changes or a bulk run advances.
    @State private var transcribedHashes: Set<String> = []
    @State private var bambiTranscriptHashes: Set<String> = []

    private var sortedFiles: [LabeledFile] {
        TranscriptInventory.sorted(corpus.labeledFiles, by: sortOrder, transcribed: transcribedHashes)
    }

    private var displayedFiles: [LabeledFile] {
        if labelingSprint.isActive {
            return labelingSprint.queuedFiles(
                from: corpus.labeledFiles,
                bambiTranscriptHashes: bambiTranscriptHashes
            )
        }
        return sortedFiles
    }

    private var transcriptionAvailability: BulkTranscriptionAvailability {
        BulkTranscriptionAvailability(
            files: corpus.labeledFiles,
            transcribedHashes: transcribedHashes
        )
    }

    private var bambiAvailability: BambiDerivedLabelingAvailability {
        BambiDerivedLabelingAvailability(
            files: corpus.labeledFiles,
            transcribedHashes: transcribedHashes
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if labelingSprint.isActive {
                GoldSprintProgressPanel(
                    progress: labelingSprint.progress(in: corpus.labeledFiles),
                    onPause: pauseSprint
                )
            } else {
                GoldSprintLaunchPanel(
                    hasExistingPlan: labelingSprint.hasPlan,
                    progress: labelingSprint.progress(in: corpus.labeledFiles),
                    onStart: beginOrResumeSprint
                )

                CorpusTrainingWorkflowPanel(
                    totalFileCount: corpus.labeledFiles.count,
                    labeledFileCount: corpus.labeledFiles.filter { $0.status != .unlabeled }.count,
                    workflow: workflow
                )

                BambiSafetyPanel(
                    controller: bambiDerivation,
                    availability: bambiAvailability,
                    isBlocked: bulkTranscription.isRunning,
                    onStart: { bambiDerivation.start(corpus: corpus) },
                    onStop: { bambiDerivation.cancel() }
                )

                BulkTranscriptionPanel(
                    controller: bulkTranscription,
                    availability: transcriptionAvailability,
                    isBlocked: bambiDerivation.isRunning,
                    onStart: { bulkTranscription.start(corpus: corpus) },
                    onStop: {
                        bulkTranscription.cancel()
                        refreshTranscribedHashes()
                    }
                )
            }

            List(displayedFiles, selection: $selectedFileID) { file in
                CorpusFileRow(
                    file: file,
                    hasTranscript: transcribedHashes.contains(file.audioSHA256)
                )
                    .tag(file.id)
                    .contextMenu {
                        if !labelingSprint.isActive {
                            Button("Delete", role: .destructive) {
                                Task { await delete(file) }
                            }
                        }
                    }
            }
        }
        .task(id: corpus.labeledFiles.count) { refreshTranscribedHashes() }
        .onChange(of: bulkTranscription.completed) { refreshTranscribedHashes() }
        .onChange(of: bambiDerivation.completed) { refreshTranscribedHashes() }
        .navigationTitle("Corpus")
        .navigationSubtitle(subtitleText)
        .toolbar {
            if !labelingSprint.isActive {
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
        bambiTranscriptHashes = BambiSafetyPolicy.transcriptHashesRequiringTranscriptOnlyLabeling(
            in: corpus.labeledFiles,
            datasetDirectory: corpus.analyzerDatasetDirectory
        )
    }

    private var subtitleText: String {
        if labelingSprint.isActive {
            let progress = labelingSprint.progress(in: corpus.labeledFiles)
            return "Gold sprint · \(progress.completedCount)/\(progress.targetCount)"
        }
        let total = corpus.labeledFiles.count
        let labeled = corpus.labeledFiles.filter { $0.status != .unlabeled }.count
        return "\(labeled)/\(total) labeled"
    }

    private func beginOrResumeSprint() {
        let currentBambiTranscriptHashes =
            BambiSafetyPolicy.transcriptHashesRequiringTranscriptOnlyLabeling(
                in: corpus.labeledFiles,
                datasetDirectory: corpus.analyzerDatasetDirectory
            )
        if labelingSprint.hasPlan {
            selectedFileID = labelingSprint.resume(
                files: corpus.labeledFiles,
                bambiTranscriptHashes: currentBambiTranscriptHashes
            )
        } else {
            selectedFileID = labelingSprint.start(
                files: corpus.labeledFiles,
                targetCount: 25,
                transcribedHashes: transcribedHashes,
                bambiTranscriptHashes: currentBambiTranscriptHashes
            )
        }
    }

    private func pauseSprint() {
        labelingSprint.pause()
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

private struct GoldSprintLaunchPanel: View {
    let hasExistingPlan: Bool
    let progress: LabelingSprintController.Progress
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Gold Sprint", systemImage: "target")
                    .font(.headline)

                Spacer()

                Button(hasExistingPlan ? "Resume" : "Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .disabled(progress.remainingCount == 0)
            }

            Text("\(progress.completedCount) of \(progress.targetCount) gold files")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(12)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

private struct GoldSprintProgressPanel: View {
    let progress: LabelingSprintController.Progress
    let onPause: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Gold Sprint", systemImage: "target")
                    .font(.headline)
                Spacer()
                Button("Pause", action: onPause)
                    .buttonStyle(.bordered)
            }

            ProgressView(value: progress.fractionCompleted)

            HStack {
                Text("\(progress.completedCount) of \(progress.targetCount) gold files")
                Spacer()
                Text("\(progress.remainingCount) remaining")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if progress.deferredCount > 0 {
                Text("\(progress.deferredCount) deferred and replaced")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .controlSize(.small)
        .padding(12)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

struct BulkTranscriptionPanel: View {
    let controller: BulkTranscriptionController
    let availability: BulkTranscriptionAvailability
    let isBlocked: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Transcripts", systemImage: "text.bubble")
                        .font(.headline)
                    Text(availability.summary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if controller.isRunning {
                    Button("Stop", systemImage: "stop.fill", action: onStop)
                        .buttonStyle(.bordered)
                } else {
                    Button(availability.actionTitle, systemImage: "waveform.badge.plus", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .disabled(availability.pendingCount == 0 || isBlocked)
                        .help("Generate transcripts for every file that does not already have one.")
                }
            }

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
        .controlSize(.small)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }
}

struct BambiSafetyPanel: View {
    let controller: BambiDerivedLabelingController
    let availability: BambiDerivedLabelingAvailability
    let isBlocked: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Bambi Safety", systemImage: "shield.fill")
                        .font(.headline)
                    Text(availability.summary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if controller.isRunning {
                    Button("Stop", systemImage: "stop.fill", action: onStop)
                        .buttonStyle(.bordered)
                } else {
                    Button(availability.actionTitle, systemImage: "text.badge.checkmark", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .disabled(availability.pendingCount == 0 || isBlocked)
                }
            }

            Text("Transcript-only · no audio playback · human labels are never overwritten")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if controller.isRunning {
                ProgressView(value: controller.progress)
                Text(controller.currentFilename ?? "Starting…")
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(controller.stage?.rawValue ?? "Preparing") · \(controller.completed) of \(controller.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let statusMessage = controller.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(controller.failures.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
            }

            if availability.protectedHumanCount > 0 {
                Text("\(availability.protectedHumanCount) existing human-labeled file\(availability.protectedHumanCount == 1 ? " is" : "s are") protected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(controller.failures.prefix(3), id: \.filename) { failure in
                Text("\(failure.filename): \(failure.reason)")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .controlSize(.small)
        .padding(12)
        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
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

    @ViewBuilder
    private var statusIcon: some View {
        if BambiSafetyPolicy.isTranscriptOnlySilver(file) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(Color.purple)
                .help("Transcript-only derived silver label — independent review required")
        } else {
            let (icon, color): (String, Color) = switch file.status {
            case .unlabeled: ("circle.dashed", .secondary)
            case .rough:     ("circle.lefthalf.filled", .orange)
            case .refined:   ("checkmark.circle.fill", .green)
            }
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }
}
