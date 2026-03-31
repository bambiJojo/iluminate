//
//  LumeLabelApp.swift
//  LumeLabel
//
//  macOS utility for labeling hypnosis audio files with ground-truth
//  phase annotations. Labels are written to ~/Documents/TrainingCorpus/
//  — the same location read by the evolutionary optimizer test suite.
//

import SwiftUI

@main
struct LumeLabelApp: App {

    @State private var corpus = TrainingCorpusManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(corpus)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
