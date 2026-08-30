//
//  ContentView.swift
//  LumeLabel
//

import SwiftUI

struct ContentView: View {
    @Environment(TrainingCorpusManager.self) private var corpus
    @Environment(LabelingSprintController.self) private var labelingSprint
    @State private var selectedFileID: LabeledFile.ID?

    var body: some View {
        NavigationSplitView {
            CorpusSidebarView(selectedFileID: $selectedFileID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let selectedFileID, corpus.file(withID: selectedFileID) != nil {
                LabelingDetailView(
                    fileID: selectedFileID,
                    onSavedAndNext: advanceAfterSaving,
                    onDefer: deferFile
                )
                    .id(selectedFileID)
            } else {
                ContentUnavailableView(
                    "No File Selected",
                    systemImage: "waveform.path.ecg",
                    description: Text("Import an audio file from the sidebar, then select it to begin labeling.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: corpus.labeledFiles.count) {
            guard labelingSprint.isActive else { return }
            if let selectedFileID, corpus.file(withID: selectedFileID) != nil {
                return
            }
            selectedFileID = labelingSprint.resume(
                files: corpus.labeledFiles,
                bambiTranscriptHashes: bambiTranscriptHashes
            )
        }
        .onChange(of: labelingSprint.isActive) {
            guard labelingSprint.isActive else { return }
            if let selectedFileID, corpus.file(withID: selectedFileID) != nil {
                return
            }
            selectedFileID = labelingSprint.resume(
                files: corpus.labeledFiles,
                bambiTranscriptHashes: bambiTranscriptHashes
            )
        }
    }

    private func advanceAfterSaving(_ fileID: LabeledFile.ID) {
        selectedFileID = labelingSprint.advanceAfterSaving(
            fileID: fileID,
            files: corpus.labeledFiles,
            bambiTranscriptHashes: bambiTranscriptHashes
        )
    }

    private func deferFile(_ fileID: LabeledFile.ID) {
        let transcribedHashes = TranscriptInventory.availableHashes(
            in: corpus.analyzerDatasetDirectory
        )
        selectedFileID = labelingSprint.deferFile(
            fileID: fileID,
            files: corpus.labeledFiles,
            transcribedHashes: transcribedHashes,
            bambiTranscriptHashes: bambiTranscriptHashes
        )
    }

    private var bambiTranscriptHashes: Set<String> {
        BambiSafetyPolicy.transcriptHashesRequiringTranscriptOnlyLabeling(
            in: corpus.labeledFiles,
            datasetDirectory: corpus.analyzerDatasetDirectory
        )
    }
}
