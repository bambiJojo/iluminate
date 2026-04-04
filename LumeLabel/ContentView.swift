//
//  ContentView.swift
//  LumeLabel
//

import SwiftUI

struct ContentView: View {
    @Environment(TrainingCorpusManager.self) private var corpus
    @State private var selectedFileID: LabeledFile.ID?

    var body: some View {
        NavigationSplitView {
            CorpusSidebarView(selectedFileID: $selectedFileID)
        } detail: {
            if let selectedFileID, corpus.file(withID: selectedFileID) != nil {
                LabelingDetailView(fileID: selectedFileID)
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
    }
}
