//
//  ContentView.swift
//  LumeLabel
//

import SwiftUI

struct ContentView: View {

    @Environment(TrainingCorpusManager.self) private var corpus
    @State private var selectedFile: LabeledFile?

    var body: some View {
        NavigationSplitView {
            CorpusSidebarView(selectedFile: $selectedFile)
        } detail: {
            if let file = selectedFile {
                LabelingDetailView(file: file)
                    .id(file.id)
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
